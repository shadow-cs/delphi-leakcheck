program LeakCheckCustomReport;

{$R *.res}

uses
  LeakCheck, // Does not need do be defined here (LeakReportInternal will do) unless you want to reference it from the DPR
  LeakReportInternal, // Me first! - I don't have any dependencies but LeakCheck so I finalize after all other units
  LeakReport, // Then me - I'm the one that pulls some dependencies and have all the functionality
  Classes, // All other units
  LeakCheck.Trace.WinApi,
  LeakCheck.Trace.Map,
  Vcl.Forms,
  Vcl.StdCtrls,
  TestMain in 'TestMain.pas' {Form1};

begin
  TLeakCheck.GetStackTraceProc := WinApiStackTrace;
  TLeakCheck.GetStackTraceFormatterProc := MapStackTraceFormatter;

  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
