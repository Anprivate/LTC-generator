unit UnitOneDevice;

interface

uses
  MMDeviceAPI;

type
  TOneDevice = class(TObject)
    Name: string;
    Channels: integer;
    wasapi_device_id: string;
  end;

implementation

{ TOneDevice }

end.
