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
  LeakCheck in '..\..\Source\LeakCheck.pas',
  LeakCheck.Utils in '..\..\Source\LeakCheck.Utils.pas',
  TestFramework in '..\..\External\DUnit\TestFramework.pas',
  TestInsight.DUnit,
  LeakCheck.TestUnit in '..\LeakCheck.TestUnit.pas',
  LeakCheck.TestDUnit in '..\LeakCheck.TestDUnit.pas',
  LeakCheck.DUnit in '..\..\Source\LeakCheck.DUnit.pas',
  LeakCheck.Cycle in '..\..\Source\LeakCheck.Cycle.pas',
  LeakCheck.Cycle.Utils in '..\..\Source\LeakCheck.Cycle.Utils.pas',
  LeakCheck.DUnitCycle in '..\..\Source\LeakCheck.DUnitCycle.pas',
  {$IFDEF MSWINDOWS}
  LeakCheck.Trace.DbgHelp in '..\..\Source\LeakCheck.Trace.DbgHelp.pas',
  LeakCheck.Trace.WinApi in '..\..\Source\LeakCheck.Trace.WinApi.pas',
  LeakCheck.Trace.Jcl in '..\..\Source\LeakCheck.Trace.Jcl.pas',
  {$ENDIF}
  LeakCheck.TestCycle in '..\LeakCheck.TestCycle.pas';

{$R *.res}

begin
  // Simple test of functionality
  RunTests;

  ReportMemoryLeaksOnShutdown := True;

  //TLeakCheck.GetStackTraceProc := WinApiStackTrace;
  //TLeakCheck.GetStackTraceProc := DbgHelpStackTrace;
  TLeakCheck.GetStackTraceProc := JclRawStackTrace;
  //TLeakCheck.GetStackTraceProc := JclFramesStackTrace;
  TLeakCheck.GetStackTraceFormatterProc := JclStackTraceFormatter;

  // DUnit integration
{$IFDEF WEAKREF}
  TLeakCheck.IgnoredLeakTypes := [tkUnknown];
{$ENDIF}
  TLeakCheckCycleMonitor.UseExtendedRtti := True;
  MemLeakMonitorClass := TLeakCheckCycleGraphMonitor;
  RunRegisteredTests;
end.

