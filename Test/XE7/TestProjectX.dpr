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

program TestProjectX;

// Make sure to have DUnitX in your global search path or point DUNITX_DIR
// environmental variable to DUnitX base source directory.

// Note that in order to run this project you have to have the updated DUnitX
// framework that supports extended leak checking.

uses
  {$IFDEF WIN32}
  FastMM4,
  {$ENDIF }
  LeakCheck in '..\..\Source\LeakCheck.pas',
  System.StartUpCopy,
  LeakCheck.Utils in '..\..\Source\LeakCheck.Utils.pas',
  FMX.Forms,
  DUnitX.TestFramework,
  DUnitX.IoC,
  TestInsight.DUnitX,
  Posix.Proc in '..\..\External\Backtrace\Source\Posix.Proc.pas',
  LeakCheck.TestForm in '..\LeakCheck.TestForm.pas' {frmLeakCheckTest},
  LeakCheck.TestDUnitX in '..\LeakCheck.TestDUnitX.pas',
  LeakCheck.Collections in '..\..\Source\LeakCheck.Collections.pas',
  LeakCheck.Cycle in '..\..\Source\LeakCheck.Cycle.pas',
  LeakCheck.Cycle.Utils in '..\..\Source\LeakCheck.Cycle.Utils.pas',
  DUnitX.MemoryLeakMonitor.LeakCheck in '..\..\External\DUnitX\DUnitX.MemoryLeakMonitor.LeakCheck.pas',
  DUnitX.MemoryLeakMonitor.LeakCheckCycle in '..\..\External\DUnitX\DUnitX.MemoryLeakMonitor.LeakCheckCycle.pas',
  {$IFDEF MSWINDOWS}
  {$IFDEF CPUX32}
  LeakCheck.Trace.DbgHelp in '..\..\Source\LeakCheck.Trace.DbgHelp.pas',
  {$ENDIF }
  LeakCheck.Trace.WinApi in '..\..\Source\LeakCheck.Trace.WinApi.pas',
  LeakCheck.Trace.Jcl in '..\..\Source\LeakCheck.Trace.Jcl.pas',
  LeakCheck.MapFile in '..\..\Source\LeakCheck.MapFile.pas',
  LeakCheck.Trace.Map in '..\..\Source\LeakCheck.Trace.Map.pas',
  {$ENDIF }
  {$IFDEF POSIX}
  LeakCheck.Trace.Backtrace in '..\..\Source\LeakCheck.Trace.Backtrace.pas',
  {$ENDIF }
  LeakCheck.TestCycle in '..\LeakCheck.TestCycle.pas';

{$R *.res}

procedure Run;
begin
  ReportMemoryLeaksOnShutdown := True;

{$IFDEF MSWINDOWS}
{$IFDEF CPUX64}
  TLeakCheck.GetStackTraceProc := WinApiStackTrace;
{$ELSE}
  TLeakCheck.GetStackTraceProc := JclRawStackTrace;
{$ENDIF}
  TLeakCheck.GetStackTraceFormatterProc := MapStackTraceFormatter;
{$ENDIF}
{$IFDEF POSIX}
  TLeakCheck.GetStackTraceProc := BacktraceStackTrace;
  TLeakCheck.GetStackTraceFormatterProc := PosixProcStackTraceFormatter;
{$ENDIF}

  TDUnitX.RegisterTestFixture(TTestCycle);
  TDUnitX.RegisterTestFixture(TTestLeaksWithACycle);
  TDUnitX.RegisterTestFixture(TTestIgnoreGraphSimple);
  TDUnitX.RegisterTestFixture(TTestIgnoreGraphComplex);
  TDUnitXIoC.DefaultContainer.RegisterType<IMemoryLeakMonitor>(
    function : IMemoryLeakMonitor
    begin
      result := TDUnitXLeakCheckGraphMemoryLeakMonitor.Create;
    end);
  RunRegisteredTests;
end;

begin
  Run;
end.
