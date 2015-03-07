program TestProject;

uses
  LeakCheck in '..\..\Source\LeakCheck.pas',
  System.StartUpCopy,
  LeakCheck.Utils in '..\..\Source\LeakCheck.Utils.pas',
  FMX.Forms,
  Posix.Proc in '..\..\External\Backtrace\Source\Posix.Proc.pas',
  LeakCheck.TestUnit in '..\LeakCheck.TestUnit.pas',
  LeakCheck.TestForm in '..\LeakCheck.TestForm.pas' {frmLeakCheckTest};

{$R *.res}


begin
  ReportMemoryLeaksOnShutdown := True;
  RunTests;
  Application.Initialize;
  Application.CreateForm(TfrmLeakCheckTest, frmLeakCheckTest);
  Application.Run;
end.

