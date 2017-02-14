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

unit LeakCheck.Trace;

{$I LeakCheck.inc}

interface

procedure Trace(const Msg: string);

implementation
uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
{$IFDEF POSIX}
  Posix.Unistd,
  SysUtils,
{$ENDIF}
{$IFDEF ANDROID}
  Androidapi.Log,
{$ENDIF}
  LeakCheck;

{$IF CompilerVersion >= 25} // >= XE4
  {$LEGACYIFEND ON}
{$IFEND}

{$IFDEF LEAKCHECK_TRACE_FILE}
var
  GOutput: TextFile;
{$ENDIF}

procedure Trace(const Msg: string);
{$IF Defined(LEAKCHECK_TRACE_FILE)}
begin
  if TTextRec(GOutput).Handle = 0 then
  begin
    Assign(GOutput, 'LeakCheck.trace');
    Rewrite(GOutput);
  end;
  Writeln(GOutput, Msg);
end;
{$ELSEIF Defined(ANDROID)}
const
  TAG: MarshaledAString = MarshaledAString('LeakCheck');
var
  m: TMarshaller;
begin
  __android_log_write(ANDROID_LOG_WARN, TAG, m.AsAnsi(Msg).ToPointer);
  // Do not sleep here, it causes slowdown and we don't mind (much) if we loose
  // some messages.
  // usleep(1 * 1000);
end;
{$ELSEIF Defined(MSWINDOWS)}
begin
  OutputDebugString(PChar(Msg));
end;
{$ELSEIF Defined(POSIX)}
begin
  WriteLn(ErrOutput, Msg);
end;
{$ELSE}
  {$MESSAGE FATAL 'Unsupported platform'}
{$IFEND}

{$IFDEF LEAKCHECK_TRACE_FILE}
initialization
finalization
  if TTextRec(GOutput).Handle <> 0 then
    Flush(GOutput);
  // Do not close the file in case it is needed by other units' finalization
  // we'll leak some memory and handles but since this is debugging function,
  // this is not an issue - it will be released by the system momentarily.
{$ENDIF}

end.
