program LeakCheckCustomReport;

{$R *.res}

uses
  // LeakCheck, // Does not need do be defined here (LeakCheck.Report will do it) unless you want to reference it from the DPR
  LeakCheck.Report, // Me first! - I don't have any dependencies but LeakCheck so I finalize after all other units
  LeakCheck.Setup.Trace, // (Optional) Then me - Run setup to configure stack tracing for us
  LeakCheck.Report.FileLog, // Then me - I'm the one that pulls some dependencies and have all the functionality
  Classes, // All other units
  Forms,
  StdCtrls,
  TestMain in 'TestMain.pas' {Form1};

begin
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
