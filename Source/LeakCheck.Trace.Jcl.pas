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

unit LeakCheck.Trace.Jcl;

{$I LeakCheck.inc}

interface

{$I jcl.inc}

uses
  LeakCheck, JclDebug;

/// <summary>
///   JCL solution performing frame-based scanning. Win 32 and Win 64 only.
///   Reasonably safe and robust Win 32 implementation, identical to
///   LeakCheck.Trace.WinApi on Win64. <b>Uses global caches!</b>
/// </summary>
function JclFramesStackTrace(IgnoredFrames: Integer; Data: PPointer;
  Size: Integer): Integer;
{$IFDEF CPU32}
/// <summary>
///   JCL solution performing raw scanning (matches entire stack while scanning
///   all valid addresses, may produce invalid calls but is also able to
///   display more information than other techniques). Win 32 and Win 64 only.
///   Identical to LeakCheck.Trace.WinApi on Win64. <b>Uses global caches!</b>
/// </summary>
function JclRawStackTrace(IgnoredFrames: Integer; Data: PPointer;
  Size: Integer): Integer;
{$ENDIF}

/// <summary>
///   JCL implementation using different methods to obtain the formatted line
///   (including debug symbols and MAP file). <b>Uses global caches!</b>
/// </summary>
function JclStackTraceFormatter: TLeakCheck.IStackTraceFormatter;

implementation

uses
  Math;

function JclStackTrace(IgnoredFrames: Integer; Data: PPointer;
  Size: Integer; Raw: Boolean): Integer;
var
  OldTracer: TLeakCheck.TGetStackTrace;
  StackList: TJclStackInfoList;
  i: Integer;
begin
  // There are some allocations in the JCL tracer that would cause a cycle so
  // suspend allocation tracing during stack tracing. Also ignore JCL global
  // caches.
  OldTracer := TLeakCheck.GetStackTraceProc;
  TLeakCheck.GetStackTraceProc := nil;
  TLeakCheck.BeginIgnore;
  try
    // Use TJclStackInfoList directly (without calling JclCreateStackList) to
    // bypass JCL caches.
    StackList := TJclStackInfoList.Create(Raw, IgnoredFrames, nil);
    try
      Result := Min(StackList.Count, Size);
      for i := 0 to Result - 1 do
      begin
        Data^ := StackList[i].CallerAddr;
        Inc(Data);
      end;
    finally
      StackList.Free;
    end;
  finally
    TLeakCheck.EndIgnore;
    TLeakCheck.GetStackTraceProc := OldTracer;
  end;
end;

function JclFramesStackTrace(IgnoredFrames: Integer; Data: PPointer;
  Size: Integer): Integer;
begin
  Result := JclStackTrace(IgnoredFrames + 3, Data, Size, False);
end;

{$IFDEF CPU32}
function JclRawStackTrace(IgnoredFrames: Integer; Data: PPointer;
  Size: Integer): Integer;
begin
  Result := JclStackTrace(IgnoredFrames + 5, Data, Size, True);
end;
{$ENDIF}

type
  TJclStackTraceFormatter = class(TInterfacedObject, TLeakCheck.IStackTraceFormatter)
  public
    function FormatLine(Addr: Pointer; const Buffer: MarshaledAString;
      Size: Integer): Integer;
  end;

{ TJclStackTraceFormatter }

function TJclStackTraceFormatter.FormatLine(Addr: Pointer;
  const Buffer: MarshaledAString; Size: Integer): Integer;
var
  s: AnsiString;
begin
  TLeakCheck.BeginIgnore;
  try
    s := AnsiString(GetLocationInfoStr(Addr, True, True, True, True));
    Result := Min(Length(s), Size - 1);
    if Result > 0 then
      Move(s[1], Buffer^, Result + 1); // Add trailing zero
  finally
    TLeakCheck.EndIgnore;
  end;
end;

function JclStackTraceFormatter: TLeakCheck.IStackTraceFormatter;
var
  s: string;
begin
  // Get some info to initialize global cache
  s := GetLocationInfoStr(
    {$IF (CompilerVersion >= 23.0)}ReturnAddress{$ELSE}Caller(0, True){$IFEND},
    True, True, True, True);
  s := '';
  Result := TJclStackTraceFormatter.Create;
end;

initialization
finalization
  // JCL global caches are about to be cleared, no further tracing is possible
  if (Pointer(TLeakCheck.GetStackTraceProc) = @JclFramesStackTrace) or
    (Pointer(TLeakCheck.GetStackTraceProc) = @JclRawStackTrace) then
  begin
    TLeakCheck.GetStackTraceProc := nil;
  end;
  if Pointer(TLeakCheck.GetStackTraceFormatterProc) = @JclStackTraceFormatter then
    TLeakCheck.CleanupStackTraceFormatter;
end.
