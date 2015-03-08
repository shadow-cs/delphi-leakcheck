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


/// <summary>
///   When assigned to <see cref="LeakCheck|TLeakCheck.InstanceIgnoredProc" />
///   it ignores all TRttiObject and their internal managed fields as leaks.
/// </summary>
function IgnoreRttiObjects(const Instance: TObject; ClassType: TClass): Boolean;

/// <summary>
///   When assigned to <see cref="LeakCheck|TLeakCheck.InstanceIgnoredProc" />
///   it ignores multiple objects by calling all registered methods.
/// </summary>
function IgnoreMultipleObjects(const Instance: TObject; ClassType: TClass): Boolean;

procedure AddIgnoreObjectProc(Proc: TLeakCheck.TIsInstanceIgnored);

/// <summary>
///   Ignore managed fields that may leak in given object instance.
/// </summary>
procedure IgnoreManagedFields(const Instance: TObject; ClassType: TClass);

implementation

uses
{$IFDEF POSIX}
  Posix.Proc,
{$ENDIF}
  System.TypInfo,
  System.Rtti;

type
  TFieldInfo = packed record
    TypeInfo: PPTypeInfo;
    case Integer of
    0: ( Offset: Cardinal );
    1: ( _Dummy: NativeUInt );
  end;

  PFieldTable = ^TFieldTable;
  TFieldTable = packed record
    X: Word;
    Size: Cardinal;
    Count: Cardinal;
    Fields: array [0..0] of TFieldInfo;
  end;

var
  RegisteredIgnoreProcs: array of TLeakCheck.TIsInstanceIgnored;

// This is how System releases strings, we'll use similar way to ignore them
procedure IgnoreManagedFields(const Instance: TObject; ClassType: TClass);
var
  I: Cardinal;
  FT: PFieldTable;
  InitTable: PTypeInfo;
  Addr: IntPtr;
begin
  InitTable := PPointer(PByte(ClassType) + vmtInitTable)^;
  if not Assigned(InitTable) then
    Exit;

  FT := PFieldTable(PByte(InitTable) + Byte(PTypeInfo(InitTable).Name[0]));

  for I := 0 to FT.Count - 1 do
  begin
    Addr := IntPtr(PPointer(PByte(Instance) + IntPtr(FT.Fields[I].Offset))^);
    if FT.Fields[I].TypeInfo^^.Kind in [tkLString, tkUString] then
      RegisterExpectedMemoryLeak(Pointer(Addr - TLeakCheck.StringSkew));
  end;
end;


function IgnoreRttiObjects(const Instance: TObject; ClassType: TClass): Boolean;
begin
  // Always use ClassType, it is way safer!
  Result := ClassType.InheritsFrom(TRttiObject);
  if Result then
  begin
    IgnoreManagedFields(Instance, ClassType);
  end;
end;

function IgnoreMultipleObjects(const Instance: TObject; ClassType: TClass): Boolean;
var
  Proc: TLeakCheck.TIsInstanceIgnored;
begin
  for Proc in RegisteredIgnoreProcs do
    if Proc(Instance, ClassType) then
      Exit(True);
  Result := False;
end;

procedure AddIgnoreObjectProc(Proc: TLeakCheck.TIsInstanceIgnored);
var
  L: Integer;
begin
  L := Length(RegisteredIgnoreProcs);
  SetLength(RegisteredIgnoreProcs, L + 1);
  RegisteredIgnoreProcs[L] := Proc;
end;

{$IFDEF POSIX}

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
