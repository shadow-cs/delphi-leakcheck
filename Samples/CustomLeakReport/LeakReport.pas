unit LeakReport;

interface

uses
  LeakCheck,
  LeakCheck.Cycle,
  Windows,
  SysUtils;

implementation

uses
  LeakReportInternal;

/// <summary>
///   Will generate memory report and dangling object graph to help you
///   understand what causes the leak. Works regardless of <c>
///   ReportMemoryLeaksOnShutdown</c>.
/// </summary>
procedure SaveReport(const snapshot: TLeakCheck.TSnapshot);
var
  formatter: TCyclesFormatter;
  leaks: TLeaks;
  leak: TLeak;
  cycles: TCycles;
  f: TextFile;
  s: LeakString;
  InternalSnapshot: TLeakCheck.TSnapshot;
  logFileName: string;
  graphFileName: string;
begin
  InternalSnapshot.Create;
  logFileName := ChangeFileExt(ParamStr(0), '.log');
  graphFileName := ChangeFileExt(ParamStr(0), '.dot');
  // Make sure we do not report memory we just allocated
  TLeakCheck.MarkNotLeaking(InternalSnapshot.Snapshot);
  // Internal LeakCheck reporting functions use different memory manager so
  // they won't show up in the report so we don't need to ignore them again
  // (Windows only).
  leaks := TLeakCheck.GetLeaks(snapshot.Snapshot);
  try
    if leaks.IsEmpty then
    begin
      DeleteFile(logFileName);
      DeleteFile(graphFileName);
      Exit;
    end;

    // Save the log
    AssignFile(f, logFileName);
    Rewrite(f);
    try
      s := TLeakCheck.GetReport(snapshot.Snapshot);
      try
        Writeln(f, s.Data);
      finally
        s.Free;
      end;
    finally
      CloseFile(f);
    end;

    // Save the graph
    AssignFile(f, graphFileName);
    Rewrite(f);
    try
      formatter := TCyclesFormatter.Create([
        TCycleFormat.Graphviz,
        TCycleFormat.WithAddress,
        TCycleFormat.WithField]);
      for leak in leaks do
        if leak.TypeKind = tkClass then
        begin
          cycles := ScanGraph(leak.Data, [TScanFlag.UseExtendedRtti]);
          formatter.Append(cycles);
        end;

      Writeln(f, formatter.ToString);
    finally
      CloseFile(f);
    end;

    MessageBox(0, PChar('Memory leak detected, see ' + logFileName + ' and '
      + graphFileName),
      'Memory leak', MB_ICONERROR);
  finally
    leaks.Free;
  end;
end;

initialization
  GetReport := SaveReport;

end.
