unit UnitGenerators;

interface

uses
  System.SysUtils, System.StrUtils;

type
  TData16 = array [0 .. 16383] of smallint;
  PData16 = ^TData16;

  TinternalTC = record
    h, m, s, f: byte;
  end;

  TGenerators = class(TObject)
  private
    InternalTC: array [0 .. 9] of byte;
    intFPSnom, intFPSden, intBaseFPS: integer;
    isFPS_DF: boolean;
    //
    curr_frame_num: Int64;
    curr_position_in_frame: Int64;
    curr_frame_duration: Int64;
    curr_prev_half: Int64;
    curr_out_level: boolean;
    transfer_phase: integer;
    curr_tc: TinternalTC;
    start_tc: TinternalTC;
    end_tc: TinternalTC;

    function DurationFromFrameNumber(FrameNumber: Int64): Int64;

  public
    TCasString: string;
    sample_rate: Int64;
    LoopEnabled: boolean;
    procedure SetInititialTimeCode(InTC: String);
    procedure SetEndTimeCode(InTC: String);
    procedure NextTimeCode;
    procedure CorrectParity;
    function SetFrameRate(fps_num, fps_den: integer): boolean;
    function GenerateAudioFrame(Duration: integer): PData16;
    procedure FillBuffer(out_pointer: PSmallInt; channels: integer;
      samples_required: integer);
  end;

implementation

function NOD(A, b: integer): integer;
var
  i: integer;
begin
  repeat
    if A > b then
    // Меняем a и b местами, чтобы a было < b
    begin
      i := A;
      A := b;
      b := i;
    end;

    repeat
      b := b - A;
    until (b = 0) Or (b < A);
    Result := A;
  until (b = 0);
end;

{ TGenerators }

procedure TGenerators.CorrectParity;
var
  counter: integer;
  i, i1: integer;
  phase: byte;
begin
  // clear bits 27, 43, 59
  InternalTC[3] := InternalTC[3] and not $08;
  InternalTC[5] := InternalTC[5] and not $08;
  InternalTC[7] := InternalTC[7] and not $08;

  counter := 0;

  for i := 0 to 9 do
  begin
    phase := $01;

    for i1 := 0 to 7 do
    begin
      if (InternalTC[i] and phase) <> 0 then
        inc(counter);
      phase := phase shl 1;
    end;
  end;

  if (counter mod 2) <> 0 then
  begin
    // "Polarity correction bit" (bit 59 at 25 frame/s, bit 27 at other rates):
    if (intFPSnom = 25) and (intFPSden = 1) then
      InternalTC[7] := InternalTC[7] or $08
    else
      InternalTC[3] := InternalTC[3] or $08;
  end;
end;

function TGenerators.DurationFromFrameNumber(FrameNumber: Int64): Int64;
var
  curr_frame_start, next_frame_start: Int64;
begin
  curr_frame_start := FrameNumber * sample_rate * intFPSden div intFPSnom;
  next_frame_start := (FrameNumber + 1) * sample_rate * intFPSden div intFPSnom;
  Result := next_frame_start - curr_frame_start;
end;

procedure TGenerators.FillBuffer(out_pointer: PSmallInt;
  channels, samples_required: integer);
var
  i, i1: integer;
  full_half, curr_half: Int64;
  curr_bit, curr_byte: integer;
  tmp_out_ptr: PSmallInt;
  level, tmp_level: Int16;
begin
  if not Assigned(out_pointer) then
    Exit;

  tmp_out_ptr := out_pointer;
  for i := 0 to samples_required - 1 do
  begin
    full_half := (curr_position_in_frame * 160) div curr_frame_duration;
    curr_half := full_half mod 2;

    if curr_half <> curr_prev_half then
    begin
      if curr_half = 0 then
      begin
        // it is start of period - always jump on output
        curr_out_level := not curr_out_level;
        transfer_phase := 0;
      end
      else
      begin
        // it is a middle of period - jump only if 1
        curr_bit := (full_half div 2) mod 8;
        curr_byte := (full_half div 2) div 8;

        if (InternalTC[curr_byte] and (1 shl curr_bit)) <> 0 then
        begin
          curr_out_level := not curr_out_level;
          transfer_phase := 0;
        end;
      end;
      curr_prev_half := curr_half;
    end;

    case transfer_phase of
      0:
        begin
          tmp_level := -18607;
          inc(transfer_phase);
        end;
      1:
        begin
          tmp_level := -7169;
          inc(transfer_phase);
        end;
      2:
        begin
          tmp_level := 7169;
          inc(transfer_phase);
        end;
      3:
        begin
          tmp_level := 18607;
          inc(transfer_phase);
        end;
    else
      tmp_level := 23200;
    end;

    if curr_out_level then
      level := tmp_level
    else
      level := -tmp_level;

    for i1 := 0 to channels - 1 do
    begin
      tmp_out_ptr^ := level;
      inc(tmp_out_ptr);
    end;

    inc(curr_position_in_frame);
    if curr_position_in_frame >= curr_frame_duration then
    begin
      inc(curr_frame_num);
      NextTimeCode;
      curr_position_in_frame := 0;
      curr_frame_duration := DurationFromFrameNumber(curr_frame_num);
    end;
  end;

end;

// ATTENTION OBSOLETE VERSION - recheck before use
function TGenerators.GenerateAudioFrame(Duration: integer): PData16;
var
  tmpptr: PData16;
  i: integer;
  curr_byte, curr_bit, curr_half, full_half: integer;
  prev_half: integer;
  curr_out_level: boolean;
  isOne: boolean;
begin
  GetMem(tmpptr, Duration * 2);
  prev_half := 1;
  curr_out_level := false;
  for i := 0 to Duration - 1 do
  begin
    full_half := (i * 160) div Duration;

    curr_half := full_half mod 2;

    if curr_half <> prev_half then
    begin
      if curr_half = 0 then
      begin
        // it is start of period - always jump on output
        curr_out_level := not curr_out_level;
      end
      else
      begin
        // it is a middle of period - jump only if 1
        curr_bit := (full_half div 2) mod 8;
        curr_byte := (full_half div 2) div 8;

        isOne := (InternalTC[curr_byte] and (1 shl curr_bit)) <> 0;

        if isOne then
          curr_out_level := not curr_out_level;
      end;
      prev_half := curr_half;
    end;

    if curr_out_level then
      tmpptr[i] := 23200
    else
      tmpptr[i] := -23200;
  end;

  Result := tmpptr;
end;

procedure TGenerators.NextTimeCode;
begin
  // frames
  curr_tc.f := (InternalTC[0] and $0F) + 10 * (InternalTC[1] and $03);
  curr_tc.s := (InternalTC[2] and $0F) + 10 * (InternalTC[3] and $07);
  curr_tc.m := (InternalTC[4] and $0F) + 10 * (InternalTC[5] and $07);
  curr_tc.h := (InternalTC[6] and $0F) + 10 * (InternalTC[7] and $03);

  inc(curr_tc.f);
  if curr_tc.f >= intBaseFPS then
  begin
    curr_tc.f := 0;
    inc(curr_tc.s);
    if curr_tc.s >= 60 then
    begin
      curr_tc.s := 0;
      inc(curr_tc.m);
      if curr_tc.m >= 60 then
      begin
        curr_tc.m := 0;
        inc(curr_tc.h);
        if curr_tc.h >= 24 then
          curr_tc.h := 0;
      end;
    end;
  end;

  // frame numbers 0 and 1 are skipped during the first second of every minute, except multiples of 10 minutes
  if isFPS_DF and (curr_tc.f < 2) and (curr_tc.s = 0) and
    not((curr_tc.m mod 10) = 0) then
    curr_tc.f := 2;

  if LoopEnabled and (curr_tc.h = end_tc.h) and (curr_tc.m = end_tc.m) and
    (curr_tc.s = end_tc.s) and (curr_tc.f = end_tc.f) then
  begin
    curr_tc.h := start_tc.h;
    curr_tc.m := start_tc.m;
    curr_tc.s := start_tc.s;
    curr_tc.f := start_tc.f;
  end;

  TCasString := format('%2.2d:%2.2d:%2.2d:%2.2d',
    [curr_tc.h, curr_tc.m, curr_tc.s, curr_tc.f]);

  InternalTC[0] := (InternalTC[0] and not $0F) or ((curr_tc.f mod 10) and $0F);
  InternalTC[1] := (InternalTC[1] and not $03) or ((curr_tc.f div 10) and $03);

  InternalTC[2] := (InternalTC[2] and not $0F) or ((curr_tc.s mod 10) and $0F);
  InternalTC[3] := (InternalTC[3] and not $07) or ((curr_tc.s div 10) and $07);

  InternalTC[4] := (InternalTC[4] and not $0F) or ((curr_tc.m mod 10) and $0F);
  InternalTC[5] := (InternalTC[5] and not $07) or ((curr_tc.m div 10) and $07);

  InternalTC[6] := (InternalTC[6] and not $0F) or ((curr_tc.h mod 10) and $0F);
  InternalTC[7] := (InternalTC[7] and not $03) or ((curr_tc.h div 10) and $03);

  CorrectParity();
end;

procedure TGenerators.SetEndTimeCode(InTC: String);
var
  tmp_i: integer;
begin
  end_tc.h := 0;
  end_tc.m := 0;
  end_tc.s := 0;
  end_tc.f := 0;

  if trystrtoint(MidStr(InTC, 1, 2), tmp_i) then
    end_tc.h := tmp_i;
  if trystrtoint(MidStr(InTC, 4, 2), tmp_i) then
    end_tc.m := tmp_i;
  if trystrtoint(MidStr(InTC, 7, 2), tmp_i) then
    end_tc.s := tmp_i;
  if trystrtoint(MidStr(InTC, 10, 2), tmp_i) then
    end_tc.f := tmp_i;
end;

function TGenerators.SetFrameRate(fps_num, fps_den: integer): boolean;
var
  lnod: integer;
begin
  Result := false;

  lnod := NOD(fps_num, fps_den);
  intFPSnom := fps_num div lnod;
  intFPSden := fps_den div lnod;

  isFPS_DF := (intFPSnom = 30000) and (intFPSden = 1001);

  if isFPS_DF then
    intBaseFPS := 30
  else
    intBaseFPS := intFPSnom;

  if (intFPSden = 1) and (intFPSnom in [24, 25, 30]) then
    Result := true;

  if isFPS_DF then
    Result := true;
end;

procedure TGenerators.SetInititialTimeCode(InTC: String);
var
  tmp_b: byte;
  i: integer;
begin
  TCasString := InTC;;

  for i := 0 to Length(InternalTC) - 1 do
    InternalTC[i] := 0;

  // hours
  tmp_b := Ord(InTC[1]);

  if (tmp_b >= Ord('0')) and (tmp_b <= Ord('2')) then
    tmp_b := tmp_b - Ord('0')
  else
    tmp_b := 0;

  InternalTC[7] := tmp_b and $03;
  start_tc.h := InternalTC[7] * 10;

  tmp_b := Ord(InTC[2]);

  if (tmp_b >= Ord('0')) and (tmp_b <= Ord('9')) then
    tmp_b := tmp_b - Ord('0')
  else
    tmp_b := 0;

  InternalTC[6] := tmp_b and $0F;
  start_tc.h := start_tc.h + InternalTC[6];

  // minutes
  tmp_b := Ord(InTC[4]);

  if (tmp_b >= Ord('0')) and (tmp_b <= Ord('5')) then
    tmp_b := tmp_b - Ord('0')
  else
    tmp_b := 0;

  InternalTC[5] := tmp_b and $07;
  start_tc.m := InternalTC[5] * 10;

  tmp_b := Ord(InTC[5]);

  if (tmp_b >= Ord('0')) and (tmp_b <= Ord('9')) then
    tmp_b := tmp_b - Ord('0')
  else
    tmp_b := 0;

  InternalTC[4] := tmp_b and $0F;
  start_tc.m := start_tc.m + InternalTC[4];

  // seconds
  tmp_b := Ord(InTC[7]);

  if (tmp_b >= Ord('0')) and (tmp_b <= Ord('5')) then
    tmp_b := tmp_b - Ord('0')
  else
    tmp_b := 0;

  InternalTC[3] := tmp_b and $07;
  start_tc.s := InternalTC[3] * 10;

  tmp_b := Ord(InTC[8]);

  if (tmp_b >= Ord('0')) and (tmp_b <= Ord('9')) then
    tmp_b := tmp_b - Ord('0')
  else
    tmp_b := 0;

  InternalTC[2] := tmp_b and $0F;
  start_tc.s := start_tc.s + InternalTC[2];

  // frames
  tmp_b := Ord(InTC[10]);

  if (tmp_b >= Ord('0')) and (tmp_b <= Ord('2')) then
    tmp_b := tmp_b - Ord('0')
  else
    tmp_b := 0;

  InternalTC[1] := tmp_b and $03;
  start_tc.f := InternalTC[1] * 10;

  tmp_b := Ord(InTC[11]);

  if (tmp_b >= Ord('0')) and (tmp_b <= Ord('9')) then
    tmp_b := tmp_b - Ord('0')
  else
    tmp_b := 0;

  InternalTC[0] := tmp_b and $0F;
  start_tc.f := start_tc.f + InternalTC[0];

  // synchro word
  InternalTC[8] := $FC;
  InternalTC[9] := $BF;

  // Bit 10 is set to 1 if drop frame numbering is in use;
  // frame numbers 0 and 1 are skipped during the first second of every minute,
  // except multiples of 10 minutes.
  // This converts 30 frame/second time code to the 29.97 frame/second NTSC standard
  if (intFPSnom = 30000) and (intFPSden = 1001) then
    InternalTC[1] := InternalTC[1] or $04;

  CorrectParity();

  curr_frame_num := 0;
  curr_position_in_frame := 0;
  curr_frame_duration := DurationFromFrameNumber(curr_frame_num);
  curr_prev_half := 1;
  curr_out_level := false;
end;

end.
