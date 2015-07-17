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

{$I LeakCheck.inc}

interface

uses
  LeakCheck,
  StrUtils,
  Classes;

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
procedure IgnoreDynamicArray(Arr: Pointer);
procedure IgnoreTValue(ValuePtr: Pointer);

/// <summary>
///   Ignore managed fields that may leak in given object instance.
/// </summary>
/// <remarks>
///   Note that only given <c>ClassType</c> is inspected not all inherited
///   fields, if you want to ignore complete inheritance call this function
///   multiple times and use <c>ClassType.ClassParent</c>. We want to be less
///   restrictive and give the power to the user to be more selective when
///   needed to. Also note that only a subset of managed fields is supported,
///   this should be used for high-level testing. If you need to ignore more
///   types, it is suggested to add <c>tkUnknown</c> to global ignore.
/// </remarks>
procedure IgnoreManagedFields(const Instance: TObject; ClassType: TClass);

/// <summary>
///   Ignore managed fields that may leak in given object instance and all of
///   its parent classes.
/// </summary>
procedure IgnoreAllManagedFields(const Instance: TObject; ClassType: TClass);

type
  /// <summary>
  ///   Helper class for generation of generic ignore procedures.
  /// </summary>
  /// <typeparam name="T">
  ///   Class type to ignore
  /// </typeparam>
  TIgnore<T: class> = class
  public
    /// <summary>
    ///   Ignore just the class
    /// </summary>
    class function Any(const Instance: TObject; ClassType: TClass): Boolean; static;
    /// <summary>
    ///   Ignore the class and all of its fields.
    /// </summary>
    class function AnyAndFields(const Instance: TObject; ClassType: TClass): Boolean; static;
    /// <summary>
    ///   Ignore the class and all fields from it and all of it's parent
    ///   classes.
    /// </summary>
    class function AnyAndAllFields(const Instance: TObject; ClassType: TClass): Boolean; static;
  end;

{$IF CompilerVersion < 23} // < XE2

{$DEFINE HAS_OBJECTHELPER}

type
  TObjectHelper = class helper for TObject
    class function QualifiedClassName: string;
  end;

{$IFEND}

implementation

uses
{$IFDEF POSIX}
  Posix.Proc,
{$ENDIF}
  SysUtils,
  TypInfo,
  Rtti;

{$INCLUDE LeakCheck.Types.inc}

const
  SSystemPrefix = {$IF CompilerVersion >= 23} {XE2+} 'System.' {$ELSE} '' {$IFEND};

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

procedure IgnoreTValue(ValuePtr: Pointer);
var
  Value: PValue absolute ValuePtr;
  ValueData: PValueData absolute Value;
begin
  if Value^.IsEmpty then
    Exit;
  if Assigned(ValueData^.FValueData) then
  begin
    // Use plain pointer here to mitigate conversion and _Release issues
    if ValueData^.FValueData is TObject then
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
      IgnoreArray(Pointer(PByte(P) + NativeInt(FT.Fields[I].Offset)),
        FT.Fields[I].TypeInfo^, 1);
    end;
  end;
end;

// This is how System releases managed fields, we'll use similar way to ignore them.
// Note that only given class is inspected, this is By Design! See summary.
procedure IgnoreManagedFields(const Instance: TObject; ClassType: TClass);
var
  InitTable: PTypeInfo;
begin
  InitTable := PPointer(PByte(ClassType) + vmtInitTable)^;
  if Assigned(InitTable) then
    IgnoreRecord(Instance, InitTable);
end;

procedure IgnoreAllManagedFields(const Instance: TObject; ClassType: TClass);
begin
  repeat
    IgnoreManagedFields(Instance, ClassType);
    ClassType := ClassType.ClassParent;
  until ClassType = nil
end;

function IgnoreRttiObjects(const Instance: TObject; ClassType: TClass): Boolean;
const
  Ignores: array[0..4] of string =
  (
    SSystemPrefix + 'Rtti.TMethodImplementation.TInvokeInfo',
    SSystemPrefix + 'Rtti.TPrivateHeap',
    SSystemPrefix + 'Rtti.TRttiPool',
    SSystemPrefix + 'Rtti.TPoolToken',
    SSystemPrefix + 'Generics.Collections.TObjectDictionary<System.Pointer,' + SSystemPrefix + 'Rtti.TRttiObject>'
  );
var
  QName: string;
begin
  // Always use ClassType, it is way safer!
  Result := ClassType.InheritsFrom(TRttiObject);
  if Result then
    IgnoreAllManagedFields(Instance, ClassType)
  else
  begin
    QName := ClassType.QualifiedClassName;
    Result := MatchStr(QName, Ignores);
  end;
end;

function IgnoreCustomAttributes(const Instance: TObject; ClassType: TClass): Boolean;
begin
  Result := ClassType.InheritsFrom(TCustomAttribute);
  if Result then
    IgnoreAllManagedFields(Instance, ClassType)
  else
    Result := ClassType.QualifiedClassName = SSystemPrefix + 'Rtti.TFinalizer';
end;

function IgnoreAnonymousMethodPointers(const Instance: TObject; ClassType: TClass): Boolean;
var
  name: string;
begin
  name := ClassType.ClassName;
  Result := StartsStr('MakeClosure$', name) and EndsStr('$ActRec', name);
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

type
  TStringListInternal = class(TStrings)
  private
    FList: Pointer;
  end;
procedure IgnoreStrings(const Strings: TStrings);
var
  s: string;
begin
  RegisterExpectedMemoryLeak(Strings);
  if Strings is TStringList then
{$IF CompilerVersion >= 23} {XE2+}
    IgnoreDynamicArray(TStringListInternal(Strings).FList);
{$ELSE}
    RegisterExpectedMemoryLeak(TStringListInternal(Strings).FList);
{$IFEND}
  for s in Strings do
    IgnoreString(@s);
end;

procedure IgnoreDynamicArray(Arr: Pointer);
begin
  if Assigned(Arr) then
    RegisterExpectedMemoryLeak(PByte(Arr) - SizeOf(TDynArrayRec));
end;

{$REGION 'TIgnore<T>'}

class function TIgnore<T>.Any(const Instance: TObject;
  ClassType: TClass): Boolean;
begin
  Result := ClassType.InheritsFrom(T);
end;

class function TIgnore<T>.AnyAndAllFields(const Instance: TObject;
  ClassType: TClass): Boolean;
begin
  Result := ClassType.InheritsFrom(T);
  if Result then
    IgnoreManagedFields(Instance, ClassType);
end;

class function TIgnore<T>.AnyAndFields(const Instance: TObject;
  ClassType: TClass): Boolean;
begin
  Result := ClassType.InheritsFrom(T);
  if Result then
    IgnoreManagedFields(Instance, ClassType);
end;

{$ENDREGION}

{$REGION 'TObjectHelper'}

{$IFDEF HAS_OBJECTHELPER} // < XE2

class function TObjectHelper.QualifiedClassName: string;
var
  LScope: string;
begin
  LScope := Self.UnitName;
  if LScope = '' then
    Result := ClassName
  else
    Result := LScope + '.' + ClassName;
end;

{$ENDIF}

{$ENDREGION}

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
begin
  TLeakCheck.BeginIgnore;
  try
    TObject(ProcEntries) := TPosixProcEntryList.Create;
    TPosixProcEntryList(ProcEntries).LoadFromCurrentProcess;
  finally
    TLeakCheck.EndIgnore;
  end;
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
