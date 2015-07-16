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

unit LeakCheck.Trace.Backtrace;

{$I LeakCheck.inc}

interface

uses
  LeakCheck,
  Posix.Backtrace,
  Posix.Proc;

/// <summary>
///   Currently the only POSIX (Android) implementation, does not support frame
///   skipping.
/// </summary>
function BacktraceStackTrace(IgnoredFrames: Integer; Data: PPointer;
  Size: Integer): Integer;

/// <summary>
///   Formats stack trace addresses so they can be fed to <c>addr2line</c>
///   utility.
/// </summary>
function PosixProcStackTraceFormatter: TLeakCheck.IStackTraceFormatter;

implementation

uses
  System.SysUtils,
  System.Math;

function BacktraceStackTrace(IgnoredFrames: Integer; Data: PPointer;
  Size: Integer): Integer;
begin
  Result := backtrace(Data, Size);
end;

type
  TPosixProcStackTraceFormatter = class(TInterfacedObject, TLeakCheck.IStackTraceFormatter)
  private
    FProcEntries: TPosixProcEntryList;
  public
    constructor Create;
    destructor Destroy; override;

    function FormatLine(Addr: Pointer; const Buffer: MarshaledAString;
      Size: Integer): Integer;
  end;

{ TPosixProcStackTraceFormatter }

constructor TPosixProcStackTraceFormatter.Create;
begin
  inherited Create;
  FProcEntries := TPosixProcEntryList.Create;
  FProcEntries.LoadFromCurrentProcess;
end;

destructor TPosixProcStackTraceFormatter.Destroy;
begin
  FProcEntries.Free;
  inherited;
end;

function TPosixProcStackTraceFormatter.FormatLine(Addr: Pointer;
  const Buffer: MarshaledAString; Size: Integer): Integer;
var
  s: string;
  M: TMarshaller;
  P: MarshaledAString;
begin
  s := FProcEntries.GetStackLine(NativeUInt(Addr));
  Result := Min(Length(s), Size - 1);
  if Result > 0 then
  begin
    P:=M.AsAnsi(s).ToPointer;
    Move(P^, Buffer^, Result + 1); // Add trailing zero
  end;
end;

function PosixProcStackTraceFormatter: TLeakCheck.IStackTraceFormatter;
begin
  Result := TPosixProcStackTraceFormatter.Create;
end;

end.
