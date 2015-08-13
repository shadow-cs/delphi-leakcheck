program LeakCheckCustomReportFMX;

uses
  // LeakCheck, // Does not need do be defined here (LeakCheck.Report will do it) unless you want to reference it from the DPR
  LeakCheck.Report, // Me first! - I don't have any dependencies but LeakCheck so I finalize after all other units
  LeakCheck.Setup.Trace, // (Optional) Then me - Run setup to configure stack tracing for us
  LeakCheck.Report.FileLog, // Then me - I'm the one that pulls some dependencies and have all the functionality
  System.StartUpCopy, // All other units
  FMX.Forms,
  TestMainFMX in 'TestMainFMX.pas' {Form2};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TForm2, Form2);
  Application.Run;
end.
