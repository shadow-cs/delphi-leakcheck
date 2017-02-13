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

{$I LeakCheck.inc}

interface

{$REGION 'Delphi version dependant shadowed types'}

{$IF CompilerVersion >= 25} // >= XE4
  {$LEGACYIFEND ON}
{$IFEND}
{$IF CompilerVersion < 28} // < XE7
type
  TTypeKind = (tkUnknown, tkInteger, tkChar, tkEnumeration, tkFloat,
    tkString, tkSet, tkClass, tkMethod, tkWChar, tkLString, tkWString,
    tkVariant, tkArray, tkRecord, tkInterface, tkInt64, tkDynArray, tkUString,
    tkClassRef, tkPointer, tkProcedure);
{$ELSE}
const
  tkClass = System.tkClass;
{$IFEND}
{$IF CompilerVersion >= 27} // >= XE6
  {$DEFINE HAS_STATIC_OPERATORS}
{$IFEND}
{$IF CompilerVersion < 24} // < XE3
type
  MarshaledAString = PAnsiChar;
{$ELSE}
  {$DEFINE HAS_ATOMICS}
{$IFEND}
{$IF CompilerVersion >= 23} // >= XE2
  {$DEFINE XE2_UP}
{$IFEND}

{$ENDREGION}

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

    class operator Implicit(const Value: LeakString): MarshaledAString; {$IFDEF HAS_STATIC_OPERATORS}static;{$ENDIF} inline;

    property Data: MarshaledAString read FData;
  end;

  TLeakCheck = record
  private
    {$I LeakCheck.Configuration.inc}
    /// <summary>
    ///   Size limit of <c>InstanceSize</c> that is considered reasonable for
    ///   interface scanning.
    /// </summary>
    MaxClassSize = $10000;
  private type
    PMemRecord = ^TMemRecord;
{$IF MaxStackSize > 0}
    TStackTrace = packed record
      Trace: array[0..MaxStackSize - 1] of Pointer;
      Count: NativeInt;
    end;
{$IFEND}
    TMemRecord = record
      Prev, Next: PMemRecord;
      CurrentSize: NativeUInt;
      PrevSize: NativeUInt;
      MayLeak: LongBool;
{$IF EnableFreedObjectDetection}
      PrevClass: TClass;
{$IFEND}
{$IF MaxStackSize > 0}
      StackAllocated: TStackTrace;
{$IF RecordFreeStackTrace}
      StackFreed: TStackTrace;
{$IFEND}
{$IFEND}
      Sep: packed array[0..7] of NativeInt;
      function Data: Pointer; inline;

      /// <summary>
      ///   Sanitized size of the given record regardless of freed state.
      /// </summary>
      function Size: NativeUInt; inline;
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
    TGetStackTrace = function(IgnoredFrames: Integer; Data: PPointer;
      Size: Integer): Integer;
    /// <summary>
    ///   Ref-counted instance is held by the LeakCheck and released just prior
    ///   releasing itself (after all leaks are reported). May use strings
    ///   internally but have to properly release them and not expose them to
    ///   LeakCheck.
    /// </summary>
    IStackTraceFormatter = interface
      /// <summary>
      ///   Formats the code address pointer to symbolic representation.
      /// </summary>
      /// <param name="Addr">
      ///   Code address
      /// </param>
      /// <param name="Buffer">
      ///   Destination buffer, null terminated ANSI char `C` string
      /// </param>
      /// <param name="Size">
      ///   Size of the destination buffer, number of bytes (including the
      ///   null-terminator) written to the destination buffer MUST NOT exceed
      ///   this parameter.
      /// </param>
      /// <returns>
      ///   <para>
      ///     Number of bytes (characters) written to the buffer <b>not</b>
      ///     including the null-terminator.
      ///   </para>
      ///   <para>
      ///     If the result is <b>zero</b>, current frame is skipped and will
      ///     not be shown in the report.
      ///   </para>
      ///   <para>
      ///     If the result is <b>negative</b>, current and all following
      ///     frames will be skipped and will not be shown in the report
      ///     (current trace formatting will be aborted).
      ///   </para>
      /// </returns>
      function FormatLine(Addr: Pointer; const Buffer: MarshaledAString;
        Size: Integer): Integer;
    end;
    TGetStackTraceFormatter = function: IStackTraceFormatter;
    TProc = procedure;
    TTypeKinds = set of TTypeKind;
    /// <summary>
    ///   Helper record for creating snapshots that persist valid as long as <c>
    ///   TSnapshot</c> is in scope. It also simplifies use of <c>
    ///   MarkNotLeaking</c> since no previous allocation may be mistakenly
    ///   marked as not a leak. TSnapshot itself (its creation) is thread-safe
    ///   but keep in mind that all memory leaks are reported and ignored if
    ///   used together with other <c>TLeakCheck</c> functions so use with
    ///   care!
    /// </summary>
    TSnapshot = record
    private
      /// <summary>
      ///   Asserts that snapshot is valid as long as it is needed.
      /// </summary>
      FAsserter: IInterface;
      FSnapshot: Pointer;
    public
      property Snapshot: Pointer read FSnapshot;
      procedure Create;
      procedure Free;
      function LeakSize: NativeUInt;
    end;
    TFreedObject = class
    end;
  public const
    StringSkew = SizeOf(StrRec);
  private class var
    FOldMemoryManager: TMemoryManagerEx;
{$IF MaxStackSize > 0}
    FStackTraceFormatter: IStackTraceFormatter;
{$IFEND}
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
    class function ToRecord(P: Pointer): TLeakCheck.PMemRecord; static; inline;
{$IFDEF ANDROID}
    class function IsValidRec(Rec: PMemRecord): Boolean; static;
{$ENDIF}

    class procedure InitMem(P: PMemRecord); static; inline;

{$IFDEF DEBUG}
    class function IsConsistent: Boolean; static;
{$ENDIF}

    class procedure Initialize; static;
    class procedure Finalize; static;

    class procedure Resume; static;
    class procedure Suspend; static;

    class function GetSnapshot(Snapshot: Pointer): PMemRecord; static;
    class function IsLeakIgnored(Rec: PMemRecord): Boolean; overload; static;
    class function IsLeakIgnored(const LeakInfo: TLeakInfo; Rec: PMemRecord): Boolean; overload; static;
    class procedure GetLeakInfo(var Info: TLeakInfo; Rec: PMemRecord); static;
{$IF EnableVirtualCallsOnFreedObjectInterception}
    class procedure ReportInvalidVirtualCall(const Self: TObject; ATypeInfo: Pointer); static;
{$IFEND}
{$IF EnableInterfaceCallsOnFreedObjectInterception}
    class procedure ReportInvalidInterfaceCall(Self, SelfStd: Pointer; ATypeInfo: Pointer); static;
{$IFEND}

{$IF MaxStackSize > 0}
    class procedure GetStackTrace(var Trace: TStackTrace); static;
    class procedure InitializeStackFormatter; static;
{$IFEND}
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
    ///   Begins ignored block where all allocations are marked as not-leaking
    ///   by default.
    /// </summary>
    /// <remarks>
    ///   Increments ignore block counter, multiple nested ignore blocks are
    ///   allowed. Not thread-safe.
    /// </remarks>
    class procedure BeginIgnore; static;
    /// <summary>
    ///   Ends ignored block where all allocations are marked as not-leaking by
    ///   default.
    /// </summary>
    /// <remarks>
    ///   Decrements ignore block counter, multiple nested ignore blocks are
    ///   allowed. Not thread-safe.
    /// </remarks>
    class procedure EndIgnore; static;

    /// <summary>
    ///   Indicate that any allocation made between given snapshot and current
    ///   last allocation will not be treated as a leak. Note that the snapshot
    ///   is cerated on the last allocation so last allocation and all
    ///   allocations after that will be ignored. Make sure the last allocation
    ///   was made by known code before calling <c>CreateSnapshot</c>.
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

    class procedure CleanupStackTraceFormatter; static;

    /// <summary>
    ///   Executes given code with suspended memory manager code, all release
    ///   code must be executed in RunSuspended as well.
    /// </summary>
    class procedure RunSuspended(Proc: TProc); experimental; static;

    /// <summary>
    ///   Performs multiple checks on given pointer and if it looks like a
    ///   class returns its type.
    /// </summary>
    /// <param name="SafePtr">
    ///   If True the pointer is treated as safe and its dereference is assumed
    ///   to always succeed.
    /// </param>
    class function GetObjectClass(APointer: Pointer; SafePtr: Boolean = False): TClass; static;
    /// <summary>
    ///   Performs multiple checks on given class type and if it looks like a
    ///   class returns true or false otherwise.
    /// </summary>
    class function IsValidClass(AClassType: TClass): Boolean; static;
    /// <summary>
    ///   Returns <c>true</c> if given pointer looks like ANSI or Unicode
    ///   string. Note that you have to pass pointer to the <c>StrRec</c>
    ///   structure (stuff before the string skew) <b>not</b> the string
    ///   pointer itself.
    /// </summary>
    class function IsString(APointer: Pointer): Boolean; static;
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

    /// <summary>
    ///   If set and <c>MaxStackSize</c> is greater than 0 each allocation will
    ///   use this function to collect stack trace of the allocation.
    /// </summary>
    GetStackTraceProc: TGetStackTrace;

    /// <summary>
    ///   Called when stack trace formatter is required, all allocations made
    ///   by this function or subsequent calls are automatically registered as
    ///   not-leaking. All caches should be initialized by the constructor or
    ///   ignored manually later.
    /// </summary>
    GetStackTraceFormatterProc: TGetStackTraceFormatter;
  end;

{$IFNDEF MSWINDOWS}

// In System but not available on other platforms
function RegisterExpectedMemoryLeak(P: Pointer): Boolean; inline;
function UnregisterExpectedMemoryLeak(P: Pointer): Boolean; inline;

{$ENDIF}

implementation

uses
{$IFDEF MSWINDOWS}
  Windows;
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

{$MINENUMSIZE 1}
{$IF SizeOf(Pointer) = 4}
  {$ALIGN 4}
{$ELSEIF SizeOf(Pointer) = 8}
  {$ALIGN 8}
{$ELSE}
  {$MESSAGE FATAL 'Unsupported pointer size'}
{$IFEND}

type
  PShortString = ^TShortString;
  TShortString = packed record
    case Byte of
      0: (Length: Byte; Data: Byte);
{$IF Declared(ShortString)}
      1: (Str: ShortString);
{$IFEND}
  end;

  PTypeInfo = ^TTypeInfo;
  PPTypeInfo = ^PTypeInfo;
  TTypeInfo = record
    Kind: TTypeKind;
    Name: TShortString;
  end;

  TOrdType = (otSByte, otUByte, otSWord, otUWord, otSLong, otULong);

  PIntegerTypeData = ^TIntegerTypeData;
  TIntegerTypeData = packed record
    OrdType: TOrdType;
    MinValue: Longint;
    MaxValue: Longint;
  end;

  StrRec = TLeakCheck.StrRec;
  PStrRec = TLeakCheck.PStrRec;

{$IFNDEF MSWINDOWS}
  // Just a shadowed type with no other use than just make the code cleaner
  // with less IFDEFs (below).
  TMemoryBasicInformation = record
    RegionSize: NativeInt;
  end;
{$ENDIF}

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

  TStringBuffer = record
  strict private
    FBuffer: MarshaledAString;
    FBufferSize: NativeInt;
  public
    class function Create: TStringBuffer; static;

    procedure EnsureBuff(IncBy: NativeInt);
    procedure EnsureFree(Bytes: NativeInt);
    procedure Clear;
    procedure Free;

    property Size: NativeInt read FBufferSize;

    class operator Implicit(const ABuffer: TStringBuffer): MarshaledAString; inline;
    class operator Explicit(const ABuffer: TStringBuffer): NativeUInt; inline;
    class operator Explicit(const ABuffer: TStringBuffer): PByte; inline;
  end;

  PClass = ^TClass;

  TClassVirtualMethod = procedure(const Self: TObject);
  TInterfaceMethod = procedure(const Self: Pointer);
  TInterfaceStdMethod = procedure(const Self: Pointer); stdcall;

  PClassData = ^TClassData;
  TClassData = record
    SelfPtr: TClass;
    IntfTable: Pointer;
    AutoTable: Pointer;
    InitTable: Pointer;
    TypeInfo: PTypeInfo;
    FieldTable: Pointer;
    MethodTable: Pointer;
    DynamicTable: Pointer;
    ClassName: PShortString;
    InstanceSize: Integer;
    Parent: PClass;

    case Byte of
      1 : (
{$IFDEF AUTOREFCOUNT}
        __ObjAddRef: TClassVirtualMethod;
        __ObjRelease: TClassVirtualMethod;
{$ENDIF}
        Equals: TClassVirtualMethod;
        GetHashCode: TClassVirtualMethod;
        ToString: TClassVirtualMethod;
        SafeCallException: TClassVirtualMethod;
        AfterConstruction: TClassVirtualMethod;
        BeforeDestruction: TClassVirtualMethod;
        Dispatch: TClassVirtualMethod;
        DefaultHandler: TClassVirtualMethod;
        NewInstance: TClassVirtualMethod;
        FreeInstance: TClassVirtualMethod;
        Destroy: TClassVirtualMethod;
        VirtualMethods_: array[0..0] of TClassVirtualMethod);
    2 : (VirtualMethods: array[0..255] of TClassVirtualMethod);
  end;

  TIntfVTable = record
    QueryInterface: TInterfaceStdMethod;
    AddRef: TInterfaceStdMethod;
    Release: TInterfaceStdMethod;
    Methods: array[3..255] of TInterfaceMethod;
  end;

{$IF TLeakCheck.EnableVirtualCallsOnFreedObjectInterception}
  TInvalidVirtualCall<E> = record
    class procedure Indexed(const Self: TObject); static;
  end;
{$IFEND}

{$IF TLeakCheck.EnableInterfaceCallsOnFreedObjectInterception}
  TInvalidInterfaceCall<E> = record
    class procedure Indexed(const Self: Pointer); static;
    class procedure IndexedStd(const Self: Pointer); static; stdcall;
  end;
{$IFEND}

{$IF TLeakCheck.NeedsIndexTypes}
{$REGION 'Index types'}
  // Types used to get index of virtual proc
  // Generated by Excel =CONCATENATE("  T";DEC2HEX(A1);" = ";A1;"..";A1;";")
  T0 = 0..0;
  T1 = 1..1;
  T2 = 2..2;
  T3 = 3..3;
  T4 = 4..4;
  T5 = 5..5;
  T6 = 6..6;
  T7 = 7..7;
  T8 = 8..8;
  T9 = 9..9;
  TA = 10..10;
  TB = 11..11;
  TC = 12..12;
  TD = 13..13;
  TE = 14..14;
  TF = 15..15;
  T10 = 16..16;
  T11 = 17..17;
  T12 = 18..18;
  T13 = 19..19;
  T14 = 20..20;
  T15 = 21..21;
  T16 = 22..22;
  T17 = 23..23;
  T18 = 24..24;
  T19 = 25..25;
  T1A = 26..26;
  T1B = 27..27;
  T1C = 28..28;
  T1D = 29..29;
  T1E = 30..30;
  T1F = 31..31;
  T20 = 32..32;
  T21 = 33..33;
  T22 = 34..34;
  T23 = 35..35;
  T24 = 36..36;
  T25 = 37..37;
  T26 = 38..38;
  T27 = 39..39;
  T28 = 40..40;
  T29 = 41..41;
  T2A = 42..42;
  T2B = 43..43;
  T2C = 44..44;
  T2D = 45..45;
  T2E = 46..46;
  T2F = 47..47;
  T30 = 48..48;
  T31 = 49..49;
  T32 = 50..50;
  T33 = 51..51;
  T34 = 52..52;
  T35 = 53..53;
  T36 = 54..54;
  T37 = 55..55;
  T38 = 56..56;
  T39 = 57..57;
  T3A = 58..58;
  T3B = 59..59;
  T3C = 60..60;
  T3D = 61..61;
  T3E = 62..62;
  T3F = 63..63;
  T40 = 64..64;
  T41 = 65..65;
  T42 = 66..66;
  T43 = 67..67;
  T44 = 68..68;
  T45 = 69..69;
  T46 = 70..70;
  T47 = 71..71;
  T48 = 72..72;
  T49 = 73..73;
  T4A = 74..74;
  T4B = 75..75;
  T4C = 76..76;
  T4D = 77..77;
  T4E = 78..78;
  T4F = 79..79;
  T50 = 80..80;
  T51 = 81..81;
  T52 = 82..82;
  T53 = 83..83;
  T54 = 84..84;
  T55 = 85..85;
  T56 = 86..86;
  T57 = 87..87;
  T58 = 88..88;
  T59 = 89..89;
  T5A = 90..90;
  T5B = 91..91;
  T5C = 92..92;
  T5D = 93..93;
  T5E = 94..94;
  T5F = 95..95;
  T60 = 96..96;
  T61 = 97..97;
  T62 = 98..98;
  T63 = 99..99;
  T64 = 100..100;
  T65 = 101..101;
  T66 = 102..102;
  T67 = 103..103;
  T68 = 104..104;
  T69 = 105..105;
  T6A = 106..106;
  T6B = 107..107;
  T6C = 108..108;
  T6D = 109..109;
  T6E = 110..110;
  T6F = 111..111;
  T70 = 112..112;
  T71 = 113..113;
  T72 = 114..114;
  T73 = 115..115;
  T74 = 116..116;
  T75 = 117..117;
  T76 = 118..118;
  T77 = 119..119;
  T78 = 120..120;
  T79 = 121..121;
  T7A = 122..122;
  T7B = 123..123;
  T7C = 124..124;
  T7D = 125..125;
  T7E = 126..126;
  T7F = 127..127;
  T80 = 128..128;
  T81 = 129..129;
  T82 = 130..130;
  T83 = 131..131;
  T84 = 132..132;
  T85 = 133..133;
  T86 = 134..134;
  T87 = 135..135;
  T88 = 136..136;
  T89 = 137..137;
  T8A = 138..138;
  T8B = 139..139;
  T8C = 140..140;
  T8D = 141..141;
  T8E = 142..142;
  T8F = 143..143;
  T90 = 144..144;
  T91 = 145..145;
  T92 = 146..146;
  T93 = 147..147;
  T94 = 148..148;
  T95 = 149..149;
  T96 = 150..150;
  T97 = 151..151;
  T98 = 152..152;
  T99 = 153..153;
  T9A = 154..154;
  T9B = 155..155;
  T9C = 156..156;
  T9D = 157..157;
  T9E = 158..158;
  T9F = 159..159;
  TA0 = 160..160;
  TA1 = 161..161;
  TA2 = 162..162;
  TA3 = 163..163;
  TA4 = 164..164;
  TA5 = 165..165;
  TA6 = 166..166;
  TA7 = 167..167;
  TA8 = 168..168;
  TA9 = 169..169;
  TAA = 170..170;
  TAB = 171..171;
  TAC = 172..172;
  TAD = 173..173;
  TAE = 174..174;
  TAF = 175..175;
  TB0 = 176..176;
  TB1 = 177..177;
  TB2 = 178..178;
  TB3 = 179..179;
  TB4 = 180..180;
  TB5 = 181..181;
  TB6 = 182..182;
  TB7 = 183..183;
  TB8 = 184..184;
  TB9 = 185..185;
  TBA = 186..186;
  TBB = 187..187;
  TBC = 188..188;
  TBD = 189..189;
  TBE = 190..190;
  TBF = 191..191;
  TC0 = 192..192;
  TC1 = 193..193;
  TC2 = 194..194;
  TC3 = 195..195;
  TC4 = 196..196;
  TC5 = 197..197;
  TC6 = 198..198;
  TC7 = 199..199;
  TC8 = 200..200;
  TC9 = 201..201;
  TCA = 202..202;
  TCB = 203..203;
  TCC = 204..204;
  TCD = 205..205;
  TCE = 206..206;
  TCF = 207..207;
  TD0 = 208..208;
  TD1 = 209..209;
  TD2 = 210..210;
  TD3 = 211..211;
  TD4 = 212..212;
  TD5 = 213..213;
  TD6 = 214..214;
  TD7 = 215..215;
  TD8 = 216..216;
  TD9 = 217..217;
  TDA = 218..218;
  TDB = 219..219;
  TDC = 220..220;
  TDD = 221..221;
  TDE = 222..222;
  TDF = 223..223;
  TE0 = 224..224;
  TE1 = 225..225;
  TE2 = 226..226;
  TE3 = 227..227;
  TE4 = 228..228;
  TE5 = 229..229;
  TE6 = 230..230;
  TE7 = 231..231;
  TE8 = 232..232;
  TE9 = 233..233;
  TEA = 234..234;
  TEB = 235..235;
  TEC = 236..236;
  TED = 237..237;
  TEE = 238..238;
  TEF = 239..239;
  TF0 = 240..240;
  TF1 = 241..241;
  TF2 = 242..242;
  TF3 = 243..243;
  TF4 = 244..244;
  TF5 = 245..245;
  TF6 = 246..246;
  TF7 = 247..247;
  TF8 = 248..248;
  TF9 = 249..249;
  TFA = 250..250;
  TFB = 251..251;
  TFC = 252..252;
  TFD = 253..253;
  TFE = 254..254;
  TFF = 255..255;
{$ENDREGION}
{$IFEND NeedsIndexTypes}

const
{$IF TLeakCheck.EnableFreedObjectDetection}
  // RTTI-like ShortString
  SFreedObjectImpl: array[0..16] of Byte = (16, Ord('T'), Ord('F'), Ord('r'),
    Ord('e'), Ord('e'), Ord('d'), Ord('O'), Ord('b'), Ord('j'), Ord('e'),
    Ord('c'), Ord('t'), Ord('I'), Ord('m'), Ord('p'), Ord('l'));
{$IFEND}
  sLineBreak: MarshaledAString = {$IFDEF POSIX} #10 {$ENDIF}
       {$IFDEF MSWINDOWS} #13#10 {$ENDIF};
  SizeMemRecord = SizeOf(TLeakCheck.TMemRecord);
  SizeFooter = TLeakCheck.FooterSize * SizeOf(Pointer);

{$ENDREGION}

{$REGION 'Global vars'}

var
  First: TLeakCheck.PMemRecord = nil;
  Last: TLeakCheck.PMemRecord = nil;
  AllocationCount: NativeUInt = 0;
  AllocatedBytes: NativeUInt = 0;
  GBuff: array[0..31] of Byte;
  LeakStr: MarshaledAString = nil;
{$IF Defined(MSWINDOWS) AND TLeakCheck.UseInternalHeap}
  /// <summary>
  ///   Internal heap used by reporting functions that separate internal buffer
  ///   from other process memory to make sure leak (or other) reporting won't
  ///   interfere with freed process blocks.
  /// </summary>
  InternalHeap: THandle;
{$IFEND}
  CS: TCritSec;
  IgnoreCnt: NativeUInt = 0;
{$IF TLeakCheck.EnableFreedObjectDetection}
  FakeVMT: TClassData = (
    //SelfPtr: TClass(PByte(@FakeVMT) - vmtSelfPtr);
    //Parent: @TLeakCheck.TFreedObject;
    ClassName: @SFreedObjectImpl;
    InstanceSize: -1;
{$REGION 'Initializer'}
{$IF TLeakCheck.EnableVirtualCallsOnFreedObjectInterception}
    VirtualMethods: (
      TInvalidVirtualCall<T0>.Indexed,
      TInvalidVirtualCall<T1>.Indexed,
      TInvalidVirtualCall<T2>.Indexed,
      TInvalidVirtualCall<T3>.Indexed,
      TInvalidVirtualCall<T4>.Indexed,
      TInvalidVirtualCall<T5>.Indexed,
      TInvalidVirtualCall<T6>.Indexed,
      TInvalidVirtualCall<T7>.Indexed,
      TInvalidVirtualCall<T8>.Indexed,
      TInvalidVirtualCall<T9>.Indexed,
      TInvalidVirtualCall<TA>.Indexed,
      TInvalidVirtualCall<TB>.Indexed,
      TInvalidVirtualCall<TC>.Indexed,
      TInvalidVirtualCall<TD>.Indexed,
      TInvalidVirtualCall<TE>.Indexed,
      TInvalidVirtualCall<TF>.Indexed,
      TInvalidVirtualCall<T10>.Indexed,
      TInvalidVirtualCall<T11>.Indexed,
      TInvalidVirtualCall<T12>.Indexed,
      TInvalidVirtualCall<T13>.Indexed,
      TInvalidVirtualCall<T14>.Indexed,
      TInvalidVirtualCall<T15>.Indexed,
      TInvalidVirtualCall<T16>.Indexed,
      TInvalidVirtualCall<T17>.Indexed,
      TInvalidVirtualCall<T18>.Indexed,
      TInvalidVirtualCall<T19>.Indexed,
      TInvalidVirtualCall<T1A>.Indexed,
      TInvalidVirtualCall<T1B>.Indexed,
      TInvalidVirtualCall<T1C>.Indexed,
      TInvalidVirtualCall<T1D>.Indexed,
      TInvalidVirtualCall<T1E>.Indexed,
      TInvalidVirtualCall<T1F>.Indexed,
      TInvalidVirtualCall<T20>.Indexed,
      TInvalidVirtualCall<T21>.Indexed,
      TInvalidVirtualCall<T22>.Indexed,
      TInvalidVirtualCall<T23>.Indexed,
      TInvalidVirtualCall<T24>.Indexed,
      TInvalidVirtualCall<T25>.Indexed,
      TInvalidVirtualCall<T26>.Indexed,
      TInvalidVirtualCall<T27>.Indexed,
      TInvalidVirtualCall<T28>.Indexed,
      TInvalidVirtualCall<T29>.Indexed,
      TInvalidVirtualCall<T2A>.Indexed,
      TInvalidVirtualCall<T2B>.Indexed,
      TInvalidVirtualCall<T2C>.Indexed,
      TInvalidVirtualCall<T2D>.Indexed,
      TInvalidVirtualCall<T2E>.Indexed,
      TInvalidVirtualCall<T2F>.Indexed,
      TInvalidVirtualCall<T30>.Indexed,
      TInvalidVirtualCall<T31>.Indexed,
      TInvalidVirtualCall<T32>.Indexed,
      TInvalidVirtualCall<T33>.Indexed,
      TInvalidVirtualCall<T34>.Indexed,
      TInvalidVirtualCall<T35>.Indexed,
      TInvalidVirtualCall<T36>.Indexed,
      TInvalidVirtualCall<T37>.Indexed,
      TInvalidVirtualCall<T38>.Indexed,
      TInvalidVirtualCall<T39>.Indexed,
      TInvalidVirtualCall<T3A>.Indexed,
      TInvalidVirtualCall<T3B>.Indexed,
      TInvalidVirtualCall<T3C>.Indexed,
      TInvalidVirtualCall<T3D>.Indexed,
      TInvalidVirtualCall<T3E>.Indexed,
      TInvalidVirtualCall<T3F>.Indexed,
      TInvalidVirtualCall<T40>.Indexed,
      TInvalidVirtualCall<T41>.Indexed,
      TInvalidVirtualCall<T42>.Indexed,
      TInvalidVirtualCall<T43>.Indexed,
      TInvalidVirtualCall<T44>.Indexed,
      TInvalidVirtualCall<T45>.Indexed,
      TInvalidVirtualCall<T46>.Indexed,
      TInvalidVirtualCall<T47>.Indexed,
      TInvalidVirtualCall<T48>.Indexed,
      TInvalidVirtualCall<T49>.Indexed,
      TInvalidVirtualCall<T4A>.Indexed,
      TInvalidVirtualCall<T4B>.Indexed,
      TInvalidVirtualCall<T4C>.Indexed,
      TInvalidVirtualCall<T4D>.Indexed,
      TInvalidVirtualCall<T4E>.Indexed,
      TInvalidVirtualCall<T4F>.Indexed,
      TInvalidVirtualCall<T50>.Indexed,
      TInvalidVirtualCall<T51>.Indexed,
      TInvalidVirtualCall<T52>.Indexed,
      TInvalidVirtualCall<T53>.Indexed,
      TInvalidVirtualCall<T54>.Indexed,
      TInvalidVirtualCall<T55>.Indexed,
      TInvalidVirtualCall<T56>.Indexed,
      TInvalidVirtualCall<T57>.Indexed,
      TInvalidVirtualCall<T58>.Indexed,
      TInvalidVirtualCall<T59>.Indexed,
      TInvalidVirtualCall<T5A>.Indexed,
      TInvalidVirtualCall<T5B>.Indexed,
      TInvalidVirtualCall<T5C>.Indexed,
      TInvalidVirtualCall<T5D>.Indexed,
      TInvalidVirtualCall<T5E>.Indexed,
      TInvalidVirtualCall<T5F>.Indexed,
      TInvalidVirtualCall<T60>.Indexed,
      TInvalidVirtualCall<T61>.Indexed,
      TInvalidVirtualCall<T62>.Indexed,
      TInvalidVirtualCall<T63>.Indexed,
      TInvalidVirtualCall<T64>.Indexed,
      TInvalidVirtualCall<T65>.Indexed,
      TInvalidVirtualCall<T66>.Indexed,
      TInvalidVirtualCall<T67>.Indexed,
      TInvalidVirtualCall<T68>.Indexed,
      TInvalidVirtualCall<T69>.Indexed,
      TInvalidVirtualCall<T6A>.Indexed,
      TInvalidVirtualCall<T6B>.Indexed,
      TInvalidVirtualCall<T6C>.Indexed,
      TInvalidVirtualCall<T6D>.Indexed,
      TInvalidVirtualCall<T6E>.Indexed,
      TInvalidVirtualCall<T6F>.Indexed,
      TInvalidVirtualCall<T70>.Indexed,
      TInvalidVirtualCall<T71>.Indexed,
      TInvalidVirtualCall<T72>.Indexed,
      TInvalidVirtualCall<T73>.Indexed,
      TInvalidVirtualCall<T74>.Indexed,
      TInvalidVirtualCall<T75>.Indexed,
      TInvalidVirtualCall<T76>.Indexed,
      TInvalidVirtualCall<T77>.Indexed,
      TInvalidVirtualCall<T78>.Indexed,
      TInvalidVirtualCall<T79>.Indexed,
      TInvalidVirtualCall<T7A>.Indexed,
      TInvalidVirtualCall<T7B>.Indexed,
      TInvalidVirtualCall<T7C>.Indexed,
      TInvalidVirtualCall<T7D>.Indexed,
      TInvalidVirtualCall<T7E>.Indexed,
      TInvalidVirtualCall<T7F>.Indexed,
      TInvalidVirtualCall<T80>.Indexed,
      TInvalidVirtualCall<T81>.Indexed,
      TInvalidVirtualCall<T82>.Indexed,
      TInvalidVirtualCall<T83>.Indexed,
      TInvalidVirtualCall<T84>.Indexed,
      TInvalidVirtualCall<T85>.Indexed,
      TInvalidVirtualCall<T86>.Indexed,
      TInvalidVirtualCall<T87>.Indexed,
      TInvalidVirtualCall<T88>.Indexed,
      TInvalidVirtualCall<T89>.Indexed,
      TInvalidVirtualCall<T8A>.Indexed,
      TInvalidVirtualCall<T8B>.Indexed,
      TInvalidVirtualCall<T8C>.Indexed,
      TInvalidVirtualCall<T8D>.Indexed,
      TInvalidVirtualCall<T8E>.Indexed,
      TInvalidVirtualCall<T8F>.Indexed,
      TInvalidVirtualCall<T90>.Indexed,
      TInvalidVirtualCall<T91>.Indexed,
      TInvalidVirtualCall<T92>.Indexed,
      TInvalidVirtualCall<T93>.Indexed,
      TInvalidVirtualCall<T94>.Indexed,
      TInvalidVirtualCall<T95>.Indexed,
      TInvalidVirtualCall<T96>.Indexed,
      TInvalidVirtualCall<T97>.Indexed,
      TInvalidVirtualCall<T98>.Indexed,
      TInvalidVirtualCall<T99>.Indexed,
      TInvalidVirtualCall<T9A>.Indexed,
      TInvalidVirtualCall<T9B>.Indexed,
      TInvalidVirtualCall<T9C>.Indexed,
      TInvalidVirtualCall<T9D>.Indexed,
      TInvalidVirtualCall<T9E>.Indexed,
      TInvalidVirtualCall<T9F>.Indexed,
      TInvalidVirtualCall<TA0>.Indexed,
      TInvalidVirtualCall<TA1>.Indexed,
      TInvalidVirtualCall<TA2>.Indexed,
      TInvalidVirtualCall<TA3>.Indexed,
      TInvalidVirtualCall<TA4>.Indexed,
      TInvalidVirtualCall<TA5>.Indexed,
      TInvalidVirtualCall<TA6>.Indexed,
      TInvalidVirtualCall<TA7>.Indexed,
      TInvalidVirtualCall<TA8>.Indexed,
      TInvalidVirtualCall<TA9>.Indexed,
      TInvalidVirtualCall<TAA>.Indexed,
      TInvalidVirtualCall<TAB>.Indexed,
      TInvalidVirtualCall<TAC>.Indexed,
      TInvalidVirtualCall<TAD>.Indexed,
      TInvalidVirtualCall<TAE>.Indexed,
      TInvalidVirtualCall<TAF>.Indexed,
      TInvalidVirtualCall<TB0>.Indexed,
      TInvalidVirtualCall<TB1>.Indexed,
      TInvalidVirtualCall<TB2>.Indexed,
      TInvalidVirtualCall<TB3>.Indexed,
      TInvalidVirtualCall<TB4>.Indexed,
      TInvalidVirtualCall<TB5>.Indexed,
      TInvalidVirtualCall<TB6>.Indexed,
      TInvalidVirtualCall<TB7>.Indexed,
      TInvalidVirtualCall<TB8>.Indexed,
      TInvalidVirtualCall<TB9>.Indexed,
      TInvalidVirtualCall<TBA>.Indexed,
      TInvalidVirtualCall<TBB>.Indexed,
      TInvalidVirtualCall<TBC>.Indexed,
      TInvalidVirtualCall<TBD>.Indexed,
      TInvalidVirtualCall<TBE>.Indexed,
      TInvalidVirtualCall<TBF>.Indexed,
      TInvalidVirtualCall<TC0>.Indexed,
      TInvalidVirtualCall<TC1>.Indexed,
      TInvalidVirtualCall<TC2>.Indexed,
      TInvalidVirtualCall<TC3>.Indexed,
      TInvalidVirtualCall<TC4>.Indexed,
      TInvalidVirtualCall<TC5>.Indexed,
      TInvalidVirtualCall<TC6>.Indexed,
      TInvalidVirtualCall<TC7>.Indexed,
      TInvalidVirtualCall<TC8>.Indexed,
      TInvalidVirtualCall<TC9>.Indexed,
      TInvalidVirtualCall<TCA>.Indexed,
      TInvalidVirtualCall<TCB>.Indexed,
      TInvalidVirtualCall<TCC>.Indexed,
      TInvalidVirtualCall<TCD>.Indexed,
      TInvalidVirtualCall<TCE>.Indexed,
      TInvalidVirtualCall<TCF>.Indexed,
      TInvalidVirtualCall<TD0>.Indexed,
      TInvalidVirtualCall<TD1>.Indexed,
      TInvalidVirtualCall<TD2>.Indexed,
      TInvalidVirtualCall<TD3>.Indexed,
      TInvalidVirtualCall<TD4>.Indexed,
      TInvalidVirtualCall<TD5>.Indexed,
      TInvalidVirtualCall<TD6>.Indexed,
      TInvalidVirtualCall<TD7>.Indexed,
      TInvalidVirtualCall<TD8>.Indexed,
      TInvalidVirtualCall<TD9>.Indexed,
      TInvalidVirtualCall<TDA>.Indexed,
      TInvalidVirtualCall<TDB>.Indexed,
      TInvalidVirtualCall<TDC>.Indexed,
      TInvalidVirtualCall<TDD>.Indexed,
      TInvalidVirtualCall<TDE>.Indexed,
      TInvalidVirtualCall<TDF>.Indexed,
      TInvalidVirtualCall<TE0>.Indexed,
      TInvalidVirtualCall<TE1>.Indexed,
      TInvalidVirtualCall<TE2>.Indexed,
      TInvalidVirtualCall<TE3>.Indexed,
      TInvalidVirtualCall<TE4>.Indexed,
      TInvalidVirtualCall<TE5>.Indexed,
      TInvalidVirtualCall<TE6>.Indexed,
      TInvalidVirtualCall<TE7>.Indexed,
      TInvalidVirtualCall<TE8>.Indexed,
      TInvalidVirtualCall<TE9>.Indexed,
      TInvalidVirtualCall<TEA>.Indexed,
      TInvalidVirtualCall<TEB>.Indexed,
      TInvalidVirtualCall<TEC>.Indexed,
      TInvalidVirtualCall<TED>.Indexed,
      TInvalidVirtualCall<TEE>.Indexed,
      TInvalidVirtualCall<TEF>.Indexed,
      TInvalidVirtualCall<TF0>.Indexed,
      TInvalidVirtualCall<TF1>.Indexed,
      TInvalidVirtualCall<TF2>.Indexed,
      TInvalidVirtualCall<TF3>.Indexed,
      TInvalidVirtualCall<TF4>.Indexed,
      TInvalidVirtualCall<TF5>.Indexed,
      TInvalidVirtualCall<TF6>.Indexed,
      TInvalidVirtualCall<TF7>.Indexed,
      TInvalidVirtualCall<TF8>.Indexed,
      TInvalidVirtualCall<TF9>.Indexed,
      TInvalidVirtualCall<TFA>.Indexed,
      TInvalidVirtualCall<TFB>.Indexed,
      TInvalidVirtualCall<TFC>.Indexed,
      TInvalidVirtualCall<TFD>.Indexed,
      TInvalidVirtualCall<TFE>.Indexed,
      TInvalidVirtualCall<TFF>.Indexed
    );
{$IFEND EnableVirtualCallsOnFreedObjectInterception}
{$ENDREGION}
  );
{$REGION 'IntfFakeVTable'}
{$IF TLeakCheck.EnableInterfaceCallsOnFreedObjectInterception}
  IntfFakeVTable: TIntfVTable = (
    QueryInterface: TInvalidInterfaceCall<T0>.IndexedStd;
    AddRef: TInvalidInterfaceCall<T1>.IndexedStd;
    Release: TInvalidInterfaceCall<T2>.IndexedStd;
    Methods: (
      TInvalidInterfaceCall<T3>.Indexed,
      TInvalidInterfaceCall<T4>.Indexed,
      TInvalidInterfaceCall<T5>.Indexed,
      TInvalidInterfaceCall<T6>.Indexed,
      TInvalidInterfaceCall<T7>.Indexed,
      TInvalidInterfaceCall<T8>.Indexed,
      TInvalidInterfaceCall<T9>.Indexed,
      TInvalidInterfaceCall<TA>.Indexed,
      TInvalidInterfaceCall<TB>.Indexed,
      TInvalidInterfaceCall<TC>.Indexed,
      TInvalidInterfaceCall<TD>.Indexed,
      TInvalidInterfaceCall<TE>.Indexed,
      TInvalidInterfaceCall<TF>.Indexed,
      TInvalidInterfaceCall<T10>.Indexed,
      TInvalidInterfaceCall<T11>.Indexed,
      TInvalidInterfaceCall<T12>.Indexed,
      TInvalidInterfaceCall<T13>.Indexed,
      TInvalidInterfaceCall<T14>.Indexed,
      TInvalidInterfaceCall<T15>.Indexed,
      TInvalidInterfaceCall<T16>.Indexed,
      TInvalidInterfaceCall<T17>.Indexed,
      TInvalidInterfaceCall<T18>.Indexed,
      TInvalidInterfaceCall<T19>.Indexed,
      TInvalidInterfaceCall<T1A>.Indexed,
      TInvalidInterfaceCall<T1B>.Indexed,
      TInvalidInterfaceCall<T1C>.Indexed,
      TInvalidInterfaceCall<T1D>.Indexed,
      TInvalidInterfaceCall<T1E>.Indexed,
      TInvalidInterfaceCall<T1F>.Indexed,
      TInvalidInterfaceCall<T20>.Indexed,
      TInvalidInterfaceCall<T21>.Indexed,
      TInvalidInterfaceCall<T22>.Indexed,
      TInvalidInterfaceCall<T23>.Indexed,
      TInvalidInterfaceCall<T24>.Indexed,
      TInvalidInterfaceCall<T25>.Indexed,
      TInvalidInterfaceCall<T26>.Indexed,
      TInvalidInterfaceCall<T27>.Indexed,
      TInvalidInterfaceCall<T28>.Indexed,
      TInvalidInterfaceCall<T29>.Indexed,
      TInvalidInterfaceCall<T2A>.Indexed,
      TInvalidInterfaceCall<T2B>.Indexed,
      TInvalidInterfaceCall<T2C>.Indexed,
      TInvalidInterfaceCall<T2D>.Indexed,
      TInvalidInterfaceCall<T2E>.Indexed,
      TInvalidInterfaceCall<T2F>.Indexed,
      TInvalidInterfaceCall<T30>.Indexed,
      TInvalidInterfaceCall<T31>.Indexed,
      TInvalidInterfaceCall<T32>.Indexed,
      TInvalidInterfaceCall<T33>.Indexed,
      TInvalidInterfaceCall<T34>.Indexed,
      TInvalidInterfaceCall<T35>.Indexed,
      TInvalidInterfaceCall<T36>.Indexed,
      TInvalidInterfaceCall<T37>.Indexed,
      TInvalidInterfaceCall<T38>.Indexed,
      TInvalidInterfaceCall<T39>.Indexed,
      TInvalidInterfaceCall<T3A>.Indexed,
      TInvalidInterfaceCall<T3B>.Indexed,
      TInvalidInterfaceCall<T3C>.Indexed,
      TInvalidInterfaceCall<T3D>.Indexed,
      TInvalidInterfaceCall<T3E>.Indexed,
      TInvalidInterfaceCall<T3F>.Indexed,
      TInvalidInterfaceCall<T40>.Indexed,
      TInvalidInterfaceCall<T41>.Indexed,
      TInvalidInterfaceCall<T42>.Indexed,
      TInvalidInterfaceCall<T43>.Indexed,
      TInvalidInterfaceCall<T44>.Indexed,
      TInvalidInterfaceCall<T45>.Indexed,
      TInvalidInterfaceCall<T46>.Indexed,
      TInvalidInterfaceCall<T47>.Indexed,
      TInvalidInterfaceCall<T48>.Indexed,
      TInvalidInterfaceCall<T49>.Indexed,
      TInvalidInterfaceCall<T4A>.Indexed,
      TInvalidInterfaceCall<T4B>.Indexed,
      TInvalidInterfaceCall<T4C>.Indexed,
      TInvalidInterfaceCall<T4D>.Indexed,
      TInvalidInterfaceCall<T4E>.Indexed,
      TInvalidInterfaceCall<T4F>.Indexed,
      TInvalidInterfaceCall<T50>.Indexed,
      TInvalidInterfaceCall<T51>.Indexed,
      TInvalidInterfaceCall<T52>.Indexed,
      TInvalidInterfaceCall<T53>.Indexed,
      TInvalidInterfaceCall<T54>.Indexed,
      TInvalidInterfaceCall<T55>.Indexed,
      TInvalidInterfaceCall<T56>.Indexed,
      TInvalidInterfaceCall<T57>.Indexed,
      TInvalidInterfaceCall<T58>.Indexed,
      TInvalidInterfaceCall<T59>.Indexed,
      TInvalidInterfaceCall<T5A>.Indexed,
      TInvalidInterfaceCall<T5B>.Indexed,
      TInvalidInterfaceCall<T5C>.Indexed,
      TInvalidInterfaceCall<T5D>.Indexed,
      TInvalidInterfaceCall<T5E>.Indexed,
      TInvalidInterfaceCall<T5F>.Indexed,
      TInvalidInterfaceCall<T60>.Indexed,
      TInvalidInterfaceCall<T61>.Indexed,
      TInvalidInterfaceCall<T62>.Indexed,
      TInvalidInterfaceCall<T63>.Indexed,
      TInvalidInterfaceCall<T64>.Indexed,
      TInvalidInterfaceCall<T65>.Indexed,
      TInvalidInterfaceCall<T66>.Indexed,
      TInvalidInterfaceCall<T67>.Indexed,
      TInvalidInterfaceCall<T68>.Indexed,
      TInvalidInterfaceCall<T69>.Indexed,
      TInvalidInterfaceCall<T6A>.Indexed,
      TInvalidInterfaceCall<T6B>.Indexed,
      TInvalidInterfaceCall<T6C>.Indexed,
      TInvalidInterfaceCall<T6D>.Indexed,
      TInvalidInterfaceCall<T6E>.Indexed,
      TInvalidInterfaceCall<T6F>.Indexed,
      TInvalidInterfaceCall<T70>.Indexed,
      TInvalidInterfaceCall<T71>.Indexed,
      TInvalidInterfaceCall<T72>.Indexed,
      TInvalidInterfaceCall<T73>.Indexed,
      TInvalidInterfaceCall<T74>.Indexed,
      TInvalidInterfaceCall<T75>.Indexed,
      TInvalidInterfaceCall<T76>.Indexed,
      TInvalidInterfaceCall<T77>.Indexed,
      TInvalidInterfaceCall<T78>.Indexed,
      TInvalidInterfaceCall<T79>.Indexed,
      TInvalidInterfaceCall<T7A>.Indexed,
      TInvalidInterfaceCall<T7B>.Indexed,
      TInvalidInterfaceCall<T7C>.Indexed,
      TInvalidInterfaceCall<T7D>.Indexed,
      TInvalidInterfaceCall<T7E>.Indexed,
      TInvalidInterfaceCall<T7F>.Indexed,
      TInvalidInterfaceCall<T80>.Indexed,
      TInvalidInterfaceCall<T81>.Indexed,
      TInvalidInterfaceCall<T82>.Indexed,
      TInvalidInterfaceCall<T83>.Indexed,
      TInvalidInterfaceCall<T84>.Indexed,
      TInvalidInterfaceCall<T85>.Indexed,
      TInvalidInterfaceCall<T86>.Indexed,
      TInvalidInterfaceCall<T87>.Indexed,
      TInvalidInterfaceCall<T88>.Indexed,
      TInvalidInterfaceCall<T89>.Indexed,
      TInvalidInterfaceCall<T8A>.Indexed,
      TInvalidInterfaceCall<T8B>.Indexed,
      TInvalidInterfaceCall<T8C>.Indexed,
      TInvalidInterfaceCall<T8D>.Indexed,
      TInvalidInterfaceCall<T8E>.Indexed,
      TInvalidInterfaceCall<T8F>.Indexed,
      TInvalidInterfaceCall<T90>.Indexed,
      TInvalidInterfaceCall<T91>.Indexed,
      TInvalidInterfaceCall<T92>.Indexed,
      TInvalidInterfaceCall<T93>.Indexed,
      TInvalidInterfaceCall<T94>.Indexed,
      TInvalidInterfaceCall<T95>.Indexed,
      TInvalidInterfaceCall<T96>.Indexed,
      TInvalidInterfaceCall<T97>.Indexed,
      TInvalidInterfaceCall<T98>.Indexed,
      TInvalidInterfaceCall<T99>.Indexed,
      TInvalidInterfaceCall<T9A>.Indexed,
      TInvalidInterfaceCall<T9B>.Indexed,
      TInvalidInterfaceCall<T9C>.Indexed,
      TInvalidInterfaceCall<T9D>.Indexed,
      TInvalidInterfaceCall<T9E>.Indexed,
      TInvalidInterfaceCall<T9F>.Indexed,
      TInvalidInterfaceCall<TA0>.Indexed,
      TInvalidInterfaceCall<TA1>.Indexed,
      TInvalidInterfaceCall<TA2>.Indexed,
      TInvalidInterfaceCall<TA3>.Indexed,
      TInvalidInterfaceCall<TA4>.Indexed,
      TInvalidInterfaceCall<TA5>.Indexed,
      TInvalidInterfaceCall<TA6>.Indexed,
      TInvalidInterfaceCall<TA7>.Indexed,
      TInvalidInterfaceCall<TA8>.Indexed,
      TInvalidInterfaceCall<TA9>.Indexed,
      TInvalidInterfaceCall<TAA>.Indexed,
      TInvalidInterfaceCall<TAB>.Indexed,
      TInvalidInterfaceCall<TAC>.Indexed,
      TInvalidInterfaceCall<TAD>.Indexed,
      TInvalidInterfaceCall<TAE>.Indexed,
      TInvalidInterfaceCall<TAF>.Indexed,
      TInvalidInterfaceCall<TB0>.Indexed,
      TInvalidInterfaceCall<TB1>.Indexed,
      TInvalidInterfaceCall<TB2>.Indexed,
      TInvalidInterfaceCall<TB3>.Indexed,
      TInvalidInterfaceCall<TB4>.Indexed,
      TInvalidInterfaceCall<TB5>.Indexed,
      TInvalidInterfaceCall<TB6>.Indexed,
      TInvalidInterfaceCall<TB7>.Indexed,
      TInvalidInterfaceCall<TB8>.Indexed,
      TInvalidInterfaceCall<TB9>.Indexed,
      TInvalidInterfaceCall<TBA>.Indexed,
      TInvalidInterfaceCall<TBB>.Indexed,
      TInvalidInterfaceCall<TBC>.Indexed,
      TInvalidInterfaceCall<TBD>.Indexed,
      TInvalidInterfaceCall<TBE>.Indexed,
      TInvalidInterfaceCall<TBF>.Indexed,
      TInvalidInterfaceCall<TC0>.Indexed,
      TInvalidInterfaceCall<TC1>.Indexed,
      TInvalidInterfaceCall<TC2>.Indexed,
      TInvalidInterfaceCall<TC3>.Indexed,
      TInvalidInterfaceCall<TC4>.Indexed,
      TInvalidInterfaceCall<TC5>.Indexed,
      TInvalidInterfaceCall<TC6>.Indexed,
      TInvalidInterfaceCall<TC7>.Indexed,
      TInvalidInterfaceCall<TC8>.Indexed,
      TInvalidInterfaceCall<TC9>.Indexed,
      TInvalidInterfaceCall<TCA>.Indexed,
      TInvalidInterfaceCall<TCB>.Indexed,
      TInvalidInterfaceCall<TCC>.Indexed,
      TInvalidInterfaceCall<TCD>.Indexed,
      TInvalidInterfaceCall<TCE>.Indexed,
      TInvalidInterfaceCall<TCF>.Indexed,
      TInvalidInterfaceCall<TD0>.Indexed,
      TInvalidInterfaceCall<TD1>.Indexed,
      TInvalidInterfaceCall<TD2>.Indexed,
      TInvalidInterfaceCall<TD3>.Indexed,
      TInvalidInterfaceCall<TD4>.Indexed,
      TInvalidInterfaceCall<TD5>.Indexed,
      TInvalidInterfaceCall<TD6>.Indexed,
      TInvalidInterfaceCall<TD7>.Indexed,
      TInvalidInterfaceCall<TD8>.Indexed,
      TInvalidInterfaceCall<TD9>.Indexed,
      TInvalidInterfaceCall<TDA>.Indexed,
      TInvalidInterfaceCall<TDB>.Indexed,
      TInvalidInterfaceCall<TDC>.Indexed,
      TInvalidInterfaceCall<TDD>.Indexed,
      TInvalidInterfaceCall<TDE>.Indexed,
      TInvalidInterfaceCall<TDF>.Indexed,
      TInvalidInterfaceCall<TE0>.Indexed,
      TInvalidInterfaceCall<TE1>.Indexed,
      TInvalidInterfaceCall<TE2>.Indexed,
      TInvalidInterfaceCall<TE3>.Indexed,
      TInvalidInterfaceCall<TE4>.Indexed,
      TInvalidInterfaceCall<TE5>.Indexed,
      TInvalidInterfaceCall<TE6>.Indexed,
      TInvalidInterfaceCall<TE7>.Indexed,
      TInvalidInterfaceCall<TE8>.Indexed,
      TInvalidInterfaceCall<TE9>.Indexed,
      TInvalidInterfaceCall<TEA>.Indexed,
      TInvalidInterfaceCall<TEB>.Indexed,
      TInvalidInterfaceCall<TEC>.Indexed,
      TInvalidInterfaceCall<TED>.Indexed,
      TInvalidInterfaceCall<TEE>.Indexed,
      TInvalidInterfaceCall<TEF>.Indexed,
      TInvalidInterfaceCall<TF0>.Indexed,
      TInvalidInterfaceCall<TF1>.Indexed,
      TInvalidInterfaceCall<TF2>.Indexed,
      TInvalidInterfaceCall<TF3>.Indexed,
      TInvalidInterfaceCall<TF4>.Indexed,
      TInvalidInterfaceCall<TF5>.Indexed,
      TInvalidInterfaceCall<TF6>.Indexed,
      TInvalidInterfaceCall<TF7>.Indexed,
      TInvalidInterfaceCall<TF8>.Indexed,
      TInvalidInterfaceCall<TF9>.Indexed,
      TInvalidInterfaceCall<TFA>.Indexed,
      TInvalidInterfaceCall<TFB>.Indexed,
      TInvalidInterfaceCall<TFC>.Indexed,
      TInvalidInterfaceCall<TFD>.Indexed,
      TInvalidInterfaceCall<TFE>.Indexed,
      TInvalidInterfaceCall<TFF>.Indexed
    );
  );
{$IFEND EnableVirtualCallsOnFreedObjectInterception}
{$ENDREGION}
{$IFEND EnableFreedObjectDetection}

{$ENDREGION}

function IsValidVMTAddress(APAddress: Pointer;
  var AMemInfo: TMemoryBasicInformation): Boolean; forward;
function IsValidClass(AClassType: TClass): Boolean; forward;
function GetObjectClass(Rec: TLeakCheck.PMemRecord; APointer: Pointer;
  SafePtr: Boolean = False): TClass; forward;
function IsString(Rec: TLeakCheck.PMemRecord; LDataPtr: Pointer): Boolean; forward;

{$IFNDEF HAS_ATOMICS}

function AtomicIncrement(var Value: NativeUInt; I: Integer = 1): Integer;
asm
      MOV   ECX,EAX
      MOV   EAX,EDX
 LOCK XADD  [ECX],EAX
      ADD   EAX,EDX
end;

function AtomicDecrement(var Value: NativeUInt; I: Integer = 1): Integer;
begin
  Result := AtomicIncrement(Value, -I);
end;

{$ENDIF}

{$IF TLeakCheck.EnableInterfaceVTablesFastFill}

procedure FillPointer(Destination: PPointer; Count: NativeUInt; Value: Pointer);
begin
  while Count > 0 do
  begin
    Destination^ := Value;
    Inc(Destination);
    Dec(Count);
  end;
end;

{$IFEND}

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

{$REGION 'Optional defer stubs'}

// If defined, do not use system memory manager directly but use previous one
// can be handy if FastMM and LeakCheck are running together.
{$IFDEF LEAKCHECK_DEFER}

function SysGetMem(Size: NativeInt): Pointer;
begin
  Result := TLeakCheck.FOldMemoryManager.GetMem(Size);
end;

function SysFreeMem(P: Pointer): Integer;
begin
  Result := TLeakCheck.FOldMemoryManager.FreeMem(P);
end;

function SysReallocMem(P: Pointer; Size: NativeInt): Pointer;
begin
  Result := TLeakCheck.FOldMemoryManager.ReallocMem(P, Size);
end;

function SysAllocMem(Size: NativeInt): Pointer;
begin
  Result := TLeakCheck.FOldMemoryManager.AllocMem(Size);
end;

{$ENDIF}

// Internal functions that use different memory manager (if possible) to ensure
// that memory reports do not modify freed memory of the default memory manager
// (ie. the one used by LeakCheck to allocate memory or system low-level memory
// manager) if possible (only on selected platforms). Also keep in mind that
// higher level functions like stack trace formatting also allocates memory via
// LeakCheck and thus the standard memory manager and may interfere with freed
// blocks.
function InternalGetMem(Size: NativeInt): Pointer;
begin
{$IF Defined(MSWINDOWS) AND TLeakCheck.UseInternalHeap}
  Result := HeapAlloc(InternalHeap, 0, Size);
{$ELSE}
  Result := System.SysGetMem(Size);
{$IFEND}
end;

function InternalFreeMem(P: Pointer): Integer;
begin
{$IF Defined(MSWINDOWS) AND TLeakCheck.UseInternalHeap}
  LongBool(Result) := HeapFree(InternalHeap, 0, P);
{$ELSE}
  Result := System.SysFreeMem(P);
{$IFEND}
end;

function InternalReallocMem(P: Pointer; Size: NativeInt): Pointer;
begin
{$IF Defined(MSWINDOWS) AND TLeakCheck.UseInternalHeap}
  Result := HeapReAlloc(InternalHeap, 0, P, Size);
{$ELSE}
  Result := System.SysReallocMem(P, Size);
{$IFEND}
end;

{$ENDREGION}

{$REGION 'TLeakCheck'}

class procedure TLeakCheck._AddRec(const P: PMemRecord; Size: NativeUInt);
begin
  Assert(Size > 0);
  if not Assigned(P) then
    System.Error(reOutOfMemory);
  // Store Size here before it gets corrupted.
  P^.CurrentSize := Size;
  CS.Enter;
  P^.MayLeak := IgnoreCnt = 0;
  if P^.MayLeak then
  begin
    AtomicIncrement(AllocationCount);
    // There are compiler issues with Atomic operations that break the Inrement
    // value if registers are used in a specific way (with optimization on).
    // In this specific case Size is stored in ESI that receives previous value
    // of AllocatedBytes that gets later incremented by EAX (initialized to ESI)
    // so ESI holds total allocation size rather then unchanged Size.
    // Size is broken beyond this point!
    AtomicIncrement(AllocatedBytes, Size);
  end;
  P^.Next := nil;
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

  FillChar(P^.Sep, SizeOf(P^.Sep), $FF);
{$IF MaxStackSize > 0}
  if Assigned(GetStackTraceProc) and P^.MayLeak then
  begin
    GetStackTrace(P^.StackAllocated);
  end
  else
  begin
    P^.StackAllocated.Count := 0;
  end;
{$IF RecordFreeStackTrace}
  P^.StackFreed.Count := 0;
{$IFEND}
{$IFEND}
{$IF FooterSize > 0}
  FillChar((PByte(P) + SizeMemRecord + P^.CurrentSize)^, FooterSize * SizeOf(Pointer), $FF);
{$IFEND}
end;

class procedure TLeakCheck._ReleaseRec(const P: PMemRecord);
begin
  CS.Enter;

{$IFDEF ANDROID}
  // {$DEFINE USE_LIBICU} - See System.pas
  // Try to fix a bug when System tries to release invalid record (this doesn't
  // work of there are leaks in the application).
  // Actually allocation count should be around 1 but leave some space here.
  if AllocationCount < 4 then
  begin
    if not IsValidRec(P) then
    begin
      CS.Leave;
      Exit;
    end;
  end;
{$ENDIF}

  // Memory marked as non-leaking is excluded from allocation info
  if P^.MayLeak then
  begin
    AtomicDecrement(AllocationCount);
    // Note that there are compiler issues with Atomic operations that do not
    // apply here.
    AtomicDecrement(AllocatedBytes, P^.CurrentSize);
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

  P^.CurrentSize := 0;
end;

class procedure TLeakCheck._SetLeaks(const P: PMemRecord; Value: LongBool);
begin
  if P^.CurrentSize = 0 then
    Exit;

  if P^.MayLeak <> Value then
  begin
    P^.MayLeak := Value;
    if Value then
    begin
      AtomicIncrement(AllocationCount);
      AtomicIncrement(AllocatedBytes, P^.CurrentSize);
    end
    else
    begin
      AtomicDecrement(AllocationCount);
      AtomicDecrement(AllocatedBytes, P^.CurrentSize);
    end;
  end;
end;

class function TLeakCheck.AllocMem(Size: NativeInt): Pointer;
begin
  Result := SysAllocMem(Size + SizeMemRecord + SizeFooter);
  _AddRec(Result, Size);
  InitMem(Result);
  Inc(NativeUInt(Result), SizeMemRecord);
end;

class procedure TLeakCheck.BeginIgnore;
begin
  AtomicIncrement(IgnoreCnt);
end;

class procedure TLeakCheck.CleanupStackTraceFormatter;
begin
{$IF MaxStackSize > 0}
  FStackTraceFormatter := nil;
{$IFEND}
  GetStackTraceFormatterProc := nil;
end;

class function TLeakCheck.CreateSnapshot: Pointer;
begin
  Result:=Last;
end;

class procedure TLeakCheck.EndIgnore;
begin
  AtomicDecrement(IgnoreCnt);
end;

class procedure TLeakCheck.Finalize;
begin
  if ReportMemoryLeaksOnShutdown then
    Report(nil, True);
{$IF MaxStackSize > 0}
  CleanupStackTraceFormatter;
{$IFEND}
  if Assigned(FinalizationProc) then
    FinalizationProc();
{$IFNDEF WEAKREF}
  CS.Free;
  Suspend;
{$ELSE}
{$IF Defined(MSWINDOWS) AND TLeakCheck.UseInternalHeap}
  HeapDestroy(InternalHeap);
  InternalHeap := 0;
{$IFEND}
  // RTL releases Weakmaps in System unit finalization that is executed later
  // it was allocated using this MemoryManager and must be released as such
  // it is then safer to leak the mutex rather then release the memory
  // improperly
  // This will cause SEGFAULT in System finalization but it still leaks less
  // memory. System should use SysGet/FreeMem internally.
  // _ReleaseRec should fix that in "most" cases.
{$ENDIF}
end;

class function TLeakCheck.FreeMem(P: Pointer): Integer;
{$IF TLeakCheck.EnableFreeCleanup}
  {$IF TLeakCheck.EnableInterfaceCallsOnFreedObjectInterception AND
    NOT TLeakCheck.EnableInterfaceVTablesFastFill}
  procedure FillIntfTable(Instance: PByte; ClassPtr: TClass);
  var
    IntfTable: PInterfaceTable;
    I: Integer;
  begin
    while ClassPtr <> nil do
    begin
      IntfTable := ClassPtr.GetInterfaceTable;
      if IntfTable <> nil then
        for I := 0 to IntfTable.EntryCount-1 do
          with IntfTable.Entries[I] do
          begin
            if VTable <> nil then
              PPointer(@Instance[IOffset])^ := @IntfFakeVTable;
          end;
      ClassPtr := ClassPtr.ClassParent;
    end;
  end;
  {$IFEND}

  procedure Cleanup(P: PByte; Rec: PMemRecord);
  {$IF FooterSize > 0}
  var
    F: PNativeInt;
    I: Integer;
  {$IFEND}
  begin
    {$IF FooterSize > 0}
      F:=PNativeInt(P + Rec^.PrevSize);
      for I := 1 to FooterSize do
      begin
        if F^ <> -1 then
          System.Error(reAccessViolation);
      end;
    {$IFEND}
    {$IF EnableFreedObjectDetection}
      // Assign fake VMT to all freed blocks so even if other type is used but
      // here are still dangling pointers that assume this memory was an object
      // virtual call interception will still work if the second allocation gets
      // deallocated before the dangling pointer gets used (the original VMT
      // is corrupted though).
      if Rec^.PrevSize >= NativeUInt(TObject.InstanceSize) then
      begin
        Rec^.PrevClass := PClass(P)^;
        {$IF TLeakCheck.EnableInterfaceCallsOnFreedObjectInterception}
          {$IF TLeakCheck.EnableInterfaceVTablesFastFill}
            if Rec.PrevSize < MaxClassSize then
              FillPointer(Pointer(P), Rec.PrevSize div SizeOf(Pointer), @IntfFakeVTable);
          {$ELSE}
            if Assigned(GetObjectClass(P, True)) then
              FillIntfTable(P, Rec^.PrevClass);
          {$IFEND}
        {$IFEND}
        PClass(P)^:=FakeVMT.SelfPtr;
      end;
    {$IFEND}
  end;
{$IFEND}
begin
  Dec(NativeUInt(P), SizeMemRecord);
  PMemRecord(P)^.PrevSize := PMemRecord(P)^.CurrentSize;
  _ReleaseRec(P);
{$IF EnableFreeCleanup}
  // Cleanup does not need to be synchronized since the memory is still marked
  // as allocated by the underlying (system) memory manager and is released
  // after cleanup has concluded. During cleanup the memory block marked as
  // free by the LeakCheck but it does not affect future allocations (
  // allocations made during cleanup).
  Cleanup(PByte(P) + SizeMemRecord, P);
{$IFEND}
{$IF (MaxStackSize > 0) AND RecordFreeStackTrace}
  if Assigned(GetStackTraceProc) then
  begin
    GetStackTrace(PMemRecord(P)^.StackFreed);
  end;
  // else no need to zero anything it is done implicitly during allocation
{$IFEND}

  Result := SysFreeMem(P);
end;

class procedure TLeakCheck.GetLeakInfo(var Info: TLeakInfo; Rec: PMemRecord);
var
  Data: Pointer;
begin
  // Scan for object first (string require more scanning and processing)
  Data := Rec^.Data;
  Info.ClassType := GetObjectClass(Data, True);
  if Assigned(Info.ClassType) then
    Info.StringInfo := nil
  else if LeakCheck.IsString(Rec, Data) then
    Info.StringInfo := Data
  else
    Info.StringInfo := nil;
end;

class function TLeakCheck.GetLeaks(Snapshot: Pointer = nil): TLeaks;
var
  P: PMemRecord;
  i: PPointer;
  c: Integer;
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

  Result.FLeaks := InternalGetMem(Result.FLength * SizeOf(Pointer));

  c := 0;
  P := Snapshot;
  i := @Result.FLeaks^[0];
  while Assigned(P) do
  begin
    if P^.MayLeak and not IsLeakIgnored(P) then
    begin
      i^ := P^.Data;
      Inc(i);
      Inc(c);
    end;
    P := P^.Next;
  end;

  // It is possible that class ignored later will also ignore some other memory
  // allocated before (like string or TValue) and thus lowering our size,
  // it must be set to correct value in second pass!
  if c = 0 then
  begin
    Result.Free;
    Result.FLength := 0;
    Result.FLeaks := nil;
  end
  else
    Result.FLength := c;
end;

class function TLeakCheck.GetMem(Size: NativeInt): Pointer;
begin
  Result := SysGetMem(Size + SizeMemRecord + SizeFooter);
  _AddRec(Result, Size);
  InitMem(Result);
  Inc(NativeUInt(Result), SizeMemRecord);
end;

class function TLeakCheck.GetObjectClass(APointer: Pointer; SafePtr: Boolean = False): TClass;
begin
  Result := LeakCheck.GetObjectClass(ToRecord(APointer), APointer, SafePtr);
end;

procedure CatLeak(const Data: MarshaledAString);
begin
  LeakStr := InternalReallocMem(LeakStr, StrLen(LeakStr) + Length(sLineBreak)
    + StrLen(Data) + 1);
  if LeakStr^ <> #0 then
    StrCat(LeakStr, sLineBreak);
  StrCat(LeakStr, Data);
end;

class function TLeakCheck.GetReport(Snapshot: Pointer): LeakString;
begin
  LeakStr := InternalGetMem(1);
  LeakStr^ := #0;
  GetReport(CatLeak, Snapshot);
  if LeakStr^ = #0 then
  begin
    Result.FData := nil;
    InternalFreeMem(LeakStr);
  end
  else
    Result.FData := LeakStr;
  LeakStr := nil;
end;

class procedure TLeakCheck.GetReport(const Callback: TLeakProc;
  Snapshot: Pointer = nil; SendSeparator: Boolean = False);
var
  Buff: TStringBuffer;

  function DivCeil(const a, b : Integer) : Integer; inline;
  begin
    Result:=(a + b - 1) div b;
  end;

  function IsChar(C: Word): Boolean; inline;
  begin
    // Printable ASCII
    Result := (C >= $20) and (C <= $7E);
  end;

  procedure SendBuf;
  begin
    Callback(Buff);
    Buff.Clear;
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
    Buff.EnsureFree(TypeInfo^.Name.Length + 1);
    StrCat(Buff, @TypeInfo^.Name.Data, TypeInfo^.Name.Length);
{$IFDEF AUTOREFCOUNT}
    Buff.EnsureFree(16);
    StrCat(Buff, ' {RefCount: ');
    StrCat(Buff, IntToStr(TObject(Data).RefCount));
    StrCat(Buff, '}');
{$ELSE}
    // Safer than using 'is'
    if LeakInfo.ClassType.InheritsFrom(TInterfacedObject) then
    begin
      Buff.EnsureFree(16);
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
    Buff.EnsureFree(48 + StringLength + 1);
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
    Size := Leak^.CurrentSize;
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

{$IF MaxStackSize > 0}
  procedure SendStackTrace(const Trace: TStackTrace);
  var
    i: Integer;
    BytesWritten: Integer;
  begin
    if Assigned(GetStackTraceFormatterProc) then
    begin
      InitializeStackFormatter;
      if Buff.Size < 256 + 2 then
        Buff.EnsureBuff(Buff.Size - (256 + 2));

      // Prepare buffer
      StrCat(Buff, '  ', 2);
      for i := 0 to Trace.Count - 1 do
      begin
        // Sanitize the buffer from previous call
        (PByte(Buff) + 2)^ := 0;
        BytesWritten := FStackTraceFormatter.FormatLine(Trace.Trace[i],
          Pointer(PByte(Buff) + 2), 256);
        if BytesWritten > 0 then
          Callback(Buff)
        else if BytesWritten < 0 then // If the result is negative discard all following frames
          Break;
        // else skip the frame
      end;
      // Cleanup the buffer
      Buff.Clear;
    end
    else
    begin
      // Fallback
      for i := 0 to Trace.Count - 1 do
      begin
        StrCat(Buff, '  $', 3);
        StrCat(Buff, IntToStr(NativeUInt(Trace.Trace[i]),
          SizeOf(Pointer) * 2, 16));
        SendBuf;
      end;
    end;
  end;

  procedure SendStackTraces;
  begin
    if Leak^.StackAllocated.Count > 0 then
    begin
      StrCat(Buff, 'Stack trace when the memory block was allocated:');
      SendBuf;
      SendStackTrace(Leak^.StackAllocated);
    end;
  end;
{$IFEND}

var
  CountSent: Boolean;
begin
  Buff := TStringBuffer.Create;
  CS.Enter;
  try
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

      Buff.EnsureFree(256);
      if (not CountSent) then begin
        CountSent := True;
        SendMemoryInfo;
      end;
      StrCat(Buff, 'Leak detected ');
      Data := Leak^.Data;
      StrCat(Buff, IntToStr(NativeUInt(Data), SizeOf(Pointer) * 2, 16));
      StrCat(Buff, ' size ');
      StrCat(Buff, IntToStr(Leak^.CurrentSize));
      StrCat(Buff, ' B');

      if Assigned(LeakInfo.ClassType) then
        AppendObject
      else if Assigned(LeakInfo.StringInfo) then
        AppendString;
      SendBuf;

      // There should be enough space in the buffer in any case
      if not Assigned(LeakInfo.ClassType) and not Assigned(LeakInfo.StringInfo) then
        SendDump;
{$IF MaxStackSize > 0}
      SendStackTraces;
{$IFEND}

      Leak := Leak^.Next;
    end;
  finally
    CS.Leave;
    Buff.Free;
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

{$IF TLeakCheck.MaxStackSize > 0}
class procedure TLeakCheck.GetStackTrace(var Trace: TStackTrace);
begin
  Trace.Count := GetStackTraceProc(3, @Trace.Trace[0], MaxStackSize);
end;

class procedure TLeakCheck.InitializeStackFormatter;
var
  OldTracer: TGetStackTrace;
begin
  // Use enhanced stack formatting
  if not Assigned(FStackTraceFormatter) then
  begin
    // Ignore all data allocated by the formatter, the formatter is required
    // to initialize all caches during creation or to ignore them itself.
    // Also disable stack tracing to speed things up.
    OldTracer := GetStackTraceProc;
    GetStackTraceProc := nil;
    BeginIgnore;
    try
      FStackTraceFormatter := GetStackTraceFormatterProc;
    finally
      EndIgnore;
      GetStackTraceProc := OldTracer;
    end;
  end;
end;
{$IFEND}

class procedure TLeakCheck.Initialize;
begin
  GetMemoryManager(FOldMemoryManager);
  CS.Initialize;
{$IF EnableFreedObjectDetection}
  with FakeVMT do
  begin
    Parent := @PClassData(PByte(TLeakCheck.TFreedObject) + vmtSelfPtr).SelfPtr;
    SelfPtr := TClass(PByte(@FakeVMT) - vmtSelfPtr);
  end;
{$IFEND}
{$IF Defined(MSWINDOWS) AND TLeakCheck.UseInternalHeap}
  InternalHeap := HeapCreate(HEAP_GENERATE_EXCEPTIONS, 0, 1024*1024);
{$IFEND}
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

{$IFDEF DEBUG}
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
{$ENDIF}

class function TLeakCheck.IsLeakIgnored(const LeakInfo: TLeakInfo; Rec: PMemRecord): Boolean;
begin
  if (IgnoredLeakTypes = []) and (not Assigned(InstanceIgnoredProc)) then
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

class function TLeakCheck.IsString(APointer: Pointer): Boolean;
begin
  Result := LeakCheck.IsString(ToRecord(APointer), APointer);
end;

class function TLeakCheck.IsValidClass(AClassType: TClass): Boolean;
begin
  Result := LeakCheck.IsValidClass(AClassType);
end;

{$IFDEF ANDROID}
class function TLeakCheck.IsValidRec(Rec: PMemRecord): Boolean;
var
  P: PMemRecord;
begin
  P := Last;
  while Assigned(P) do
  begin
    if P = Rec then
      Exit(True);
    P := P^.Prev;
  end;
  Result := False;
end;
{$ENDIF}

class function TLeakCheck.IsLeakIgnored(Rec: PMemRecord): Boolean;
var
  Info: TLeakInfo;
begin
  if (IgnoredLeakTypes = []) and (not Assigned(InstanceIgnoredProc)) then
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
  Result := SysReallocMem(P, Size + SizeMemRecord + SizeFooter);
  _AddRec(Result, Size);
  Inc(NativeUInt(Result), SizeMemRecord);
end;

class function TLeakCheck.RegisterExpectedMemoryLeak(P: Pointer): Boolean;
begin
  Dec(NativeUInt(P), SizeMemRecord);
  _SetLeaks(P, False);
  Result := True;
  // Always call the previous memory managers to suppress warning at exit
  FOldMemoryManager.RegisterExpectedMemoryLeak(P);
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

{$IF TLeakCheck.NeedsIndexTypes}
type
  TCallInfo = record
    VirtualIndex: Integer;
    Instance: Pointer;
    ClassType: TClass;
    ClassData: PClassData;
    MethodAddr: Pointer;
    Rec: TLeakCheck.PMemRecord;
  end;
  TMethodNameGetter = function(Offset: NativeInt): MarshaledAString;
  TAppendAdditionalInfo = procedure(var Buff: TStringBuffer; Context: Pointer);

procedure SendCallError(var Buff: TStringBuffer; Caption: MarshaledAString);
begin
  try
{$IF Defined(MSWINDOWS) AND NOT Defined(NO_MESSAGEBOX)}
    MessageBoxA(0, Buff, Caption, MB_ICONERROR or MB_OK);
{$ELSE}
    ReportLeak(Buff);
{$IFEND}
  finally
    Buff.Free;
  end;
end;

procedure GetCallInfo(out CallInfo: TCallInfo; TypeInfo: PTypeInfo;
  const Self: TObject);
var
  LTypeData: PIntegerTypeData;
begin
  // Get virtual index stored as ordinal range of our special types
  Assert(TypeInfo^.Kind = tkInteger);
  PByte(LTypeData) := PByte(@TypeInfo.Name.Data) + TypeInfo.Name.Length;
  Assert(LTypeData^.MinValue = LTypeData^.MaxValue);
  CallInfo.VirtualIndex := LTypeData^.MinValue;
  CallInfo.Instance := Self;
  if Assigned(Self) then
  begin
    CallInfo.Rec := TLeakCheck.ToRecord(Self);
    CallInfo.ClassType := CallInfo.Rec^.PrevClass;
    PByte(CallInfo.ClassData) := PByte(CallInfo.ClassType) + vmtSelfPtr;
  end;
  // else cleanup must be provided by the caller
end;

procedure FormatCallInfo(out Buff: TStringBuffer; const CallInfo: TCallInfo;
  NameGetter: TMethodNameGetter; Message: MarshaledAString;
  AppendAdditionalInfo: TAppendAdditionalInfo = nil; Context: Pointer = nil);
var
  NameBuffer: array[0..255] of Byte;
{$IF TLeakCheck.MaxStackSize > 0}
  StackAllocated: TLeakCheck.TStackTrace;
{$IF TLeakCheck.RecordFreeStackTrace}
  StackFreed: TLeakCheck.TStackTrace;
{$IFEND}
{$IFEND}

{$IF TLeakCheck.MaxStackSize > 0}
  procedure AppendStackTrace(const Trace: TLeakCheck.TStackTrace);
  var
    i: Integer;
    BytesWritten: Integer;
  begin
    if Assigned(TLeakCheck.GetStackTraceFormatterProc) then
    begin
      TLeakCheck.InitializeStackFormatter;
      for i := 0 to Trace.Count - 1 do
      begin
        BytesWritten := TLeakCheck.FStackTraceFormatter.FormatLine(Trace.Trace[i],
          @NameBuffer[0], Length(NameBuffer));
        if BytesWritten > 0 then
        begin
          Buff.EnsureFree(Length(NameBuffer) + 4);
          StrCat(Buff, sLineBreak);
          StrCat(Buff, '  ', 2);
          StrCat(Buff, @NameBuffer[0]);
        end
        else if BytesWritten < 0 then // If the result is negative discard all following frames
          Break;
        // else skip the frame
      end;
    end
    else
    begin
      // Fallback
      // (LineBreak + Space + $ + address) * Count + terminator
      Buff.EnsureFree((2 + 2 + 1 + SizeOf(Pointer) * 2) * Trace.Count + 1);
      for i := 0 to Trace.Count - 1 do
      begin
        StrCat(Buff, sLineBreak);
        StrCat(Buff, '  $', 3);
        StrCat(Buff, IntToStr(NativeUInt(Trace.Trace[i]),
          SizeOf(Pointer) * 2, 16));
      end;
    end;
  end;

  procedure AppendStackTraces;
  begin
    if StackAllocated.Count > 0 then
    begin
      Buff.EnsureFree(128);
      StrCat(Buff, sLineBreak);
      StrCat(Buff, 'Stack trace when the memory block was originally allocated:');
      AppendStackTrace(StackAllocated);
    end;
{$IF TLeakCheck.RecordFreeStackTrace}
    if StackAllocated.Count > 0 then
    begin
      Buff.EnsureFree(128);
      StrCat(Buff, sLineBreak);
      StrCat(Buff, 'Stack trace when the memory block was freed:');
      AppendStackTrace(StackFreed);
    end;
{$IFEND}
  end;
{$IFEND}

var
  Name: MarshaledAString;
begin
{$IF TLeakCheck.MaxStackSize > 0}
  if Assigned(CallInfo.ClassType) then
  begin
      // Save stack so it doesn't get freed by allocations used by higher-level
      // utility functions.
      StackAllocated := CallInfo.Rec^.StackAllocated;
{$IF TLeakCheck.RecordFreeStackTrace}
      StackFreed := CallInfo.Rec^.StackFreed;
{$IFEND}
  end;
{$IFEND}
  Buff := TStringBuffer.Create;
  try
    Buff.EnsureFree(512);
    StrCat(Buff, Message);
    StrCat(Buff, ' An access violation will now be raised in order to abort the current operation.');
    StrCat(Buff, sLineBreak);
    StrCat(Buff, 'Class type: ');
    if Assigned(CallInfo.ClassData) then
      StrCat(Buff, @CallInfo.ClassData^.ClassName.Data, CallInfo.ClassData^.ClassName.Length)
    else
      StrCat(Buff, 'unknown (memory info block corrupted)');
    StrCat(Buff, sLineBreak);
    StrCat(Buff, 'Virtual method index: ');
    StrCat(Buff, IntToStr(CallInfo.VirtualIndex));
    StrCat(Buff, sLineBreak);
    StrCat(Buff, 'Virtual method address: ');
    if Assigned(CallInfo.MethodAddr) then
      StrCat(Buff, IntToStr(NativeUInt(CallInfo.MethodAddr), SizeOf(Pointer) * 2, 16))
    else
      StrCat(Buff, 'unknown');
    Name := nil;
{$IF TLeakCheck.MaxStackSize > 0}
    if Assigned(CallInfo.MethodAddr) and Assigned(TLeakCheck.GetStackTraceFormatterProc) then
    begin
      TLeakCheck.InitializeStackFormatter;
      if TLeakCheck.FStackTraceFormatter.FormatLine(CallInfo.MethodAddr,
        @NameBuffer[0], Length(NameBuffer)) > 0 then
      begin
        Name := @NameBuffer[0];
      end;
    end;
{$IFEND}
    if not Assigned(Name) then
      Name := NameGetter(CallInfo.VirtualIndex  * SizeOf(Pointer));
    if Assigned(Name) then
    begin
      StrCat(Buff, sLineBreak);
      StrCat(Buff, 'Virtual method name: ');
      Buff.EnsureFree(StrLen(Name) + 1);
      StrCat(Buff, Name);
    end;
    if Assigned(AppendAdditionalInfo) then
      AppendAdditionalInfo(Buff, Context);
{$IF TLeakCheck.MaxStackSize > 0}
    if Assigned(CallInfo.ClassType) then
    begin
      AppendStackTraces;
    end;
{$IFEND}
  except
    Buff.Free;
    raise;
  end;
end;
{$IFEND}

{$IF TLeakCheck.EnableVirtualCallsOnFreedObjectInterception}
function DefaultVirtualNameGetter(Offset: NativeInt): MarshaledAString;
begin
{$WARN SYMBOL_DEPRECATED OFF}
  case Offset of
{$IFDEF AUTOREFCOUNT}
    vmtObjAddRef :
      Result := '_ObjAddRef';
    vmtObjRelease :
      Result := '_ObjRelease';
{$ENDIF}
    vmtEquals :
      Result := 'Equals';
    vmtGetHashCode :
      Result := 'GetHashCode';
    vmtToString :
      Result := 'ToString';
    vmtSafeCallException :
      Result := 'SafeCallException';
    vmtAfterConstruction :
      Result := 'AfterConstruction';
    vmtBeforeDestruction :
      Result := 'BeforeDestruction';
    vmtDispatch :
      Result := 'Dispatch';
    vmtDefaultHandler :
      Result := 'DefaultHandler';
    vmtNewInstance :
      Result := 'NewInstance';
    vmtFreeInstance :
      Result := 'FreeInstance';
    vmtDestroy :
      Result := 'Destroy'
    else
      Result := nil;
  end;
{$WARN SYMBOL_DEPRECATED ON}
end;

class procedure TLeakCheck.ReportInvalidVirtualCall(const Self: TObject;
  ATypeInfo: Pointer);
var
  CallInfo: TCallInfo;
  Buff: TStringBuffer;
begin
  // Prevent memory block info overwrite
  CS.Enter;
  try
    // Gather all memory block dependent data here
    GetCallInfo(CallInfo, ATypeInfo, Self);
    Dec(CallInfo.VirtualIndex, ((- vmtParent) div SizeOf(Pointer)) - 1);
    // Get original class
    with CallInfo do
    begin
      if LeakCheck.IsValidClass(CallInfo.ClassType) then
      begin
        // Obtain the original method address from the VMT
        MethodAddr := PPointer(PByte(ClassType) + (VirtualIndex * SizeOf(Pointer)))^;
      end
      else
      begin
        ClassData := nil;
        ClassType := nil;
        MethodAddr := nil;
      end;
    end;
    // The rest is just formatting but keep the CS acquired so we can safely use
    // all local buffers.

    FormatCallInfo(Buff, CallInfo, DefaultVirtualNameGetter,
      'An attempt to call a virtual method on a freed object.');
  finally
    CS.Leave;
  end;

  // Frees the Buff
  SendCallError(Buff, 'Virtual call error');
  System.Error(reInvalidPtr);
end;
{$IFEND EnableVirtualCallsOnFreedObjectInterception}

{$IF TLeakCheck.EnableInterfaceCallsOnFreedObjectInterception}
type
  PInterfaceInfo = ^TInterfaceInfo;
  TInterfaceInfo = record
    Entry: PInterfaceEntry;
    TypeInfo: PTypeInfo;
  end;

function DefaultInterfaceNameGetter(Offset: NativeInt): MarshaledAString;
begin
{$WARN SYMBOL_DEPRECATED OFF}
  case Offset of
    vmtQueryInterface :
      Result := 'QueryInterface';
    vmtAddRef :
      Result := 'AddRef';
    vmtRelease :
      Result := 'Release'
    else
      Result := nil;
  end;
{$WARN SYMBOL_DEPRECATED ON}
end;

procedure AppendInterfaceInfo(var Buff: TStringBuffer; Context: Pointer);
var
  IntfInfo: PInterfaceInfo {absolute Context};
  TypeInfo: PTypeInfo;
begin
  IntfInfo := Context;
  TypeInfo := IntfInfo^.TypeInfo;
  if Assigned(IntfInfo^.TypeInfo) then
  begin
    StrCat(Buff, sLineBreak);
    StrCat(Buff, 'Interface type: ');
    StrCat(Buff, @IntfInfo^.TypeInfo^.Name.Data, IntfInfo^.TypeInfo^.Name.Length);
  end;
end;

class procedure TLeakCheck.ReportInvalidInterfaceCall(Self, SelfStd: Pointer;
  ATypeInfo: Pointer);

  function FindObjectInstance(VTable: PPointer): Pointer;
  var
    Origin: NativeUInt;
    LMemInfo: TMemoryBasicInformation;
    Limit: NativeUInt;
    Rec: PMemRecord;
  label Next;
  begin
    Origin := NativeUInt(VTable);
    if Origin < MaxClassSize then
      Exit(nil);
    Limit := Origin - MaxClassSize;
    Dec(VTable); //Self
    // Do not skip TInterfacedObject in case it is the cause of the error
    // Dec(VTable); //TInterfacedObject VTable
    // Do not skip FRefCount in case the object has none
    // Dec(VTable); //FRefCount
{$IFDEF MSWINDOWS}
    {No VM info yet}
    LMemInfo.RegionSize := 0;
{$ENDIF}
    while NativeUInt(VTable) > Limit do
    begin
      // May not work on some Posix platforms if heap is not present in the
      // proc map when the map is loaded by LeakCheck.Utils (Android). We
      // figured out that the maps may mutate during runtime but we're not
      // reloading them continuously to improve accuracy.
      if IsValidVMTAddress(VTable, LMemInfo) then
      begin
        if VTable^ <> FakeVMT.SelfPtr then
          goto Next;
        Rec := ToRecord(VTable);
        if Rec^.CurrentSize <> 0 then // Still alive
          goto Next;
        if not LeakCheck.IsValidClass(Rec^.PrevClass) then
          goto Next;
        // IsValidClass does not check for this
        if NativeUInt(Rec^.PrevClass.InstanceSize) <> Rec^.PrevSize then
          goto Next;
        // Is origin inside the class we just found? Or are we too far out...
        if Origin > NativeUInt(VTable) + Rec^.PrevSize then
          goto Next;
        Exit(VTable);
      end;
Next:
      Dec(VTable);
    end;
    Result := nil;
  end;

  procedure FindIntfInfo(out Result: TInterfaceInfo; Offset: Integer;
    ClassPtr: TClass);
  var
    IntfTable: PInterfaceTable;
    I: Integer;
    TypeInfo: PPointer;
  begin
    while ClassPtr <> nil do
    begin
      IntfTable := ClassPtr.GetInterfaceTable;
      if IntfTable <> nil then
        // Proceed from top to bottom of the interface hierarchy (IOffset may
        // match for multiple interfaces).
        for I := IntfTable.EntryCount-1 downto 0 do
          with IntfTable.Entries[I] do
          begin
            if VTable <> nil then
            begin
              if IOffset = Offset then
              begin
                Result.Entry := @IntfTable.Entries[I];
                Pointer(TypeInfo) := PByte(@IntfTable.Entries) +
                  (IntfTable.EntryCount * SizeOf(TInterfaceEntry));
                // Fetch whatever RTTI uses to get the type info
                // Get the type info array (TypeInfo is ^^PTypeInfo at this point)
                TypeInfo := @IntfTable.Entries[IntfTable.EntryCount];
                // Skip to current item
                Inc(TypeInfo, I);
                // Get the pointer to PTypeInfo
                TypeInfo := TypeInfo^;
                // Get thy PTypeInfo itself
                Result.TypeInfo := TypeInfo^;
                Exit;
              end;
            end;
          end;
      ClassPtr := ClassPtr.ClassParent;
    end;
    Result.Entry := nil;
    Result.TypeInfo := nil;
  end;

var
  Instance: Pointer;
  CallInfo: TCallInfo;
  IntfInfo: TInterfaceInfo;
  Buff: TStringBuffer;
begin
  // Prevent memory block info overwrite
  CS.Enter;
  try
    // Find self
    Instance := FindObjectInstance(Self);
    // If failed, try to check if this was StdCall
    if not Assigned(Instance) and Assigned(SelfStd) then
    begin
      Instance := FindObjectInstance(SelfStd);
      Self := SelfStd;
    end;

    // Gather all memory block dependent data here
    GetCallInfo(CallInfo, ATypeInfo, Instance);
    // Get original class
    with CallInfo do
    begin
      // We know instance is OK, FindObjectInstance makes sure of that.
      if Assigned(Instance) then
      begin
        // Obtain the original method address from the VMT, note that this is
        // actually a proxy call generated by the compiler that will fix Self to
        // point to the object instance rather than the interface VTable. Then
        // the actual method gets called (that's why the symbols will be off).
        FindIntfInfo(IntfInfo, NativeInt(Self) - NativeInt(Instance), CallInfo.ClassType);
        if Assigned(IntfInfo.Entry) then
          MethodAddr := PPointer(PByte(IntfInfo.Entry.VTable) + (VirtualIndex * SizeOf(Pointer)))^
        else
          MethodAddr := nil
      end
      else
      begin
        ClassData := nil;
        ClassType := nil;
        MethodAddr := nil;
        IntfInfo.Entry := nil;
        IntfInfo.TypeInfo := nil;
      end;
    end;
    // The rest is just formatting but keep the CS acquired so we can safely use
    // all local buffers.

    FormatCallInfo(Buff, CallInfo, DefaultInterfaceNameGetter,
      'An attempt to call an interface method on a freed object.',
      AppendInterfaceInfo, @IntfInfo);
  finally
    CS.Leave;
  end;

  // Frees the Buff
  SendCallError(Buff, 'Interface call error');
  System.Error(reInvalidPtr);
end;
{$IFEND EnableInterfaceCallsOnFreedObjectInterception}

class procedure TLeakCheck.Resume;
var
  LeakCheckingMemoryManager: TMemoryManagerEx;
begin
  with LeakCheckingMemoryManager do
  begin
{$IFDEF XE2_UP}
    GetMem := TLeakCheck.GetMem;
    FreeMem := TLeakCheck.FreeMem;
    ReallocMem := TLeakCheck.ReallocMem;
    AllocMem := TLeakCheck.AllocMem;
{$ELSE}
    // Types differ, this is easier than ifdefing all definitions
    GetMem := Pointer(@TLeakCheck.GetMem);
    FreeMem := Pointer(@TLeakCheck.FreeMem);
    ReallocMem := Pointer(@TLeakCheck.ReallocMem);
    AllocMem := Pointer(@TLeakCheck.AllocMem);
{$ENDIF}
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

class function TLeakCheck.ToRecord(P: Pointer): TLeakCheck.PMemRecord;
begin
  NativeUInt(Result) := NativeUInt(P) - SizeOf(TLeakCheck.TMemRecord);
end;

class function TLeakCheck.UnregisterExpectedMemoryLeak(P: Pointer): Boolean;
begin
  Dec(NativeUInt(P), SizeMemRecord);
  _SetLeaks(P, True);
  Result := True;
  // Always call the previous memory managers to suppress warning at exit
  FOldMemoryManager.UnregisterExpectedMemoryLeak(P);
end;

{$ENDREGION}

{$REGION 'TInvalidVirtualCall<E>'}

{$IF TLeakCheck.EnableVirtualCallsOnFreedObjectInterception}
class procedure TInvalidVirtualCall<E>.Indexed(const Self: TObject);
begin
  TLeakCheck.ReportInvalidVirtualCall(Self, TypeInfo(E));
end;
{$IFEND}

{$ENDREGION}

{$REGION 'TInvalidInterfaceCall'}

{$IF TLeakCheck.EnableInterfaceCallsOnFreedObjectInterception}
{$IFDEF CPU386}
function GetEBP : DWORD; assembler;
asm
	mov EAX, EBP
end;
{$ENDIF}

class procedure TInvalidInterfaceCall<E>.Indexed(const Self: Pointer);
begin
  // Only x86 use mutliple calling conventions all other platforms have either
  // ABI defined calling convention or platform defined one (but use just the
  // one as opposed to x86).
  TLeakCheck.ReportInvalidInterfaceCall(Self,
    {$IFDEF CPU386}PPointer(GetEBP + 8)^{$ELSE}nil{$ENDIF}, TypeInfo(E));
end;

class procedure TInvalidInterfaceCall<E>.IndexedStd(const Self: Pointer);
begin
  TLeakCheck.ReportInvalidInterfaceCall(Self, nil, TypeInfo(E));
end;
{$IFEND}

{$ENDREGION}

{$REGION 'TLeakCheck.TMemRecord'}

function TLeakCheck.TMemRecord.Data: Pointer;
begin
  NativeUInt(Result):=NativeUInt(@Self) + SizeOf(TMemRecord);
end;

function TLeakCheck.TMemRecord.Size: NativeUInt;
begin
  if CurrentSize <> 0 then
    Result := CurrentSize
  else
    Result := PrevSize;
end;

{$ENDREGION}

{$REGION 'TLeakCheck.TSnapshot'}

procedure TLeakCheck.TSnapshot.Create;
begin
  CS.Enter;
  FAsserter := TInterfacedObject.Create;
  FSnapshot := TLeakCheck.CreateSnapshot;
  // Make sure our asserter is not marked as a leak
  TLeakCheck.MarkNotLeaking(Snapshot);
  CS.Leave;
end;

procedure TLeakCheck.TSnapshot.Free;
begin
  FSnapshot := nil;
  FAsserter := nil;
end;

function TLeakCheck.TSnapshot.LeakSize: NativeUInt;
var
  Leaks: TLeaks;
begin
  if not Assigned(FAsserter) then
    Exit(0);

  Leaks := TLeakCheck.GetLeaks(Snapshot);
  Result := Leaks.TotalSize;
  Leaks.Free;
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

{$REGION 'TStringBuffer'}

procedure TStringBuffer.Clear;
begin
  if Assigned(FBuffer) then
    FBuffer^ := #0;
end;

class function TStringBuffer.Create: TStringBuffer;
begin
  Result.FBuffer := nil;
  Result.FBufferSize := 0;
end;

procedure TStringBuffer.EnsureBuff(IncBy: NativeInt);
begin
  Inc(FBufferSize, IncBy);
  if Assigned(FBuffer) then
    FBuffer := InternalReallocMem(FBuffer, FBufferSize)
  else
  begin
    FBuffer := InternalGetMem(FBufferSize);
    FBuffer^ := #0;
  end;
end;

procedure TStringBuffer.EnsureFree(Bytes: NativeInt);
var
  i: NativeInt;
begin
  if Assigned(FBuffer) then
  begin
    i := StrLen(FBuffer); // Position
    i := FBufferSize - i; // Remaining
    if i < Bytes then
      EnsureBuff(2 * Bytes);
  end
  else
    EnsureBuff(2 * Bytes);
end;

class operator TStringBuffer.Explicit(const ABuffer: TStringBuffer): NativeUInt;
begin
  Result := NativeUInt(ABuffer.FBuffer);
end;

class operator TStringBuffer.Explicit(const ABuffer: TStringBuffer): PByte;
begin
  Result := PByte(ABuffer.FBuffer);
end;

procedure TStringBuffer.Free;
begin
  if Assigned(FBuffer) then
    InternalFreeMem(FBuffer);
end;

class operator TStringBuffer.Implicit(const ABuffer: TStringBuffer): MarshaledAString;
begin
  Result := ABuffer.FBuffer;
end;

{$ENDREGION}

{$REGION 'TLeak'}

class operator TLeak.Equal(const L: TLeak; const R: Pointer): Boolean;
begin
  Result := L.Data = R;
end;

function TLeak.GetSize: NativeUInt;
begin
  Result := TLeakCheck.ToRecord(Data).CurrentSize;
end;

function TLeak.GetTypeKind: TTypeKind;
begin
  if Assigned(GetObjectClass(TLeakCheck.ToRecord(Data), Data, True)) then
    Result := tkClass
  else if IsString(TLeakCheck.ToRecord(Data), Data) then
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
    InternalFreeMem(FLeaks);
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
    InternalFreeMem(FData);
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

// Note that PMemRecord pointer is passed to these so it can be only accessed
// after some basic checks and not during function call to prevent AVs if the
// basic checks fail.

{Checks whether the given address is a valid address for a VMT entry.}
function IsValidVMTAddress(APAddress: Pointer;
  var AMemInfo: TMemoryBasicInformation): Boolean;
begin
  {Do some basic pointer checks: Must be dword aligned and beyond 64K}
  if (Cardinal(APAddress) > 65535)
    and (Cardinal(APAddress) and 3 = 0) then
  begin
{$IFDEF MSWINDOWS}
    {Do we need to recheck the virtual memory?}
    if (Cardinal(AMemInfo.BaseAddress) > Cardinal(APAddress))
      or ((Cardinal(AMemInfo.BaseAddress) + AMemInfo.RegionSize) < (Cardinal(APAddress) + 4)) then
    begin
      {Get the VM status for the pointer}
      AMemInfo.RegionSize := 0;
      VirtualQuery(APAddress,  AMemInfo, SizeOf(AMemInfo));
    end;
    {Check the readability of the memory address}
    Result := (AMemInfo.RegionSize >= 4)
      and (AMemInfo.State = MEM_COMMIT)
      and (AMemInfo.Protect and (PAGE_READONLY or PAGE_READWRITE or PAGE_EXECUTE or PAGE_EXECUTE_READ or PAGE_EXECUTE_READWRITE or PAGE_EXECUTE_WRITECOPY) <> 0)
      and (AMemInfo.Protect and PAGE_GUARD = 0);
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

function IsValidClass(AClassType: TClass): Boolean;
var
  LMemInfo: TMemoryBasicInformation;

  {Returns true if AClassPointer points to a class VMT}
  function InternalIsValidClass(AClassPointer: PByte; ADepth: Integer = 0): Boolean;
  var
    LParentClassSelfPointer: PCardinal;
    LTypeInfo: PTypeInfo;
  begin
    {Check that the self pointer, parent class self pointer, typeinfo pointer
     and typeinfo addresses are valid}
    if (ADepth < 1000)
      and IsValidVMTAddress(AClassPointer + vmtSelfPtr, LMemInfo)
      and IsValidVMTAddress(AClassPointer + vmtParent, LMemInfo)
      and IsValidVMTAddress(AClassPointer + vmtTypeInfo, LMemInfo)
      and IsValidVMTAddress(PPointer(AClassPointer + vmtTypeInfo)^, LMemInfo) then
    begin
      {Get a pointer to the parent class' self pointer}
      LParentClassSelfPointer := PPointer(Integer(AClassPointer) + vmtParent)^;
      LTypeInfo := PPTypeInfo(Integer(AClassPointer) + vmtTypeInfo)^;
      {Check that the self pointer as well as the parent class is valid}
      Result := (PPointer(Integer(AClassPointer) + vmtSelfPtr)^ = AClassPointer)
        and ((LParentClassSelfPointer = nil)
          or ((LTypeInfo^.Kind = tkClass)
            and IsValidVMTAddress(LParentClassSelfPointer, LMemInfo)
            and InternalIsValidClass(PByte(LParentClassSelfPointer^), ADepth + 1)));
    end
    else
      Result := False;
  end;

begin
  if not Assigned(AClassType) then
    Exit(False);
{$IF TLeakCheck.EnableFreedObjectDetection}
  if AClassType = FakeVMT.SelfPtr then
    Exit(False);
{$IFEND}
{$IFDEF MSWINDOWS}
  {No VM info yet}
  LMemInfo.RegionSize := 0;
{$ENDIF}
  Result := InternalIsValidClass(Pointer(AClassType), 0);
end;

{Returns the class for a memory block. Returns nil if it is not a valid class}
function GetObjectClass(Rec: TLeakCheck.PMemRecord; APointer: Pointer;
  SafePtr: Boolean = False): TClass;
var
  LMemInfo: TMemoryBasicInformation;
begin
  if not Assigned(APointer) then
    Exit(nil);

{$IFDEF MSWINDOWS}
  {No VM info yet}
  LMemInfo.RegionSize := 0;
{$ENDIF}
  // Especially on Posix when proc/self/maps are read and kept as singleton
  // memory information may change in runtime and may be incomplete when the
  // memory map was originally read, so it is useful to skip this check if we
  // know the pointer is safe (ie. when calling from LeakCechk itself).
  // Later checks operate only on TClass data which are considered constant and
  // should lye in code or constants segment which should be preset in memory
  // map right after startup.
  if (not SafePtr) and (not IsValidVMTAddress(APointer, LMemInfo)) then
    Exit(nil);
  {Get the class pointer from the (suspected) object}
  Result := TClass(PCardinal(APointer)^);
  {Check the block}
  if NativeUInt(Result) < -vmtSelfPtr then
    Exit(nil);
  if IsValidVMTAddress(PByte(Result) + vmtInstanceSize, LMemInfo) then
  begin
{$IF TLeakCheck.LeakCheckEnabled}
    // Check size first, shold be easy and fast enough
    if PNativeUInt(PByte(Result) + vmtInstanceSize)^ <> Rec.Size then
      Result := nil
    else
{$IFEND}
    if (not IsValidClass(Result)) then
      Result := nil;
  end
  else
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

{$IF TLeakCheck.LeakCheckEnabled}
initialization
  TLeakCheck.Initialize;
finalization
  TLeakCheck.Finalize;
{$IFEND}

end.
