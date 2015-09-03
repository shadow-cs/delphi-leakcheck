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

program TestProject;

uses
  {$IFDEF WIN32}
  // If used together with LeakCheck registering expected leaks may not bubble
  // to the internal system memory manager and thus may be reported to the user.
  // This behavior is due to FastMM not calling parent RegisterExpectedMemoryLeak
  // and is not LeakCheck issue. This is only exposed if LEAKCHECK_DEFER is
  // defined.
  {$IFDEF LEAKCHECK_DEFER}
  FastMM4,
  {$ENDIF}
  {$ENDIF }
  {$IFDEF MSWINDOWS}
  Windows,
  {$ENDIF }
  LeakCheck in '..\..\Source\LeakCheck.pas',
  {$IFDEF MSWINDOWS}
  LeakCheck.Setup.JclTrace,
  {$ELSE}
  LeakCheck.Setup.Trace,
  {$ENDIF}
  System.StartUpCopy,
  LeakCheck.Utils in '..\..\Source\LeakCheck.Utils.pas',
  FMX.Forms,
  TestFramework in '..\..\External\DUnit\TestFramework.pas',
  TestInsight.DUnit,
  Posix.Proc in '..\..\External\Backtrace\Source\Posix.Proc.pas',
  LeakCheck.TestUnit in '..\LeakCheck.TestUnit.pas',
  LeakCheck.TestDUnit in '..\LeakCheck.TestDUnit.pas',
  LeakCheck.TestForm in '..\LeakCheck.TestForm.pas' {frmLeakCheckTest},
  LeakCheck.DUnit in '..\..\Source\LeakCheck.DUnit.pas',
  LeakCheck.Collections in '..\..\Source\LeakCheck.Collections.pas',
  LeakCheck.Cycle in '..\..\Source\LeakCheck.Cycle.pas',
  LeakCheck.Cycle.Utils in '..\..\Source\LeakCheck.Cycle.Utils.pas',
  LeakCheck.DUnitCycle in '..\..\Source\LeakCheck.DUnitCycle.pas',
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

begin
  ReportMemoryLeaksOnShutdown := True;

{$IFDEF MSWINDOWS}
  TLeakCheck.GetStackTraceProc := WinApiStackTrace;
  //TLeakCheck.GetStackTraceProc := DbgHelpStackTrace;
{$IFDEF CPUX64}
  TLeakCheck.GetStackTraceProc := JclFramesStackTrace;
{$ELSE}
  TLeakCheck.GetStackTraceProc := JclRawStackTrace;
{$ENDIF}
  //TLeakCheck.GetStackTraceProc := JclFramesStackTrace;

  TLeakCheck.GetStackTraceFormatterProc := JclStackTraceFormatter;
  //TLeakCheck.GetStackTraceFormatterProc := MapStackTraceFormatter;
{$ENDIF}
{$IFDEF POSIX}
  TLeakCheck.GetStackTraceProc := BacktraceStackTrace;
  TLeakCheck.GetStackTraceFormatterProc := PosixProcStackTraceFormatter;
{$ENDIF}

  // Simple test of functionality
  RunTests;

  // DUnit integration
{$IFDEF WEAKREF}
  TLeakCheck.IgnoredLeakTypes := [tkUnknown];
{$ENDIF}
  MemLeakMonitorClass := TLeakCheckCycleMonitor;
  RunRegisteredTests;

{$IFDEF GUI}
  // FMX Leak detection
  Application.Initialize;
  Application.CreateForm(TfrmLeakCheckTest, frmLeakCheckTest);
  Application.Run;
{$ENDIF}
end.

