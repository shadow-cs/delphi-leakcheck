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

unit LeakCheck.Utils;

interface

uses
  LeakCheck;

implementation

{$IFDEF POSIX}
uses
  Posix.Proc;

var
  // No refcounting so we can create and free with the memory manager suspended
  // so we don't create additional leaks
  ProcEntries: Pointer = nil;

function ProcLoader(Address: Pointer): TLeakCheck.TPosixProcEntryPermissions;
var
  Entry: PPosixProcEntry;
begin
  Entry := TPosixProcEntryList(ProcEntries).FindEntry(NativeUInt(Address));
  if Assigned(Entry) then
    TPosixProcEntryPermissions(Result) := Entry^.Perms
  else
    Result := [];
end;

procedure Init;
var
  Snapshot: Pointer;
begin
  Snapshot := TLeakCheck.CreateSnapshot;
  TObject(ProcEntries) := TPosixProcEntryList.Create;
  TPosixProcEntryList(ProcEntries).LoadFromCurrentProcess;
  TLeakCheck.MarkNotLeaking(Snapshot);
end;

procedure ManagerFinalization;
begin
  TObject(ProcEntries).Free;
end;

initialization
  Init;
  TLeakCheck.AddrPermProc := ProcLoader;
  TLeakCheck.FinalizationProc := ManagerFinalization;

{$ENDIF}

end.
