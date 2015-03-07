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
  TLeaks = record
  private type
    TPointerArray = array[0..0] of Pointer;
  public type
    TLeaksEnumerator = record
    private
      FCurrent: PPointer;
      FRemaining: Integer;
      function GetCurrent: Pointer; inline;
    public
      property Current: Pointer read GetCurrent;
      function MoveNext: Boolean; inline;
    end;
  private
    FLength: Integer;
    FLeaks: ^TPointerArray;
    function GetLeak(Index: Integer): Pointer; inline;
  public
    procedure Free;
    function GetEnumerator: TLeaksEnumerator; inline;

    property Leaks[Index: Integer]: Pointer read GetLeak; default;
    property Length: Integer read FLength;
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
      Size: NativeInt;
      MayLeak: LongBool;
      Sep: packed array[0..253] of NativeInt;
      function Data: Pointer; inline;
    end;
  public type
    TPosixProcEntryPermissions = set of (peRead, peWrite, peExecute, peShared,
		  pePrivate {copy on write});
    TLeakProc = procedure(const Data: MarshaledAString);
    TAddrPermProc = function(Address: Pointer): TPosixProcEntryPermissions;
    TProc = procedure;
  private class var
    FOldMemoryManager: TMemoryManagerEx;
  private
    class function GetMem(Size: NativeInt): Pointer; static;
    class function FreeMem(P: Pointer): Integer; static;
    class function ReallocMem(P: Pointer; Size: NativeInt): Pointer; static;

    class function AllocMem(Size: NativeInt): Pointer; static;
    class function RegisterExpectedMemoryLeak(P: Pointer): Boolean; static;
    class function UnregisterExpectedMemoryLeak(P: Pointer): Boolean; static;

    class procedure _AddRec(const P: PMemRecord; size: Integer); static;
    class procedure _ReleaseRec(const P: PMemRecord); static;
    class procedure _SetLeaks(const P: PMemRecord; Value: LongBool); static;

    class function IsConsistent: Boolean; static;

    class procedure Initialize; static;
    class procedure Finalize; static;

    class procedure Resume; static;
    class procedure Suspend; static;

    class function GetSnapshot(Snapshot: Pointer): PMemRecord; static;
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
    class procedure Report(Snapshot: Pointer = nil); static;
    class function GetLeaks(Snapshot: Pointer = nil): TLeaks; static;
    class procedure GetReport(const Callback: TLeakProc;
      Snapshot: Pointer = nil); overload; static;
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
  end;

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

type
  PTypeInfo = ^TTypeInfo;
  TTypeInfo = record
    Kind: TTypeKind;
    Name: Byte;
  end;

const
  SizeMemRecord = SizeOf(TLeakCheck.TMemRecord);

var
  First: TLeakCheck.PMemRecord = nil;
  Last: TLeakCheck.PMemRecord = nil;
  AllocationCount: Integer = 0;
  GBuff: array[0..31] of Byte;
  LeakStr: MarshaledAString = nil;

const
  SZero: MarshaledAString = MarshaledAString('0');

  HexTable: array[0..15] of Byte = (Ord('0'), Ord('1'), Ord('2'), Ord('3'),
    Ord('4'), Ord('5'), Ord('6'), Ord('7'), Ord('8'), Ord('9'), Ord('A'),
    Ord('B'), Ord('C'), Ord('D'), Ord('E'), Ord('F'));

function GetObjectClass(APointer: Pointer): TClass; forward;

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

function IntToStr(Value: NativeUInt; MinChars: Integer = 0; Base: NativeUInt = 10): MarshaledAString;
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

type
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

var
  CS: TCritSec;

{ TLeakCheck }

class procedure TLeakCheck._AddRec(const P: PMemRecord; size: Integer);
begin
  CS.Enter;
  AtomicIncrement(AllocationCount);
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
  CS.Enter;
  AtomicDecrement(AllocationCount);
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
end;

class procedure TLeakCheck._SetLeaks(const P: PMemRecord; Value: LongBool);
begin
  if P^.MayLeak <> Value then
  begin
    P^.MayLeak := Value;
    if Value then
      AtomicIncrement(AllocationCount)
    else
      AtomicDecrement(AllocationCount);
  end;
end;

class function TLeakCheck.AllocMem(Size: NativeInt): Pointer;
begin
  Result := SysAllocMem(Size + SizeMemRecord);
  _AddRec(Result, Size);
  Inc(NativeInt(Result), SizeMemRecord);
end;

class function TLeakCheck.CreateSnapshot: Pointer;
begin
  Result:=Last;
end;

class procedure TLeakCheck.Finalize;
begin
  if ReportMemoryLeaksOnShutdown then
    Report;
  if Assigned(FinalizationProc) then
    FinalizationProc();
  CS.Free;
  Suspend;
end;

class function TLeakCheck.FreeMem(P: Pointer): Integer;
begin
  Dec(NativeInt(P), SizeMemRecord);
  _ReleaseRec(P);
  Result := SysFreeMem(P);
end;

class function TLeakCheck.GetLeaks(Snapshot: Pointer = nil): TLeaks;
var
  P: PMemRecord;
  i: PPointer;
begin
  Result.FLength := 0;
  Snapshot:=GetSnapshot(Snapshot);
  P := Snapshot;
  while Assigned(P) do
  begin
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
    i^ := P^.Data;
    P := P^.Next;
    Inc(i);
  end;
end;

class function TLeakCheck.GetMem(Size: NativeInt): Pointer;
begin
  Result := SysGetMem(Size + SizeMemRecord);
  _AddRec(Result, Size);
  Inc(NativeInt(Result), SizeMemRecord);
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
  Snapshot: Pointer = nil);
var
  Buff: MarshaledAString;
  BuffSize: Integer;

  function DivCeil(const a, b : Integer) : Integer;
  begin
    Result:=(a + b - 1) div b;
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

var
  Leak: PMemRecord;
  CountSent: Boolean;
  Data: PByte;
  Size: Integer;
  i, j: Integer;
  Clazz: TClass;
  TypeInfo: PTypeInfo;
  TmpSize: Integer;
  TmpData: PByte;
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

      EnsureFree(256);
      if (not CountSent) then begin
        CountSent := True;
        StrCat(Buff, 'Total allocation count: ');
        StrCat(Buff, IntToStr(AllocationCount));
        SendBuf
      end;
      StrCat(Buff, 'Leak detected ');
      Data := Leak^.Data;
      StrCat(Buff, IntToStr(NativeInt(Data), SizeOf(Pointer) * 2, 16));
      StrCat(Buff, ' size ');
      Size := Leak^.Size;
      StrCat(Buff, IntToStr(Size));
      Clazz := GetObjectClass(Data);
      if Assigned(Clazz) then
      begin
        TypeInfo := Clazz.ClassInfo;
        StrCat(Buff, ' for class: ');
        EnsureFree(TypeInfo^.Name + 1);
        StrCat(Buff, MarshaledAString(NativeUInt(@TypeInfo^.Name) + 1),
          TypeInfo^.Name);
{$IFDEF AUTOREFCOUNT}
        EnsureFree(16);
        StrCat(Buff, ' {RefCount: ');
        StrCat(Buff, IntToStr(TObject(Data).RefCount));
        StrCat(Buff, '}');
{$ELSE}
        if TObject(Data) is TInterfacedObject then
        begin
          EnsureFree(16);
          StrCat(Buff, ' {RefCount: ');
          StrCat(Buff, IntToStr(TInterfacedObject(Data).RefCount));
          StrCat(Buff, '}');
        end;
{$ENDIF}
      end;
      SendBuf;

      // There should be enough space in the buffer in any case
      if not Assigned(Clazz) then
      begin
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
          GBuff[1] := 0;
          for j := 1 to 32 do
          begin
            if (Size <= 0) then Break;
            if (Data^ >= $20) and (Data^ <= $7E) then
              GBuff[0] := Data^
            else
              GBuff[0] := Ord('?');

            StrCat(Buff, @GBuff[0]);
            Dec(Size);
            Inc(Data);
          end;
          SendBuf;
        end;
      end;

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
    Assert(false, 'Invalid memory snapshot');
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
  Dec(NativeInt(P), SizeMemRecord);
  _ReleaseRec(P);
  Result := SysReallocMem(P, Size + SizeMemRecord);
  _AddRec(Result, Size);
  Inc(NativeInt(Result), SizeMemRecord);
end;

class function TLeakCheck.RegisterExpectedMemoryLeak(P: Pointer): Boolean;
begin
  Dec(NativeInt(P), SizeMemRecord);
  _SetLeaks(P, False);
  Result := True;
end;

{$IFNDEF MSWINDOWS}
procedure ReportLeak(const Data: MarshaledAString);
{$IFDEF ANDROID}
const
  TAG: MarshaledAString = MarshaledAString('leak');
begin
  __android_log_write(ANDROID_LOG_WARN, TAG, Data);
  usleep(1 * 1000);
end;
{$ENDIF}
{$ENDIF}

class procedure TLeakCheck.Report(Snapshot: Pointer);
{$IFDEF MSWINDOWS}
var
  Leaks: LeakString;
begin
  Leaks := TLeakCheck.GetReport(Snapshot);
  if not Leaks.IsEmpty then
    MessageBoxA(0, Leaks, 'Leak detected', MB_ICONERROR);
  Leaks.Free;
end;
{$ENDIF}
{$IFDEF POSIX}
begin
  GetReport(ReportLeak, Snapshot);
end;
{$ENDIF}

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
  Dec(NativeInt(P), SizeMemRecord);
  _SetLeaks(P, True);
  Result := True;
end;

{ TLeaks }

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

function TLeaks.GetLeak(Index: Integer): Pointer;
begin
  Result:=FLeaks^[Index];
end;

{ TLeakCheck.TMemRecord }

function TLeakCheck.TMemRecord.Data: Pointer;
begin
  NativeInt(Result):=NativeInt(@Self) + SizeOf(TMemRecord);
end;

{ TLeaks.TLeaksEnumerator }

function TLeaks.TLeaksEnumerator.GetCurrent: Pointer;
begin
  Result := FCurrent^;
end;

function TLeaks.TLeaksEnumerator.MoveNext: Boolean;
begin
  Result := FRemaining > 0;
  Dec(FRemaining);
  Inc(FCurrent);
end;

{ LeakString }

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

{ TCritSec }

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

{Returns the class for a memory block. Returns nil if it is not a valid class}
// FastMM
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
  begin
    {Check that the self pointer as well as parent class self pointer addresses
     are valid}
    if (ADepth < 1000)
      and IsValidVMTAddress(Pointer(Integer(AClassPointer) + vmtSelfPtr))
      and IsValidVMTAddress(Pointer(Integer(AClassPointer) + vmtParent)) then
    begin
      {Get a pointer to the parent class' self pointer}
      LParentClassSelfPointer := PPointer(Integer(AClassPointer) + vmtParent)^;
      {Check that the self pointer as well as the parent class is valid}
      Result := (PPointer(Integer(AClassPointer) + vmtSelfPtr)^ = AClassPointer)
        and ((LParentClassSelfPointer = nil)
          or (IsValidVMTAddress(LParentClassSelfPointer)
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

initialization
  TLeakCheck.Initialize;
finalization
  TLeakCheck.Finalize;

end.
