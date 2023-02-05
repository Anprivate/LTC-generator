object FormTCgenerator: TFormTCgenerator
  Left = 0
  Top = 0
  Caption = 'FormTCgenerator'
  ClientHeight = 299
  ClientWidth = 635
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnClose = FormClose
  OnCreate = FormCreate
  OnResize = FormResize
  PixelsPerInch = 96
  TextHeight = 13
  object LabelDevice: TLabel
    Left = 8
    Top = 13
    Width = 36
    Height = 13
    Caption = 'Device:'
  end
  object LabelFormat: TLabel
    Left = 8
    Top = 45
    Width = 38
    Height = 13
    Caption = 'Format:'
  end
  object LabelStart: TLabel
    Left = 8
    Top = 87
    Width = 28
    Height = 13
    Caption = 'Start:'
  end
  object LabelEnd: TLabel
    Left = 211
    Top = 87
    Width = 22
    Height = 13
    Caption = 'End:'
  end
  object PanelTC: TPanel
    Left = 367
    Top = 14
    Width = 217
    Height = 41
    Caption = '00:00:00:00'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -32
    Font.Name = 'Arial'
    Font.Pitch = fpFixed
    Font.Style = []
    ParentFont = False
    TabOrder = 0
  end
  object ButtonStartStop: TButton
    Left = 264
    Top = 8
    Width = 89
    Height = 55
    Caption = 'Start'
    Enabled = False
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -19
    Font.Name = 'MS Sans Serif'
    Font.Style = []
    ParentFont = False
    TabOrder = 1
    OnClick = ButtonStartStopClick
  end
  object ComboBoxDevice: TComboBox
    Left = 64
    Top = 10
    Width = 185
    Height = 21
    Style = csDropDownList
    TabOrder = 2
    OnChange = ComboBoxDeviceChange
  end
  object ComboBoxFormat: TComboBox
    Left = 64
    Top = 42
    Width = 185
    Height = 21
    Style = csDropDownList
    TabOrder = 3
    OnChange = ComboBoxFormatChange
    Items.Strings = (
      '25 fps'
      '24 fps'
      '30 fps'
      '29.97DF fps')
  end
  object MaskEditStart: TMaskEdit
    Left = 64
    Top = 79
    Width = 116
    Height = 27
    Alignment = taCenter
    EditMask = '00\:00\:00\:00;1;_'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -16
    Font.Name = 'Tahoma'
    Font.Style = []
    MaxLength = 11
    ParentFont = False
    TabOrder = 4
    Text = '  :  :  :  '
  end
  object MaskEditEnd: TMaskEdit
    Left = 247
    Top = 79
    Width = 116
    Height = 27
    Alignment = taCenter
    EditMask = '00\:00\:00\:00;1;_'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -16
    Font.Name = 'Tahoma'
    Font.Style = []
    MaxLength = 11
    ParentFont = False
    TabOrder = 5
    Text = '  :  :  :  '
  end
  object Memo1: TMemo
    Left = 8
    Top = 125
    Width = 611
    Height = 163
    Lines.Strings = (
      'Memo1')
    ScrollBars = ssVertical
    TabOrder = 6
  end
  object CheckBoxLoop: TCheckBox
    Left = 376
    Top = 85
    Width = 97
    Height = 17
    Caption = 'Loop'
    TabOrder = 7
  end
  object Timer1: TTimer
    Interval = 100
    OnTimer = Timer1Timer
    Left = 528
    Top = 85
  end
end
