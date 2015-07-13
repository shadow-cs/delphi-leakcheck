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

unit LeakCheck.Trace.WinApi;

interface

/// <summary>
///   Native Windows API solution. Performs basic scanning and may omit some
///   stack frames. Win32 and Win64 only. Best solution for Win64. Does not use
///   global caches.
/// </summary>
function WinApiStackTrace(IgnoredFrames: Integer; Data: PPointer;
  Size: Integer): Integer;

implementation

uses
  Windows;

function RtlCaptureStackBackTrace(FramesToSkip: ULONG; FramesToCapture: ULONG;
  BackTrace: PPointer; BackTraceHash : PULONG = nil): USHORT;
  stdcall; external 'kernel32.dll';


function WinApiStackTrace(IgnoredFrames: Integer; Data: PPointer;
  Size: Integer): Integer;
begin
  Result := RtlCaptureStackBackTrace(IgnoredFrames + 1, Size, Data);
end;

end.
