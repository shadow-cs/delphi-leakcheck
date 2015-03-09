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

unit LeakCheck;

interface

type
  TLeak = record
  private
    FData: Pointer;
    function GetTypeKind: TTypeKind;
    function GetSize: NativeUInt; inline;
  public
    class operator Implicit(const Leak: TLeak): Pointer; inline;
    class operator Equal(const L: TLeak; const R: Pointer): Boolean; inline;

    property Data: Pointer read FData;
    property Size: NativeUInt read GetSize;
    property TypeKind: TTypeKind read GetTypeKind;
  end;

  TLeaks = record
  private type
    TPointerArray = array[0..0] of Pointer;
  public type
    TLeaksEnumerator = record
    private
      FCurrent: PPointer;
      FRemaining: Integer;
      function GetCurrent: TLeak; inline;
    public
      property Current: TLeak read GetCurrent;
      function MoveNext: Boolean; inline;
    end;
  private
    FLength: Integer;
    FLeaks: ^TPointerArray;
    function GetLeak(Index: Integer): TLeak; inline;
    function GetTotalSize: NativeUInt;
  public
    procedure Free;
    function GetEnumerator: TLeaksEnumerator; inline;

    function IsEmpty: Boolean; inline;

    property Leaks[Index: Integer]: TLeak read GetLeak; default;
    property Length: Integer read FLength;
    property TotalSize: NativeUInt read GetTotalSize;
  end;

  LeakString = record
  private
    FData: MarshaledAString;
  public
    procedure Free;
    function IsEmpty: Boolean; inline;

    class operator Implicit(const Value: LeakString): MarshaledAString; static; inline;

    property Data: MarshaledAString read FData;
  end;

  TLeakCheck = record
  private type
    PMemRecord = ^TMemRecord;
    TMemRecord = record
      Prev, Next: PMemRecord;
      Size: NativeUInt;
      MayLeak: LongBool;
      Sep: packed array[0..7] of NativeInt;
      function Data: Pointer; inline;
    end;

    // The layout of a string allocation. Used to detect string leaks.
    PStrRec = ^StrRec;
    StrRec = packed record
    {$IF SizeOf(Pointer) = 8}
      _Padding: LongInt; // Make 16 byte align for payload..
    {$IFEND}
    {$IF RTLVersion >= 20}
      codePage: Word;
      elemSize: Word;
    {$IFEND}
      refCnt: Longint;
      length: Longint;
    end;

    TLeakInfo = record
      ClassType: TClass;
      StringInfo: PStrRec;
    end;
  public type
    TPosixProcEntryPermissions = set of (peRead, peWrite, peExecute, peShared,
		  pePrivate {copy on write});
    TLeakProc = procedure(const Data: MarshaledAString);
    TAddrPermProc = function(Address: Pointer): TPosixProcEntryPermissions;
    /// <summary>
    ///   See <see cref="LeakCheck|TLeakCheck.InstanceIgnoredProc" />.
    /// </summary>
    TIsInstanceIgnored = function(const Instance: TObject; ClassType: TClass): Boolean;
    TProc = procedure;
    TTypeKinds = set of TTypeKind;
  public const
    StringSkew = SizeOf(StrRec);
  private class var
    FOldMemoryManager: TMemoryManagerEx;
  private
    class function GetMem(Size: NativeInt): Pointer; static;
    class function FreeMem(P: Pointer): Integer; static;
    class function ReallocMem(P: Pointer; Size: NativeInt): Pointer; static;

    class function AllocMem(Size: NativeInt): Pointer; static;
    class function RegisterExpectedMemoryLeak(P: Pointer): Boolean; static;
    class function UnregisterExpectedMemoryLeak(P: Pointer): Boolean; static;

    class procedure _AddRec(const P: PMemRecord; Size: NativeUInt); static;
    class procedure _ReleaseRec(const P: PMemRecord); static;
    class procedure _SetLeaks(const P: PMemRecord; Value: LongBool); static;

    class procedure InitMem(P: PMemRecord); static; inline;

    class function IsConsistent: Boolean; static;

    class procedure Initialize; static;
    class procedure Finalize; static;

    class procedure Resume; static;
    class procedure Suspend; static;

    class function GetSnapshot(Snapshot: Pointer): PMemRecord; static;
    class function IsLeakIgnored(Rec: PMemRecord): Boolean; overload; static;
    class function IsLeakIgnored(const LeakInfo: TLeakInfo; Rec: PMemRecord): Boolean; overload; static;
    class procedure GetLeakInfo(var Info: TLeakInfo; Rec: PMemRecord); static;
  public
    /// <summary>
    ///   Create a new allocation snapshot that can be passed to various other
    ///   functions. The snapshot indicate a state of memory allocation at a
    ///   given time. The caller must ensure that the memory pointer last
    ///   allocated will be valid when the snapshot is used. The snapshot
    ///   doesn't have to be freed in any way (but if used incorrectly may
    ///   become invalid and cause AVs).
    /// </summary>
    class function CreateSnapshot: Pointer; static;

    /// <summary>
    ///   Indicate that any allocation made between given snapshot and current
    ///   last allocation will not be treated as a leak.
    /// </summary>
    class procedure MarkNotLeaking(Snapshot: Pointer); static;

    /// <summary>
    ///   Report leaks. If Snapshot is assigned, leaks will be reported since
    ///   given snapshot.
    /// </summary>
    class procedure Report(Snapshot: Pointer = nil; SendSeparator: Boolean = False); static;
    class function GetLeaks(Snapshot: Pointer = nil): TLeaks; static;
    class procedure GetReport(const Callback: TLeakProc;
      Snapshot: Pointer = nil; SendSeparator: Boolean = False); overload; static;
    class function GetReport(Snapshot: Pointer = nil): LeakString; overload; static;

    /// <summary>
    ///   Executes given code with suspended memory manager code, all release
    ///   code must be executed in RunSuspended as well.
    /// </summary>
    class procedure RunSuspended(Proc: TProc); experimental; static;
  public class var
{$IFDEF POSIX}
    AddrPermProc: TAddrPermProc;
{$ENDIF}
    FinalizationProc: TProc;

    /// <summary>
    ///   Some leak types can be ignored if they are not relevant to the
    ///   application. This can be especially important on NextGen where
    ///   WeakRefs and Closures are freed after the memory manager has scanned
    ///   for leaks (in System unit).
    /// </summary>
    IgnoredLeakTypes: TTypeKinds;

    /// <summary>
    ///   If set it is called before any instance is marked as a leak. If
    ///   marked once as a non-leak the instance won't be checked again. Any
    ///   type check should use <c>ClassType.InheritsFrom</c> rather than
    ///   instance and 'is' operator, it is much safer. After you're sure the
    ///   is correct you may cast instance to it.
    /// </summary>
    InstanceIgnoredProc: TIsInstanceIgnored;
  end;

  TPointerHelper = record helper for Pointer
  private
    function ToRecord: TLeakCheck.PMemRecord;
  end;

{$IFNDEF MSWINDOWS}

// In System but not available on other platforms
function RegisterExpectedMemoryLeak(P: Pointer): Boolean; inline;
function UnregisterExpectedMemoryLeak(P: Pointer): Boolean; inline;

{$ENDIF}

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows;
{$ENDIF}
{$IFDEF ANDROID}
  Androidapi.Log,
{$ENDIF}
{$IFDEF POSIX}
  Posix.SysTypes,
  Posix.Unistd,
  Posix.Pthread;
{$ENDIF}

{$REGION 'Common types'}

type
  PTypeInfo = ^TTypeInfo;
  PPTypeInfo = ^PTypeInfo;
  TTypeInfo = record
    Kind: TTypeKind;
    case Byte of
      0: (NameLength: Byte);
{$IF Declared(ShortString)}
      1: (Name: ShortString);
{$IFEND}
  end;

  StrRec = TLeakCheck.StrRec;
  PStrRec = TLeakCheck.PStrRec;

  TCritSec = record
{$IFDEF MSWINDOWS}
    FHandle: TRTLCriticalSection;
{$ENDIF}
{$IFDEF POSIX}
    FHandle: pthread_mutex_t;
{$ENDIF}
    procedure Initialize; inline;
    procedure Free; inline;
    procedure Enter; inline;
    procedure Leave; inline;
  end;

const
  SizeMemRecord = SizeOf(TLeakCheck.TMemRecord);

{$ENDREGION}

{$REGION 'Global vars'}

var
  First: TLeakCheck.PMemRecord = nil;
  Last: TLeakCheck.PMemRecord = nil;
  AllocationCount: NativeUInt = 0;
  AllocatedBytes: NativeUInt = 0;
  GBuff: array[0..31] of Byte;
  LeakStr: MarshaledAString = nil;
  CS: TCritSec;

{$ENDREGION}

function GetObjectClass(APointer: Pointer): TClass; forward;
function IsString(Rec: TLeakCheck.PMemRecord; LDataPtr: Pointer): Boolean; forward;

{$REGION 'String utils'}

const
  SZero: MarshaledAString = MarshaledAString('0'#0);

  HexTable: array[0..15] of Byte = (Ord('0'), Ord('1'), Ord('2'), Ord('3'),
    Ord('4'), Ord('5'), Ord('6'), Ord('7'), Ord('8'), Ord('9'), Ord('A'),
    Ord('B'), Ord('C'), Ord('D'), Ord('E'), Ord('F'));

function StrLen(s: MarshaledAString): Integer;
begin
  Result := 0;
  if not Assigned(s) then
    Exit;
  while s^ <> #0 do
  begin
    Inc(s);
    Inc(Result);
  end;
end;

procedure StrCat(Dest, Src: MarshaledAString; Len: Integer = -1);
begin
  Inc(Dest, StrLen(Dest));
  if Len < 0 then
    Len := StrLen(Src);
  Move(Src^, Dest^, Len);
  Inc(Dest, Len);
  Dest^ := #0;
end;

function IntToStr(Value: NativeUInt; MinChars: Integer = 0; Base: NativeUInt = 10): MarshaledAString; overload;
var
  b: PByte;
begin
  if (Value = 0) and (MinChars <= 0) then Exit(SZero);

  b:=@GBuff[High(GBuff)];
  b^:=0;
  while (Value <> 0) or (MinChars > 0) do
  begin
    Dec(MinChars);
    Dec(b);
    b^:=HexTable[Value mod Base];
    Value := Value div Base;
  end;

  Result := MarshaledAString(b);
end;

function IntToStr(Value: NativeInt): MarshaledAString; overload;
begin
  if Value < 0 then
  begin
    Result := IntToStr(-Value, 0);
    Dec(Result);
    Result^ := '-';
  end
  else
    Result := IntToStr(Value, 0)
end;

{$ENDREGION}

{$REGION 'TLeakCheck'}

class procedure TLeakCheck._AddRec(const P: PMemRecord; Size: NativeUInt);
begin
  Assert(Size > 0);
  CS.Enter;
  AtomicIncrement(AllocationCount);
  AtomicIncrement(AllocatedBytes, Size);
  P^.Next := nil;
  P^.MayLeak := True;
  if not Assigned(First) then
  begin
    First := P;
    Last := P;
    P^.Prev := nil;
  end
  else begin
    Last^.Next := P;
    P^.Prev := Last;
    Last := P;
  end;
  CS.Leave;

  P^.Size := size;
  FillChar(P^.Sep, SizeOf(P^.Sep), $FF);
end;

class procedure TLeakCheck._ReleaseRec(const P: PMemRecord);
begin
  if P^.Size = 0 then
  begin
    Assert(False);
    Exit;
  end;

  CS.Enter;

  // Memory marked as non-leaking is excluded from allocation info
  if P^.MayLeak then
  begin
    AtomicDecrement(AllocationCount);
    AtomicDecrement(AllocatedBytes, P^.Size);
  end;

  if (P = Last) and (P = First) then
  begin
    First := nil;
    Last := nil;
  end
  else if P = Last then
  begin
    Last := Last^.Prev;
    Last^.Next := nil;
  end
  else if P = First then
  begin
    First := First^.Next;
    First^.Prev := nil;
  end
  else begin
    P^.Prev^.Next := P^.Next;
    P^.Next^.Prev := P^.Prev;
  end;
  CS.Leave;

  P^.Size := 0;
end;

class procedure TLeakCheck._SetLeaks(const P: PMemRecord; Value: LongBool);
begin
  if P^.Size = 0 then
    Exit;

  if P^.MayLeak <> Value then
  begin
    P^.MayLeak := Value;
    if Value then
    begin
      AtomicIncrement(AllocationCount);
      AtomicIncrement(AllocatedBytes, P^.Size);
    end
    else
    begin
      AtomicDecrement(AllocationCount);
      AtomicDecrement(AllocatedBytes, P^.Size);
    end;
  end;
end;

class function TLeakCheck.AllocMem(Size: NativeInt): Pointer;
begin
  Result := SysAllocMem(Size + SizeMemRecord);
  _AddRec(Result, Size);
  InitMem(Result);
  Inc(NativeUInt(Result), SizeMemRecord);
end;

class function TLeakCheck.CreateSnapshot: Pointer;
begin
  Result:=Last;
end;

class procedure TLeakCheck.Finalize;
begin
  if ReportMemoryLeaksOnShutdown then
    Report(nil, True);
  if Assigned(FinalizationProc) then
    FinalizationProc();
{$IFNDEF WEAKREF}
  CS.Free;
  Suspend;
{$ELSE}
  // RTL releases Weakmaps in System unit finalization that is executed later
  // it was allocated using this MemoryManager and must be released as such
  // it is then safer to leak the mutex rather then release the memory
  // improperly
  // This will cause SEGFAULT in System finalization but it still leaks less
  // memory. System should use SysGet/FreeMem internally.
{$ENDIF}
end;

class function TLeakCheck.FreeMem(P: Pointer): Integer;
begin
  Dec(NativeUInt(P), SizeMemRecord);
  _ReleaseRec(P);
  Result := SysFreeMem(P);
end;

class procedure TLeakCheck.GetLeakInfo(var Info: TLeakInfo; Rec: PMemRecord);
var
  Data: Pointer;
begin
  // Scan for object first (string require more scanning and processing)
  Data := Rec^.Data;
  Info.ClassType := GetObjectClass(Data);
  if Assigned(Info.ClassType) then
    Info.StringInfo := nil
  else if IsString(Rec, Data) then
    Info.StringInfo := Data
  else
    Info.StringInfo := nil;
end;

class function TLeakCheck.GetLeaks(Snapshot: Pointer = nil): TLeaks;
var
  P: PMemRecord;
  i: PPointer;
begin
  Result.FLength := 0;
  Snapshot := GetSnapshot(Snapshot);
  P := Snapshot;
  while Assigned(P) do
  begin
    if P^.MayLeak and not IsLeakIgnored(P) then
      Inc(Result.FLength);
    P := P^.Next;
  end;
  if Result.FLength = 0 then
  begin
    Result.FLeaks := nil;
    Exit;
  end;

  Result.FLeaks := SysGetMem(Result.FLength * SizeOf(Pointer));

  P := Snapshot;
  i := @Result.FLeaks^[0];
  while Assigned(P) do
  begin
    if P^.MayLeak and not IsLeakIgnored(P) then
    begin
      i^ := P^.Data;
      Inc(i);
    end;
    P := P^.Next;
  end;
end;

class function TLeakCheck.GetMem(Size: NativeInt): Pointer;
begin
  Result := SysGetMem(Size + SizeMemRecord);
  _AddRec(Result, Size);
  InitMem(Result);
  Inc(NativeUInt(Result), SizeMemRecord);
end;

procedure CatLeak(const Data: MarshaledAString);
begin
  LeakStr := SysReallocMem(LeakStr, StrLen(LeakStr) + Length(sLineBreak)
    + StrLen(Data) + 1);
  if LeakStr^ <> #0 then
    StrCat(LeakStr, sLineBreak);
  StrCat(LeakStr, Data);
end;

class function TLeakCheck.GetReport(Snapshot: Pointer): LeakString;
begin
  LeakStr := SysGetMem(1);
  LeakStr^ := #0;
  GetReport(CatLeak, Snapshot);
  if LeakStr^ = #0 then
  begin
    Result.FData := nil;
    SysFreeMem(LeakStr);
  end
  else
    Result.FData := LeakStr;
  LeakStr := nil;
end;

class procedure TLeakCheck.GetReport(const Callback: TLeakProc;
  Snapshot: Pointer = nil; SendSeparator: Boolean = False);
var
  Buff: MarshaledAString;
  BuffSize: Integer;

  function DivCeil(const a, b : Integer) : Integer; inline;
  begin
    Result:=(a + b - 1) div b;
  end;

  function IsChar(C: Word): Boolean; inline;
  begin
    // Printable ASCII
    Result := (C >= $20) and (C <= $7E);
  end;

  procedure EnsureBuff(IncBy: Integer);
  begin
    Inc(BuffSize, IncBy);
    if Assigned(Buff) then
      Buff := SysReallocMem(Buff, BuffSize)
    else
    begin
      Buff := SysGetMem(BuffSize);
      Buff^ := #0;
    end;
  end;

  procedure EnsureFree(Bytes: Integer);
  var
    i: Integer;
  begin
    if Assigned(Buff) then
    begin
      i := StrLen(Buff); // Position
      i := BuffSize - i; // Remaining
      if i < Bytes then
        EnsureBuff(2 * Bytes);
    end
    else
      EnsureBuff(2 * Bytes);
  end;

  procedure SendBuf;
  begin
    Callback(Buff);
    Buff^ := #0;
  end;

  procedure SendMemoryInfo;
  begin
    if SendSeparator then
    begin
      StrCat(Buff, '--------------------------------------------------------------');
      SendBuf;
    end;
    StrCat(Buff, 'Total allocation count: ');
    StrCat(Buff, IntToStr(AllocationCount));
    StrCat(Buff, ' (');
    StrCat(Buff, IntToStr(AllocatedBytes));
    StrCat(Buff, ' B)');
    SendBuf;
  end;

var
  Leak: PMemRecord;
  Data: PByte;
  LeakInfo: TLeakInfo;

  procedure AppendObject;
  var
    TypeInfo: PTypeInfo;
  begin
    TypeInfo := LeakInfo.ClassType.ClassInfo;
    StrCat(Buff, ' for class: ');
    EnsureFree(TypeInfo^.NameLength + 1);
    StrCat(Buff, MarshaledAString(NativeUInt(@TypeInfo^.NameLength) + 1),
      TypeInfo^.NameLength);
{$IFDEF AUTOREFCOUNT}
    EnsureFree(16);
    StrCat(Buff, ' {RefCount: ');
    StrCat(Buff, IntToStr(TObject(Data).RefCount));
    StrCat(Buff, '}');
{$ELSE}
    // Safer than using 'is'
    if LeakInfo.ClassType.InheritsFrom(TInterfacedObject) then
    begin
      EnsureFree(16);
      StrCat(Buff, ' {RefCount: ');
      StrCat(Buff, IntToStr(TInterfacedObject(Data).RefCount));
      StrCat(Buff, '}');
    end;
{$ENDIF}
  end;

  procedure AppendString;
  var
    i: Integer;
    WData: System.PWord;
    Size, StringLength: NativeUInt;
    StringElemSize: Integer;
    B: PByte;
  begin
    StringLength := LeakInfo.StringInfo^.length;
    StringElemSize := LeakInfo.StringInfo^.elemSize;
    Assert(StringElemSize in [1, 2]);
    EnsureFree(48 + StringLength + 1);
    if StringElemSize = 1 then
      StrCat(Buff, ' for AnsiString {RefCount: ')
    else
      StrCat(Buff, ' for UnicodeString {RefCount: ');
    StrCat(Buff, IntToStr(LeakInfo.StringInfo^.refCnt));
    StrCat(Buff, '} = ');
    Inc(Data, SizeOf(StrRec));
    if StringElemSize = 1 then
    begin
      Size := StrLen(Buff);
      Move(Data^, PByte(NativeUInt(Buff) + Size)^, StringLength);
      PByte(NativeUInt(Buff) + Size + StringLength)^ := 0;
    end
    else
    begin
      B := PByte(Buff);
      Inc(B, StrLen(Buff));
      WData := System.PWord(Data);
      for i := 1 to StringLength do
      begin
        if IsChar(WData^) then
          B^ := WData^
        else
          B^ := Ord('?');

        Inc(WData);
        Inc(B);
      end;
      B^ := 0;
    end;
  end;

  procedure SendDump;
  var
    i, j: Integer;
    Size: NativeUInt;
    TmpSize: Integer;
    TmpData: PByte;
  begin
    Size := Leak^.Size;
    if Size > 256 then
      Size := 256;
    for i := 1 to DivCeil(Size, 32) do
    begin
      StrCat(Buff, ' ');
      TmpSize := Size;
      TmpData := Data;
      for j := 1 to 32 do
      begin
        if (Size <= 0) then Break;
        StrCat(Buff, ' ');
        StrCat(Buff, IntToStr(Data^, 2, 16));
        Dec(Size);
        Inc(Data);
      end;
      Size := TmpSize;
      Data := TmpData;
      StrCat(Buff, ' | ');
      TmpData := PByte(Buff);
      Inc(TmpData, StrLen(Buff));
      for j := 1 to 32 do
      begin
        if (Size <= 0) then Break;
        if IsChar(Data^) then
          TmpData^ := Data^
        else
          TmpData^ := Ord('?');

        Dec(Size);
        Inc(Data);
        Inc(TmpData);
      end;
      TmpData^ := 0;
      SendBuf;
    end;
  end;

var
  CountSent: Boolean;
begin
  CS.Enter;
  try
    Buff := nil;
    BuffSize := 0;
    CountSent := False;
    Leak := GetSnapshot(Snapshot);
    while Assigned(Leak) do
    begin
      if not Leak^.MayLeak then
      begin
        Leak := Leak^.Next;
        Continue;
      end;

      // Test if the type is ignored
      // Scan for object first (string require more scanning and processing)
      GetLeakInfo(LeakInfo, Leak);
      if IsLeakIgnored(LeakInfo, Leak) then
      begin
        Leak := Leak^.Next;
        Continue;
      end;

      EnsureFree(256);
      if (not CountSent) then begin
        CountSent := True;
        SendMemoryInfo;
      end;
      StrCat(Buff, 'Leak detected ');
      Data := Leak^.Data;
      StrCat(Buff, IntToStr(NativeUInt(Data), SizeOf(Pointer) * 2, 16));
      StrCat(Buff, ' size ');
      StrCat(Buff, IntToStr(Leak^.Size));
      StrCat(Buff, ' B');

      if Assigned(LeakInfo.ClassType) then
        AppendObject
      else if Assigned(LeakInfo.StringInfo) then
        AppendString;
      SendBuf;

      // There should be enough space in the buffer in any case
      if not Assigned(LeakInfo.ClassType) and not Assigned(LeakInfo.StringInfo) then
        SendDump;

      Leak := Leak^.Next;
    end;
    if Assigned(Buff) then
      SysFreeMem(Buff);
  finally
    CS.Leave;
  end;
end;

class function TLeakCheck.GetSnapshot(Snapshot: Pointer): PMemRecord;
begin
  if Assigned(Snapshot) then
  begin
    Result := Last;
    while Assigned(Result) do
    begin
      if Result = Snapshot then
        Exit(Result^.Next);
      Result := Result^.Prev;
    end;
    Assert(Result = nil);
    Assert(False, 'Invalid memory snapshot');
  end
  else
    Result := First;
end;

class procedure TLeakCheck.Initialize;
begin
  GetMemoryManager(FOldMemoryManager);
  CS.Initialize;
  Resume;
{$IFDEF DEBUG}
  IsConsistent;
{$ENDIF}
end;

class procedure TLeakCheck.InitMem(P: PMemRecord);
begin
{$IF SizeOf(Pointer) = 8}
  // Cleanup the padding, it may contain random data that may get mistaken
  // as valid class reference
  if P^.Size > SizeOf(StrRec) then
    PStrRec(P.Data)^._Padding := 0;
{$IFEND}
end;

class function TLeakCheck.IsConsistent: Boolean;
var
  P: PMemRecord;
  i: Integer;
begin
  P:=First;
  i:=0;
  while Assigned(P)do
  begin
    P := P^.Next;
    Inc(i);
    if (i > $3FFFFFF) then
      Exit(False);
  end;
  P:=Last;
  i:=0;
  while Assigned(P) do
  begin
    P := P^.Prev;
    Inc(i);
    if (i > $3FFFFFF) then
      Exit(False);
  end;
  Result := True;
end;

class function TLeakCheck.IsLeakIgnored(const LeakInfo: TLeakInfo; Rec: PMemRecord): Boolean;
begin
  if IgnoredLeakTypes = [] then
    Exit(False);
  if Assigned(LeakInfo.ClassType) then
  begin
    if tkClass in IgnoredLeakTypes then
      Exit(True);
    if Assigned(InstanceIgnoredProc) then
    begin
      Result := InstanceIgnoredProc(Rec.Data, LeakInfo.ClassType);
      // Once ignored, mark as non-leak to prevent further processing
      if Result then
        _SetLeaks(Rec, False);
      Exit;
    end
    else
      Exit(False);
  end;
  if Assigned(LeakInfo.StringInfo) then
  begin
    case LeakInfo.StringInfo^.elemSize of
      1: Exit(tkLString in IgnoredLeakTypes);
      2: Exit(tkUString in IgnoredLeakTypes);
    end;
  end;
  Result := tkUnknown in IgnoredLeakTypes;
end;

class function TLeakCheck.IsLeakIgnored(Rec: PMemRecord): Boolean;
var
  Info: TLeakInfo;
begin
  if IgnoredLeakTypes = [] then
    Exit(False);
  GetLeakInfo(Info, Rec);
  Result := IsLeakIgnored(Info, Rec);
end;

class procedure TLeakCheck.MarkNotLeaking(Snapshot: Pointer);
var
  P: PMemRecord absolute Snapshot;
begin
  while Assigned(P) do
  begin
    _SetLeaks(P, False);
    P := P^.Next;
  end;
end;

class function TLeakCheck.ReallocMem(P: Pointer; Size: NativeInt): Pointer;
begin
  Dec(NativeUInt(P), SizeMemRecord);
  _ReleaseRec(P);
  Result := SysReallocMem(P, Size + SizeMemRecord);
  _AddRec(Result, Size);
  Inc(NativeUInt(Result), SizeMemRecord);
end;

class function TLeakCheck.RegisterExpectedMemoryLeak(P: Pointer): Boolean;
begin
  Dec(NativeUInt(P), SizeMemRecord);
  _SetLeaks(P, False);
  Result := True;
end;

procedure ReportLeak(const Data: MarshaledAString);
{$IF Defined(ANDROID)}
const
  TAG: MarshaledAString = MarshaledAString('leak');
begin
  __android_log_write(ANDROID_LOG_WARN, TAG, Data);
  usleep(1 * 1000);
end;
{$ELSEIF Defined(MSWINDOWS) AND Defined(NO_MESSAGEBOX)}
begin
  OutputDebugStringA(Data);
end;
{$ELSEIF Defined(MSWINDOWS)}
begin
end;
{$ELSE}
  {$MESSAGE FATAL 'Unsupported platform'}
{$IFEND}

class procedure TLeakCheck.Report(Snapshot: Pointer; SendSeparator: Boolean);
{$IF Defined(MSWINDOWS) AND NOT Defined(NO_MESSAGEBOX)}
var
  Leaks: LeakString;
begin
  Leaks := TLeakCheck.GetReport(Snapshot);
  if not Leaks.IsEmpty then
    MessageBoxA(0, Leaks, 'Leak detected', MB_ICONERROR);
  Leaks.Free;
end;
{$ELSE}
begin
  GetReport(ReportLeak, Snapshot, SendSeparator);
end;
{$IFEND}

class procedure TLeakCheck.Resume;
var
  LeakCheckingMemoryManager: TMemoryManagerEx;
begin
  with LeakCheckingMemoryManager do
  begin
    GetMem := TLeakCheck.GetMem;
    FreeMem := TLeakCheck.FreeMem;
    ReallocMem := TLeakCheck.ReallocMem;
    AllocMem := TLeakCheck.AllocMem;
    RegisterExpectedMemoryLeak := TLeakCheck.RegisterExpectedMemoryLeak;
    UnregisterExpectedMemoryLeak := TLeakCheck.UnregisterExpectedMemoryLeak;
  end;
  SetMemoryManager(LeakCheckingMemoryManager);
end;

class procedure TLeakCheck.RunSuspended(Proc: TProc);
begin
  Suspend;
  try
    Proc();
  finally
    Resume;
  end;
end;

class procedure TLeakCheck.Suspend;
begin
  SetMemoryManager(FOldMemoryManager);
end;

class function TLeakCheck.UnregisterExpectedMemoryLeak(P: Pointer): Boolean;
begin
  Dec(NativeUInt(P), SizeMemRecord);
  _SetLeaks(P, True);
  Result := True;
end;

{$ENDREGION}

{$REGION 'TLeakCheck.TMemRecord'}

function TLeakCheck.TMemRecord.Data: Pointer;
begin
  NativeUInt(Result):=NativeUInt(@Self) + SizeOf(TMemRecord);
end;

{$ENDREGION}

{$REGION 'TCritSec'}

procedure CheckOSError(LastError: Integer); inline;
begin
  if LastError <> 0 then
    raise TObject.Create;
end;

procedure TCritSec.Enter;
begin
{$IFDEF MSWINDOWS}
  EnterCriticalSection(FHandle);
{$ENDIF}
{$IFDEF POSIX}
  CheckOSError(pthread_mutex_lock(FHandle));
{$ENDIF}
end;

procedure TCritSec.Free;
begin
{$IFDEF MSWINDOWS}
  DeleteCriticalSection(FHandle);
{$ENDIF}
{$IFDEF POSIX}
  pthread_mutex_destroy(FHandle);
{$ENDIF}
end;

procedure TCritSec.Initialize;
{$IFDEF MSWINDOWS}
begin
  InitializeCriticalSection(FHandle);
end;
{$ENDIF}
{$IFDEF POSIX}
var
  Attr: pthread_mutexattr_t;
begin
  CheckOSError(pthread_mutexattr_init(Attr));
  CheckOSError(pthread_mutexattr_settype(Attr, PTHREAD_MUTEX_RECURSIVE));
  CheckOSError(pthread_mutex_init(FHandle, Attr));
end;
{$ENDIF}

procedure TCritSec.Leave;
begin
{$IFDEF MSWINDOWS}
  LeaveCriticalSection(FHandle);
{$ENDIF}
{$IFDEF POSIX}
  CheckOSError(pthread_mutex_unlock(FHandle));
{$ENDIF}
end;

{$ENDREGION}

{$REGION 'TLeak'}

class operator TLeak.Equal(const L: TLeak; const R: Pointer): Boolean;
begin
  Result := L.Data = R;
end;

function TLeak.GetSize: NativeUInt;
begin
  Result := Data.ToRecord.Size;
end;

function TLeak.GetTypeKind: TTypeKind;
begin
  if Assigned(GetObjectClass(Data)) then
    Result := tkClass
  else if IsString(Data.ToRecord, Data) then
  begin
    case PStrRec(Data)^.elemSize of
      1: Result := tkLString;
      2: Result := tkUString;
      else
        Result := tkUnknown;
    end;
  end
  else
    Result := tkUnknown;
end;

class operator TLeak.Implicit(const Leak: TLeak): Pointer;
begin
  Result := Leak.Data;
end;

{$ENDREGION}

{$REGION 'TLeaks'}

procedure TLeaks.Free;
begin
  if Assigned(FLeaks) then
    SysFreeMem(FLeaks);
end;

function TLeaks.GetEnumerator: TLeaksEnumerator;
begin
  Result.FRemaining := FLength;
  if FLength > 0 then
  begin
    Result.FCurrent := @FLeaks^[0];
    Dec(Result.FCurrent);
  end;
end;

function TLeaks.GetLeak(Index: Integer): TLeak;
begin
  Result.FData := FLeaks^[Index];
end;

function TLeaks.GetTotalSize: NativeUInt;
var
  P: TLeak;
begin
  Result := 0;
  for P in Self do
    Inc(Result, P.Size);
end;

function TLeaks.IsEmpty: Boolean;
begin
  Result := FLength = 0;
end;

{$ENDREGION}

{$REGION 'TLeaks.TLeaksEnumerator'}

function TLeaks.TLeaksEnumerator.GetCurrent: TLeak;
begin
  Result.FData := FCurrent^;
end;

function TLeaks.TLeaksEnumerator.MoveNext: Boolean;
begin
  Result := FRemaining > 0;
  Dec(FRemaining);
  Inc(FCurrent);
end;

{$ENDREGION}

{$REGION 'LeakString'}

procedure LeakString.Free;
begin
  if Assigned(FData) then
    SysFreeMem(FData);
end;

class operator LeakString.Implicit(const Value: LeakString): MarshaledAString;
begin
  Result := Value.Data;
end;

function LeakString.IsEmpty: Boolean;
begin
  Result := not Assigned(FData);
end;

{$ENDREGION}

{$REGION 'TPointerHelper'}

function TPointerHelper.ToRecord: TLeakCheck.PMemRecord;
begin
  NativeUInt(Result) := NativeUInt(Self) - SizeMemRecord;
end;

{$ENDREGION}

{$REGION 'FastMM derived functions'}

{$REGION 'License & acknowledgement'}
  // Following two functions were originaly released in FastMM project and
  // modified a bit to support our needs.
  // Original developer:
  //   Professional Software Development / Pierre le Riche
  // Original licenses:
  //   Mozilla Public License 1.1 (MPL 1.1, available from
  //   http://www.mozilla.org/MPL/MPL-1.1.html) or the GNU Lesser General Public
  //   License 2.1 (LGPL 2.1, available from
  //   http://www.opensource.org/licenses/lgpl-license.php)
  // Changes:
  //   * Posix support
  //   * Checking of class TypeInfo to prevent false positives even better
{$ENDREGION}

{Returns the class for a memory block. Returns nil if it is not a valid class}
function GetObjectClass(APointer: Pointer): TClass;
{$IFDEF MSWINDOWS}
var
  LMemInfo: TMemoryBasicInformation;
{$ENDIF}

  {Checks whether the given address is a valid address for a VMT entry.}
  function IsValidVMTAddress(APAddress: Pointer): Boolean;
  begin
    {Do some basic pointer checks: Must be dword aligned and beyond 64K}
    if (Cardinal(APAddress) > 65535)
      and (Cardinal(APAddress) and 3 = 0) then
    begin
{$IFDEF MSWINDOWS}
      {Do we need to recheck the virtual memory?}
      if (Cardinal(LMemInfo.BaseAddress) > Cardinal(APAddress))
        or ((Cardinal(LMemInfo.BaseAddress) + LMemInfo.RegionSize) < (Cardinal(APAddress) + 4)) then
      begin
        {Get the VM status for the pointer}
        LMemInfo.RegionSize := 0;
        VirtualQuery(APAddress,  LMemInfo, SizeOf(LMemInfo));
      end;
      {Check the readability of the memory address}
      Result := (LMemInfo.RegionSize >= 4)
        and (LMemInfo.State = MEM_COMMIT)
        and (LMemInfo.Protect and (PAGE_READONLY or PAGE_READWRITE or PAGE_EXECUTE or PAGE_EXECUTE_READ or PAGE_EXECUTE_READWRITE or PAGE_EXECUTE_WRITECOPY) <> 0)
        and (LMemInfo.Protect and PAGE_GUARD = 0);
{$ENDIF}
{$IFDEF POSIX}
      if Assigned(TLeakCheck.AddrPermProc) then
        Result := peRead in TLeakCheck.AddrPermProc(APAddress)
      else
        Result := False;
{$ENDIF}
    end
    else
      Result := False;
  end;

  {Returns true if AClassPointer points to a class VMT}
  function InternalIsValidClass(AClassPointer: Pointer; ADepth: Integer = 0): Boolean;
  var
    LParentClassSelfPointer: PCardinal;
    LTypeInfo: PTypeInfo;
  begin
    {Check that the self pointer, parent class self pointer, typeinfo pointer
     and typeinfo addresses are valid}
    if (ADepth < 1000)
      and IsValidVMTAddress(Pointer(Integer(AClassPointer) + vmtSelfPtr))
      and IsValidVMTAddress(Pointer(Integer(AClassPointer) + vmtParent))
      and IsValidVMTAddress(Pointer(Integer(AClassPointer) + vmtTypeInfo))
      and IsValidVMTAddress(PPointer(Integer(AClassPointer) + vmtTypeInfo)^) then
    begin
      {Get a pointer to the parent class' self pointer}
      LParentClassSelfPointer := PPointer(Integer(AClassPointer) + vmtParent)^;
      LTypeInfo := PPTypeInfo(Integer(AClassPointer) + vmtTypeInfo)^;
      {Check that the self pointer as well as the parent class is valid}
      Result := (PPointer(Integer(AClassPointer) + vmtSelfPtr)^ = AClassPointer)
        and ((LParentClassSelfPointer = nil)
          or ((LTypeInfo^.Kind = tkClass)
            and IsValidVMTAddress(LParentClassSelfPointer)
            and InternalIsValidClass(PCardinal(LParentClassSelfPointer^), ADepth + 1)));
    end
    else
      Result := False;
  end;

begin
  {Get the class pointer from the (suspected) object}
  Result := TClass(PCardinal(APointer)^);
{$IFDEF MSWINDOWS}
  {No VM info yet}
  LMemInfo.RegionSize := 0;
{$ENDIF}
  {Check the block}
  if (not InternalIsValidClass(Pointer(Result), 0)) then
    Result := nil;
end;

function IsString(Rec: TLeakCheck.PMemRecord; LDataPtr: Pointer): Boolean;
var
  LStringLength,
  LElemSize,
  LCharInd: Integer;
  LStringMemReq: NativeUInt;
  LPossibleString: Boolean;
  LPAnsiStr: MarshaledAString;
  LPUniStr: PWideChar;
begin
  Result := False;
  {Reference count < 256}
  if PStrRec(LDataPtr).refCnt < 256 then
  begin
    {Get the string length and element size}
    LStringLength := PStrRec(LDataPtr).length;
{$IF RTLVersion >= 20}
    LElemSize := PStrRec(LDataPtr).elemSize;
{$ELSE}
    LElemSize := 1;
{$IFEND}
    {Valid element size?}
    if (LElemSize = 1) or (LElemSize = 2) then
    begin
      {Calculate the amount of memory required for the string}
      LStringMemReq := (LStringLength + 1) * LElemSize + SizeOf(StrRec);
      {Does the string fit?}
      if (LStringLength > 0)
        and (LStringMemReq <= Rec.Size) then
      begin
        {It is possibly a string}
        LPossibleString := True;
        {Check for no characters < #32. If there are, then it is
         probably not a string.}
        // Honza: But if it is and is used for binary data, we will dump it
        //        later either way.
        if LElemSize = 1 then
        begin
          {Check that all characters are >= #32}
          LPAnsiStr := MarshaledAString(NativeUInt(LDataPtr) + SizeOf(StrRec));
          for LCharInd := 1 to LStringLength do
          begin
            LPossibleString := LPossibleString and (LPAnsiStr^ >= #32);
            Inc(LPAnsiStr);
          end;
          {Must have a trailing #0}
          if LPossibleString and (LPAnsiStr^ = #0) then
          begin
            Result := True;
          end;
        end
        else
        begin
          {Check that all characters are >= #32}
          LPUniStr := PWideChar(NativeUInt(LDataPtr) + SizeOf(StrRec));
          for LCharInd := 1 to LStringLength do
          begin
            LPossibleString := LPossibleString and (LPUniStr^ >= #32);
            Inc(LPUniStr);
          end;
          {Must have a trailing #0}
          if LPossibleString and (LPUniStr^ = #0) then
          begin
            Result := True;
          end;
        end;
      end;
    end;
  end;
end;

{$ENDREGION}

{$REGION 'System shadowed functions'}

{$IFNDEF MSWINDOWS}

function RegisterExpectedMemoryLeak(P: Pointer): Boolean;
begin
  Result := (P <> nil) and TLeakCheck.RegisterExpectedMemoryLeak(P);
end;

function UnregisterExpectedMemoryLeak(P: Pointer): Boolean;
begin
  Result := (P <> nil) and TLeakCheck.UnregisterExpectedMemoryLeak(P);
end;

{$ENDIF}

{$ENDREGION}

initialization
  TLeakCheck.Initialize;
finalization
  TLeakCheck.Finalize;

end.
