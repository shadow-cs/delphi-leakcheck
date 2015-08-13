{***************************************************************************}
{                                                                           }
{           LeakCheck for Delphi                                            }
{                                                                           }
{           Copyright (c) 2015 Honza Rames                                  }
{                                                                           }
{           https://bitbucket.org/shadow_cs/delphi-leakcheck                }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Licensed under the Apache License, Version 2.0 (the "License");          }
{  you may not use this file except in compliance with the License.         }
{  You may obtain a copy of the License at                                  }
{                                                                           }
{      http://www.apache.org/licenses/LICENSE-2.0                           }
{                                                                           }
{  Unless required by applicable law or agreed to in writing, software      }
{  distributed under the License is distributed on an "AS IS" BASIS,        }
{  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. }
{  See the License for the specific language governing permissions and      }
{  limitations under the License.                                           }
{                                                                           }
{***************************************************************************}

unit LeakCheck.Report.Utils;

{$I LeakCheck.inc}

interface

uses
  LeakCheck;

type
  TReportFormat = (WithLog, WithCycles);
  TReportFormats = set of TReportFormat;

  TLeakCheckReporter = class
  protected
    procedure NoLeaks; virtual;
    procedure BeginLog; virtual;
    procedure WritelnLog(Log: MarshaledAString); virtual;
    procedure EndLog; virtual;
    procedure WriteGraph(const Graph: string); virtual;
    procedure ShowMessage; virtual;
    constructor Create; virtual;
  end;
  TLeakCheckReporterClass = class of TLeakCheckReporter;

var
  ReportFormat: TReportFormats = [TReportFormat.WithLog, TReportFormat.WithCycles];
  ReporterClass: TLeakCheckReporterClass = TLeakCheckReporter;

implementation

uses
  LeakCheck.Report,
  LeakCheck.Cycle,
  SysUtils,
  TypInfo;

var
  Reporter: TLeakCheckReporter;


procedure ReportProc(const Data: MarshaledAString);
begin
  Reporter.WritelnLog(Data);
end;

/// <summary>
///   Will generate memory report and dangling object graph to help you
///   understand what causes the leak. Works regardless of <c>
///   ReportMemoryLeaksOnShutdown</c>.
/// </summary>
procedure SaveReport(const Snapshot: TLeakCheck.TSnapshot);
var
  Formatter: TCyclesFormatter;
  Leaks: TLeaks;
  Leak: TLeak;
  Cycles: TCycles;
  InternalSnapshot: TLeakCheck.TSnapshot;
begin
  if ReportFormat = [] then
    Exit;

  InternalSnapshot.Create;
  Reporter := ReporterClass.Create;
  // Make sure we do not report memory we just allocated
  TLeakCheck.MarkNotLeaking(InternalSnapshot.Snapshot);
  // Internal LeakCheck reporting functions use different memory manager so
  // they won't show up in the report so we don't need to ignore them again
  // (Windows uses completely separate memory manager where other platforms just
  // skip LeakCheck allocation mechanisms and defer that to the system memory
  // manager directly).
  Leaks := TLeakCheck.GetLeaks(Snapshot.Snapshot);
  try
    if Leaks.IsEmpty then
    begin
      Reporter.NoLeaks;
      Exit;
    end;

{$IFDEF WEAKREF}
    // Do not report unknown pointers if WeakRefs are used, it is most likely
    // held by System WeakRef pool (RTL bug).
    TLeakCheck.IgnoredLeakTypes := [tkUnknown];
{$ENDIF}

    // Save the log
    if TReportFormat.WithLog in ReportFormat then
    begin
      Reporter.BeginLog;
      try
        TLeakCheck.GetReport(ReportProc, Snapshot.Snapshot);
      finally
        Reporter.EndLog;
      end;
    end;

    // Save the graph
    if TReportFormat.WithCycles in ReportFormat then
    begin
      Formatter := TCyclesFormatter.Create([
        TCycleFormat.Graphviz,
        TCycleFormat.WithAddress,
        TCycleFormat.WithField]);
      for Leak in Leaks do
        if Leak.TypeKind = LeakCheck.tkClass then
        begin
          Cycles := ScanGraph(Leak.Data, [TScanFlag.UseExtendedRtti]);
          Formatter.Append(Cycles);
        end;
      Reporter.WriteGraph(Formatter.ToString);
    end;

    Reporter.ShowMessage;

    ReportMemoryLeaksOnShutdown := False;
  finally
    Leaks.Free;
    Reporter.Free;
  end;
end;

{ TLeakCheckReport }

procedure TLeakCheckReporter.BeginLog;
begin
  // NOP
end;

constructor TLeakCheckReporter.Create;
begin
  inherited;
end;

procedure TLeakCheckReporter.EndLog;
begin
  // NOP
end;

procedure TLeakCheckReporter.NoLeaks;
begin
  // NOP
end;

procedure TLeakCheckReporter.ShowMessage;
begin
  // NOP
end;

procedure TLeakCheckReporter.WriteGraph(const Graph: string);
begin
  // NOP
end;

procedure TLeakCheckReporter.WritelnLog(Log: MarshaledAString);
begin
  // NOP
end;

initialization
  GetReport := SaveReport;

end.
