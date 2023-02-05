unit UnitMainGenerator;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ActiveX,
  Winapi.DirectShow9,
  System.SysUtils, System.Variants, System.Classes, System.IniFiles,
  System.IOUtils,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.Mask,
  Winapi.CoreAudioApi.AudioClient, Winapi.CoreAudioApi.MMDeviceApi,
  Winapi.ActiveX.PropSys, Winapi.CoreAudioApi.AudioSessionTypes,
  Winapi.DevpKey, Winapi.CoreAudioApi.FunctionDiscoveryKeys_devpkey,
  Winapi.CoreAudioApi.MMDevApiUtils, Winapi.WinMM.MMReg,
  UnitOneDevice, UnitOneText, UnitGenerators;

type
  TIni_params = record
    DesiredDevice: string;
    SelectedDevice: string;
    SelectedDeviceNum: integer;
    SelectedMode: integer;
  end;

  TOutputThread = class(TThread)
  private
    procedure AddToLog(instring: string);
    procedure CheckAndRaiseIfFailed(hr: HResult; ErrorString: string);
  protected
    procedure Execute; override;
  public
    SelectedCardID: String;
    InitialTimecode: String;
    CurrentTimecode: String;
    FinalTimecode: String;
    LoopEnabled: boolean;
    FPSnum, FPSden: integer;
    OutputText: TTLtext_list;
  end;

  TFormTCgenerator = class(TForm)
    PanelTC: TPanel;
    ButtonStartStop: TButton;
    ComboBoxDevice: TComboBox;
    LabelDevice: TLabel;
    ComboBoxFormat: TComboBox;
    LabelFormat: TLabel;
    MaskEditStart: TMaskEdit;
    MaskEditEnd: TMaskEdit;
    LabelStart: TLabel;
    LabelEnd: TLabel;
    Memo1: TMemo;
    Timer1: TTimer;
    CheckBoxLoop: TCheckBox;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure ComboBoxDeviceChange(Sender: TObject);
    procedure ComboBoxFormatChange(Sender: TObject);
    procedure ButtonStartStopClick(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure FormResize(Sender: TObject);
  private
    Ini_params: TIni_params;
    OutputText: TTLtext_list;
    OutputThread: TOutputThread;
    isStarted: boolean;
    //
    procedure EnumerateDevices;
    procedure Start;
    procedure Stop;
    //
    procedure AddToLog(instring: string);
    procedure CheckAndRaiseIfFailed(hr: HResult; ErrorString: string);
  public
    { Public declarations }
  end;

  EMyOwnException = class(Exception);

var
  FormTCgenerator: TFormTCgenerator;

implementation

{$R *.dfm}
{ TFormTCgenerator }

procedure TFormTCgenerator.AddToLog(instring: string);
begin
  if not Assigned(OutputText) then
    Exit;

  OutputText.Add(TOne_text.Create(instring));
end;

procedure TFormTCgenerator.ButtonStartStopClick(Sender: TObject);
begin
  if isStarted then
    Stop
  else
    Start;
end;

procedure TFormTCgenerator.CheckAndRaiseIfFailed(hr: HResult;
  ErrorString: string);
var
  ErrMsg: string;
begin
  if hr <> S_OK then
  begin
    SetLength(ErrMsg, 512);
    AMGetErrorText(hr, PChar(ErrMsg), 512);
    raise EMyOwnException.Create(ErrorString + Trim(ErrMsg));
  end;
end;

procedure TFormTCgenerator.ComboBoxDeviceChange(Sender: TObject);
begin
  Ini_params.SelectedDeviceNum := ComboBoxDevice.ItemIndex;
  Ini_params.SelectedDevice :=
    (ComboBoxDevice.Items.Objects[ComboBoxDevice.ItemIndex] as TOneDevice).Name;
end;

procedure TFormTCgenerator.ComboBoxFormatChange(Sender: TObject);
begin
  Ini_params.SelectedMode := ComboBoxFormat.ItemIndex;
end;

procedure TFormTCgenerator.EnumerateDevices;
var
  MMDevEnum: IMMDeviceEnumerator;
  MMDevCollection: TEndPointDeviceArray;

  num_devices: Cardinal;
  i: integer;
  in_device: TOneDevice;
begin
  try
    CoInitializeEx(nil, COINIT_APARTMENTTHREADED);

    CheckAndRaiseIfFailed(CoCreateInstance(CLSID_MMDeviceEnumerator, nil,
      CLSCTX_ALL, IID_IMMDeviceEnumerator, MMDevEnum),
      'Cannot CoCreateInstance');

    CheckAndRaiseIfFailed(GetEndpointDevices(eRender, DEVICE_STATE_ACTIVE,
      MMDevCollection, num_devices), 'Cannot enumerate audio devices');

    for i := 0 to num_devices - 1 do
    begin
      in_device := TOneDevice.Create;
      in_device.Name := MMDevCollection[i].DeviceName;
      in_device.Channels := 2;
      in_device.wasapi_device_id := MMDevCollection[i].pwszID;

      ComboBoxDevice.AddItem(in_device.Name, in_device);
    end;

  except
    on E: EMyOwnException do
    begin
      AddToLog(E.Message);
    end;
    else
      AddToLog('Неизвестная ошибка');
  end;
end;

procedure TFormTCgenerator.FormCreate(Sender: TObject);
var
  ini: TIniFile;
  i: integer;
  tmpstr: string;
  BuildTime: TDateTime;
begin
  Memo1.Clear;

  BuildTime := TFile.GetLastWriteTime(paramstr(0));
  Self.Caption := 'TC Generator (build ' + FormatDateTime('yyyy-mm-dd hh:nn:ss',
    BuildTime) + ')';

  Self.DoubleBuffered := true;

  ini := TIniFile.Create(extractfilepath(paramstr(0)) + 'settings.ini');
  try
    tmpstr := ini.ReadString('device', 'name', '');
    Ini_params.DesiredDevice := StringReplace(tmpstr, '"', '', [rfReplaceAll]);
    Ini_params.SelectedMode := ini.ReadInteger('common', 'mode', 0);
    ComboBoxFormat.ItemIndex := Ini_params.SelectedMode;
    CheckBoxLoop.Checked := ini.ReadBool('common', 'loop', true);

    MaskEditStart.Text := ini.ReadString('common', 'start', '00:00:00:00');
    MaskEditEnd.Text := ini.ReadString('common', 'end', '00:00:00:00');

    Self.Left := ini.ReadInteger('position', 'left', Self.Left);
    Self.Top := ini.ReadInteger('position', 'top', Self.Top);
    Self.Width := ini.ReadInteger('position', 'width', Self.Width);
    Self.Height := ini.ReadInteger('position', 'height', Self.Height);
  finally
    ini.Free;
  end;

  ComboBoxDevice.Clear;

  EnumerateDevices;

  OutputText := TTLtext_list.Create;

  Ini_params.SelectedDeviceNum := -1;
  for i := 0 to ComboBoxDevice.Items.Count - 1 do
  begin
    if SameText(ComboBoxDevice.Items.Strings[i], Ini_params.DesiredDevice) then
    begin
      Ini_params.SelectedDevice := ComboBoxDevice.Items.Strings[i];
      Ini_params.SelectedDeviceNum := i;
    end;
  end;

  if Ini_params.SelectedDeviceNum >= 0 then
  begin
    ComboBoxDevice.ItemIndex := Ini_params.SelectedDeviceNum;
  end
  else
  begin
    if ComboBoxDevice.Items.Count > 0 then
      ComboBoxDevice.ItemIndex := 0;
  end;

  ComboBoxDeviceChange(Self);

  if Ini_params.SelectedDeviceNum >= 0 then
    ButtonStartStop.Enabled := true;
end;

procedure TFormTCgenerator.FormResize(Sender: TObject);
begin
  Memo1.Width := Self.ClientWidth - 2 * Memo1.Left;
  Memo1.Height := Self.ClientHeight - Memo1.Top - Memo1.Left;
end;

procedure TFormTCgenerator.FormClose(Sender: TObject; var Action: TCloseAction);
var
  ini: TIniFile;
begin
  if Assigned(OutputThread) then
    Stop;

  ini := TIniFile.Create(extractfilepath(paramstr(0)) + 'settings.ini');
  try
    ini.WriteString('device', 'name', Ini_params.SelectedDevice);

    ini.WriteInteger('common', 'mode', Ini_params.SelectedMode);

    ini.WriteString('common', 'start', MaskEditStart.Text);
    ini.WriteString('common', 'end', MaskEditEnd.Text);
    ini.WriteBool('common', 'loop', CheckBoxLoop.Checked);

    ini.WriteInteger('position', 'left', Self.Left);
    ini.WriteInteger('position', 'top', Self.Top);
    ini.WriteInteger('position', 'width', Self.Width);
    ini.WriteInteger('position', 'height', Self.Height);
  finally
    ini.Free;
  end;

end;

procedure TFormTCgenerator.Start;
var
  RenderDevice: TOneDevice;
begin
  RenderDevice := TOneDevice(ComboBoxDevice.Items.Objects
    [Ini_params.SelectedDeviceNum]);

  if not Assigned(RenderDevice) then
    Exit;

  OutputThread := TOutputThread.Create(true);
  OutputThread.SelectedCardID := RenderDevice.wasapi_device_id;
  OutputThread.OutputText := OutputText;
  OutputThread.InitialTimecode := MaskEditStart.Text;
  OutputThread.FinalTimecode := MaskEditEnd.Text;
  OutputThread.LoopEnabled := CheckBoxLoop.Checked;

  case Ini_params.SelectedMode of
    0: // 25
      begin
        OutputThread.FPSnum := 25;
        OutputThread.FPSden := 1;
      end;
    1: // 24
      begin
        OutputThread.FPSnum := 24;
        OutputThread.FPSden := 1;
      end;
    2: // 30
      begin
        OutputThread.FPSnum := 30;
        OutputThread.FPSden := 1;
      end;
    3: // 29.97DF
      begin
        OutputThread.FPSnum := 30000;
        OutputThread.FPSden := 1001;
      end;
  else
    begin
      OutputThread.FPSnum := 25;
      OutputThread.FPSden := 1;
    end;
  end;

  OutputThread.FreeOnTerminate := false;
  OutputThread.Priority := tpTimeCritical;
  OutputThread.Start;

  Sleep(500);
  if OutputThread.Finished then
    Exit;

  isStarted := true;
  ButtonStartStop.Caption := 'Stop';

  ComboBoxDevice.Enabled := false;
  ComboBoxFormat.Enabled := false;
  MaskEditStart.Enabled := false;
  MaskEditEnd.Enabled := false;
  CheckBoxLoop.Enabled := false;
end;

procedure TFormTCgenerator.Stop;
begin
  if Assigned(OutputThread) then
  begin
    OutputThread.Terminate;
    while not OutputThread.Finished do
      Sleep(10);
    OutputThread.Free;
    OutputThread := nil;
  end;

  isStarted := false;
  ButtonStartStop.Caption := 'Start';

  ComboBoxDevice.Enabled := true;
  ComboBoxFormat.Enabled := true;
  MaskEditStart.Enabled := true;
  MaskEditEnd.Enabled := true;
  CheckBoxLoop.Enabled := true;
end;

procedure TFormTCgenerator.Timer1Timer(Sender: TObject);
var
  tmp_log_list: TLtext_list;
  tmp_msg: TOne_text;
begin
  if Assigned(OutputText) then
  begin
    tmp_log_list := OutputText.LockList;
    while tmp_log_list.Count > 0 do
    begin
      tmp_msg := tmp_log_list.Items[0];
      tmp_log_list.Delete(0);
      Memo1.Lines.Add(tmp_msg.Text);
      tmp_msg.Free;
    end;
    OutputText.UnLockList;
  end;

  if Assigned(OutputThread) then
    PanelTC.Caption := OutputThread.CurrentTimecode;
end;

{ TInputRecordThread }

procedure TOutputThread.AddToLog(instring: string);
begin
  if not Assigned(OutputText) then
    Exit;

  OutputText.Add(TOne_text.Create(instring));
end;

procedure TOutputThread.CheckAndRaiseIfFailed(hr: HResult; ErrorString: string);
var
  ErrMsg: string;
begin
  if hr <> S_OK then
  begin
    SetLength(ErrMsg, 512);
    AMGetErrorText(hr, PChar(ErrMsg), 512);
    raise EMyOwnException.Create(ErrorString + Trim(ErrMsg));
  end;
end;

procedure TOutputThread.Execute;
const
  REFTIMES_PER_SEC = 10000000;
var
  MMDevEnum: IMMDeviceEnumerator;
  MMDev: IMMDevice;
  AudioClient: IAudioClient;
  RenderClient: IAudioRenderClient;

  pWfx, pCloseWfx: PWAVEFORMATEX;
  pEx: PWaveFormatExtensible;

  tmpID: PWideChar;
  BufferFrameCount, numFramesAvailable, Flags, StreamFlags, numFramesPadding
    : Cardinal;
  hnsRequestedDuration: Int64;
  pData: PByte;
  TCGenerator: TGenerators;
begin
  inherited;

  TCGenerator := TGenerators.Create;
  TCGenerator.SetFrameRate(FPSnum, FPSden);

  pCloseWfx := nil;

  try
    CoInitializeEx(nil, COINIT_APARTMENTTHREADED);

    CheckAndRaiseIfFailed(CoCreateInstance(CLSID_MMDeviceEnumerator, nil,
      CLSCTX_ALL, IID_IMMDeviceEnumerator, MMDevEnum),
      'Cannot CoCreateInstance CLSID_MMDeviceEnumerator');

    tmpID := PWideChar(SelectedCardID);
    CheckAndRaiseIfFailed(GetEndPointDeviceByID(tmpID, MMDev),
      'Cannot get selected device');

    CheckAndRaiseIfFailed(MMDev.Activate(IID_IAudioClient, CLSCTX_ALL, nil,
      Pointer(AudioClient)), 'Cannot activate device');

    CheckAndRaiseIfFailed(AudioClient.GetMixFormat(pWfx),
      'Cannot get mix format');

    // http://www.ambisonic.net/mulchaud.html
    case pWfx.wFormatTag of
      WAVE_FORMAT_IEEE_FLOAT:
        begin
          pWfx.wFormatTag := WAVE_FORMAT_PCM;
          pWfx.wBitsPerSample := 16;
          pWfx.nBlockAlign := pWfx.nChannels * pWfx.wBitsPerSample div 8;
          pWfx.nAvgBytesPerSec := pWfx.nBlockAlign * pWfx.nSamplesPerSec;
        end;
      WAVE_FORMAT_EXTENSIBLE:
        begin
          pEx := PWaveFormatExtensible(pWfx);

          if not IsEqualGUID(KSDATAFORMAT_SUBTYPE_IEEE_FLOAT, pEx.SubFormat)
          then
            raise EMyOwnException.Create('Unknown SubFormat GUID - ' +
              GUIDToString(pEx.SubFormat));

          pEx.SubFormat := KSDATAFORMAT_SUBTYPE_PCM;
          pEx.Samples.wValidBitsPerSample := 16;
          pWfx.wBitsPerSample := 16;
          pWfx.nBlockAlign := pWfx.nChannels * pWfx.wBitsPerSample div 8;
          pWfx.nAvgBytesPerSec := pWfx.nBlockAlign * pWfx.nSamplesPerSec;
        end;
    else
      Exit;
    end;

    GetMem(pCloseWfx, SizeOf(WaveFormatExtensible));

    CheckAndRaiseIfFailed(AudioClient.IsFormatSupported
      (AUDCLNT_SHAREMODE_SHARED, pWfx, pCloseWfx), 'Cannot set format');

    AddToLog('Sample frequency: ' + pWfx.nSamplesPerSec.ToString);

    TCGenerator.sample_rate := pWfx.nSamplesPerSec;
    TCGenerator.SetInititialTimeCode(InitialTimecode);
    TCGenerator.SetEndTimeCode(FinalTimecode);
    TCGenerator.LoopEnabled := LoopEnabled;

    CurrentTimecode := TCGenerator.TCasString;

    hnsRequestedDuration := REFTIMES_PER_SEC div 25;
    StreamFlags := 0;
    CheckAndRaiseIfFailed(AudioClient.Initialize(AUDCLNT_SHAREMODE_SHARED,
      StreamFlags, hnsRequestedDuration, 0, pWfx, nil),
      'Cannot initialize AudioClient');

    CheckAndRaiseIfFailed(AudioClient.GetBufferSize(BufferFrameCount),
      'Cannot GetBufferSize');

    CheckAndRaiseIfFailed(AudioClient.GetService(IID_IAudioRenderClient,
      RenderClient), 'Cannot GetService');

    CheckAndRaiseIfFailed(RenderClient.GetBuffer(BufferFrameCount, @pData),
      'Error GetBuffer');

    TCGenerator.FillBuffer(PSmallInt(pData), pWfx.nChannels, BufferFrameCount);

    Flags := 0;
    CheckAndRaiseIfFailed(RenderClient.ReleaseBuffer(BufferFrameCount, Flags),
      'Error ReleaseBuffer');

    // Start playing
    AudioClient.Start();

    while not Terminated do
    begin
      // Sleep for 1/4 the buffer duration.
      Sleep(BufferFrameCount * 250 div pWfx.nSamplesPerSec);

      // See how much buffer space is available.
      CheckAndRaiseIfFailed(AudioClient.GetCurrentPadding(numFramesPadding),
        'Cannot GetCurrentPadding');

      numFramesAvailable := BufferFrameCount - numFramesPadding;

      // Grab all the available space in the shared buffer.
      CheckAndRaiseIfFailed(RenderClient.GetBuffer(numFramesAvailable, @pData),
        'Error GetBuffer');

      TCGenerator.FillBuffer(PSmallInt(pData), pWfx.nChannels,
        numFramesAvailable);

      Flags := 0;
      CheckAndRaiseIfFailed(RenderClient.ReleaseBuffer(numFramesAvailable,
        Flags), 'Error ReleaseBuffer');

      CurrentTimecode := TCGenerator.TCasString;
    end;

    // Sleep for 1/4 the buffer duration.
    Sleep(BufferFrameCount * 250 div pWfx.nSamplesPerSec);

    // Останавливаем воспроизведение
    AudioClient.Stop();

  except
    on E: EMyOwnException do
    begin
      AddToLog(E.Message);
    end;
    else
      AddToLog('Неизвестная ошибка');
  end;

  if Assigned(TCGenerator) then
    TCGenerator.Free;

  if Assigned(pWfx) then
    CoTaskMemFree(pWfx);

  if Assigned(pCloseWfx) then
    FreeMem(pCloseWfx);
end;

end.
