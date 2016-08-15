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

{$I LeakCheck.inc}

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
  Windows,
  SysUtils;

function RtlCaptureStackBackTrace(FramesToSkip: ULONG; FramesToCapture: ULONG;
  BackTrace: PPointer; BackTraceHash : PULONG = nil): USHORT;
  stdcall; external 'kernel32.dll';

var
  // Current windows version is XP or older (RtlCaptureStackBackTrace is not
  // suppored on older version than XP according to MSDN, it may be supported
  // on Windows 2000 but the documentation has been stripped off already)
  WinXPDown: Boolean = False;

function WinApiStackTrace(IgnoredFrames: Integer; Data: PPointer;
  Size: Integer): Integer;
begin
  // Implicitly ignore current frame
  Inc(IgnoredFrames);
  if (WinXPDown) then
  begin
    // Windows XP only supports IgnoredFrames + Size < 63
    // https://msdn.microsoft.com/en-us/library/windows/desktop/bb204633(v=vs.85).aspx
    if IgnoredFrames + Size >= 63 then
      Size := 62 - IgnoredFrames;
  end;

  Result := RtlCaptureStackBackTrace(IgnoredFrames, Size, Data);
end;

initialization
  WinXPDown := not CheckWin32Version(6);

end.
