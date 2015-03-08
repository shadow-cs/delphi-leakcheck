program TestProject;

uses
  LeakCheck in '..\..\Source\LeakCheck.pas',
  System.StartUpCopy,
  LeakCheck.Utils in '..\..\Source\LeakCheck.Utils.pas',
  FMX.Forms,
  TestFramework in '..\..\External\DUnit\TestFramework.pas',
  TestInsight.DUnit,
  Posix.Proc in '..\..\External\Backtrace\Source\Posix.Proc.pas',
  LeakCheck.TestUnit in '..\LeakCheck.TestUnit.pas',
  LeakCheck.TestDUnit in '..\LeakCheck.TestDUnit.pas',
  LeakCheck.TestForm in '..\LeakCheck.TestForm.pas' {frmLeakCheckTest},
  LeakCheck.DUnit in '..\..\Source\LeakCheck.DUnit.pas';

{$R *.res}

begin
  ReportMemoryLeaksOnShutdown := True;

  // Simple test of functionality
  RunTests;

  // DUnit integration
{$IFDEF WEAKREF}
  TLeakCheck.IgnoredLeakTypes := [tkUnknown];
{$ENDIF}
  RunRegisteredTests;

{$IFDEF GUI}
  // FMX Leak detection
  Application.Initialize;
  Application.CreateForm(TfrmLeakCheckTest, frmLeakCheckTest);
  Application.Run;
{$ENDIF}
end.

