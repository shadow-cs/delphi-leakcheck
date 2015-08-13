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

/// <summary>
///   Unit that if placed as first unit in the project will initialize
///   LeakCheck memory manager together with the WinApi stack tracer and MAP
///   file based trace formatter on Windows or Backtrace and Posix.Proc trace
///   formatter on Posix. This configuration has no external dependencies.
/// </summary>
unit LeakCheck.Setup.Trace;

{$I LeakCheck.inc}

interface

uses
  LeakCheck,
  LeakCheck.Utils;

implementation

{$IFDEF MSWINDOWS}
uses
  LeakCheck.Trace.WinApi,
  LeakCheck.Trace.Map;

initialization
  TLeakCheck.GetStackTraceProc := WinApiStackTrace;
  TLeakCheck.GetStackTraceFormatterProc := MapStackTraceFormatter;
{$ENDIF}

{$IFDEF POSIX}
uses
  LeakCheck.Trace.Backtrace;

initialization
  TLeakCheck.GetStackTraceProc := BacktraceStackTrace;
  TLeakCheck.GetStackTraceFormatterProc := PosixProcStackTraceFormatter;
{$ENDIF}

end.
