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
  LeakCheck,
  System.Classes;


/// <summary>
///   When assigned to <see cref="LeakCheck|TLeakCheck.InstanceIgnoredProc" />
///   it ignores all TRttiObject and their internal managed fields as leaks.
/// </summary>
function IgnoreRttiObjects(const Instance: TObject; ClassType: TClass): Boolean;

/// <summary>
///   When assigned to <see cref="LeakCheck|TLeakCheck.InstanceIgnoredProc" />
///   it ignores <c>TCustomAttribute</c> instances.
/// </summary>
function IgnoreCustomAttributes(const Instance: TObject; ClassType: TClass): Boolean;

/// <summary>
///   When assigned to <see cref="LeakCheck|TLeakCheck.InstanceIgnoredProc" />
///   it ignores classes that the compiler creates for anonymous methods.
/// </summary>
function IgnoreAnonymousMethodPointers(const Instance: TObject; ClassType: TClass): Boolean;

/// <summary>
///   When assigned to <see cref="LeakCheck|TLeakCheck.InstanceIgnoredProc" />
///   it ignores multiple objects by calling all registered methods.
/// </summary>
function IgnoreMultipleObjects(const Instance: TObject; ClassType: TClass): Boolean;

procedure AddIgnoreObjectProc(Proc: TLeakCheck.TIsInstanceIgnored); overload;
procedure AddIgnoreObjectProc(const Procs: array of TLeakCheck.TIsInstanceIgnored); overload;

procedure IgnoreStrings(const Strings: TStrings);

/// <summary>
///   Ignore managed fields that may leak in given object instance.
/// </summary>
/// <remarks>
///   Note that only a subset of managed fields is supported, this should be
///   used for high-level testing. If you need to ignore more types, it is
///   suggested to add <c>tkUnknown</c> to global ignore.
/// </remarks>
procedure IgnoreManagedFields(const Instance: TObject; ClassType: TClass);

implementation

uses
{$IFDEF POSIX}
  Posix.Proc,
{$ENDIF}
  System.SysUtils,
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

  PNativeUint = ^NativeUInt;

  PValueData = ^TValueData;
  PValue = ^TValue;
  PPValue = ^PValue;

var
  RegisteredIgnoreProcs: array of TLeakCheck.TIsInstanceIgnored;

procedure IgnoreString(P: PString);
begin
  if P^ = '' then
    Exit;
  if StringRefCount(P^) < 0 then
    Exit; // Constant string

  RegisterExpectedMemoryLeak(Pointer(PNativeUInt(P)^ - TLeakCheck.StringSkew));
end;

procedure IgnoreTValue(Value: PValue);
var
  ValueData: PValueData absolute Value;
begin
  if Value^.IsEmpty then
    Exit;
  if Assigned(ValueData^.FValueData) then
  begin
    RegisterExpectedMemoryLeak(ValueData^.FValueData as TObject);
    case Value^.Kind of
      tkLString, tkUString:
        IgnoreString(Value^.GetReferenceToRawData);
    end;
  end;
end;

procedure IgnoreArray(P: Pointer; TypeInfo: PTypeInfo; ElemCount: NativeUInt);
begin
  if ElemCount = 0 then
    Exit;

  Assert(ElemCount = 1); // Pure arrays not supported at the moment
  case TypeInfo^.Kind of
      tkLString, tkUString:
        IgnoreString(PString(P));
      tkRecord:
        if TypeInfo = System.TypeInfo(TValue) then
          IgnoreTValue(PValue(P));
  end;
end;

procedure IgnoreRecord(P: Pointer; TypeInfo: PTypeInfo);
var
  I: Cardinal;
  FT: PFieldTable;
begin
  FT := PFieldTable(PByte(TypeInfo) + Byte(PTypeInfo(TypeInfo).Name{$IFNDEF NEXTGEN}[0]{$ENDIF}));
  if FT.Count > 0 then
  begin
    for I := 0 to FT.Count - 1 do
    begin
{$IFDEF WEAKREF}
      if FT.Fields[I].TypeInfo = nil then
        Exit; // Weakref separator
{$ENDIF}
      IgnoreArray(Pointer(PByte(P) + IntPtr(FT.Fields[I].Offset)),
        FT.Fields[I].TypeInfo^, 1);
    end;
  end;
end;

// This is how System releases managed fields, we'll use similar way to ignore them
procedure IgnoreManagedFields(const Instance: TObject; ClassType: TClass);
var
  InitTable: PTypeInfo;
begin
  repeat
    InitTable := PPointer(PByte(ClassType) + vmtInitTable)^;
    if Assigned(InitTable) then
      IgnoreRecord(Instance, InitTable);
    ClassType := ClassType.ClassParent;
  until ClassType = nil;
end;

function IgnoreRttiObjects(const Instance: TObject; ClassType: TClass): Boolean;
var
  QName: string;
begin
  // Always use ClassType, it is way safer!
  Result := ClassType.InheritsFrom(TRttiObject);
  if Result then
    IgnoreManagedFields(Instance, ClassType)
  else
  begin
    QName := ClassType.QualifiedClassName;
    Result := (QName = 'System.Rtti.TMethodImplementation.TInvokeInfo')
      or (QName = 'System.Rtti.TPrivateHeap')
  end;
end;

function IgnoreCustomAttributes(const Instance: TObject; ClassType: TClass): Boolean;
begin
  Result := ClassType.InheritsFrom(TCustomAttribute);
  if Result then
    IgnoreManagedFields(Instance, ClassType)
  else
    Result := ClassType.QualifiedClassName = 'System.Rtti.TFinalizer';
end;

function IgnoreAnonymousMethodPointers(const Instance: TObject; ClassType: TClass): Boolean;
var
  name: string;
begin
  name := ClassType.ClassName;
  Result := name.StartsWith('MakeClosure$') and name.EndsWith('$ActRec');
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

procedure AddIgnoreObjectProc(const Procs: array of TLeakCheck.TIsInstanceIgnored);
var
  Proc: TLeakCheck.TIsInstanceIgnored;
begin
  for Proc in Procs do
    AddIgnoreObjectProc(Proc);
end;

procedure IgnoreStrings(const Strings: TStrings);
var
  s: string;
begin
  RegisterExpectedMemoryLeak(Strings);
  for s in Strings do
    IgnoreString(@s);
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
