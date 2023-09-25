program OrgCng;

uses
  Forms,
  FMain in 'FMain.pas' {Main};

{$R *.res}

begin
  Application.Initialize;
  FindOtherOrgCng;
  Application.Run;
end.
