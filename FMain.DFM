object Main: TMain
  Left = 420
  Top = 273
  BorderStyle = bsToolWindow
  ClientHeight = 222
  ClientWidth = 326
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -10
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnClose = FormClose
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object lbOwner: TLabel
    Left = 26
    Top = 52
    Width = 227
    Height = 13
    Caption = #1056#1072#1079#1088#1072#1073#1086#1090#1095#1080#1082#1080': '#1043#1091#1083#1103#1077#1074' '#1043'.'#1070'., '#1054#1089#1090#1088#1086#1074#1089#1082#1080#1081' '#1041'.'#1051'.'
  end
  object lbBuild: TLabel
    Left = 65
    Top = 85
    Width = 31
    Height = 13
    Caption = 'lbBuild'
    Visible = False
  end
  object mn: TPopupMenu
    AutoPopup = False
    Left = 56
    Top = 8
    object nExit: TMenuItem
      Caption = #1047#1072#1082#1088#1099#1090#1100
      Default = True
      OnClick = nExitClick
    end
    object nAbout: TMenuItem
      Caption = #1054' '#1087#1088#1086#1075#1088#1072#1084#1084#1077
      OnClick = nAboutClick
    end
  end
end
