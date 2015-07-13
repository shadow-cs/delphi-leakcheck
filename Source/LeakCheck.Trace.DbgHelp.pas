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

unit LeakCheck.Trace.DbgHelp;

interface

/// <summary>
///   Native DbgHelp solution. Win 32 only. Similar to WinApi solution but
///   works without Win32 support if DbgHelp redistributable is installed. Does
///   not use global caches.
/// </summary>
function DbgHelpStackTrace(IgnoredFrames: Integer; Data: PPointer;
  Size: Integer): Integer;

implementation

uses
  Windows;

{$ALIGN 4}

type
  PKDHELP = ^KDHELP;
  KDHELP = record
    //
    // address of kernel thread object, as provided in the
    // WAIT_STATE_CHANGE packet.
    //
    Thread: DWORD;
    //
    // offset in thread object to pointer to the current callback frame
    // in kernel stack.
    //
    ThCallbackStack: DWORD;
    //
    // offsets to values in frame:
    //
    // address of next callback frame
    NextCallback: DWORD;
    // address of saved frame pointer (if applicable)
    FramePointer: DWORD;
    //
    // Address of the kernel function that calls out to user mode
    //
    KiCallUserMode: DWORD;
    //
    // Address of the user mode dispatcher function
    //
    KeUserCallbackDispatcher: DWORD;
    //
    // Lowest kernel mode address
    //
    SystemRangeStart: DWORD;
    //
    // offset in thread object to pointer to the current callback backing
    // store frame in kernel stack.
    //
    ThCallbackBStore: DWORD;
    Reserved: array[0..7] of DWORD;
  end;
type
  ADDRESS_MODE = (AddrMode1616, AddrMode1632, AddrModeReal, AddrModeFlat);

  LPADDRESS = ^ADDRESS;
  ADDRESS = record
    Offset: DWORD;
    Segment: WORD;
    Mode: DWORD;
  end;

  LPSTACKFRAME = ^STACKFRAME;
  STACKFRAME = record
    AddrPC: ADDRESS;                // program counter
    AddrReturn: ADDRESS;            // return address
    AddrFrame: ADDRESS;             // frame pointer
    AddrStack: ADDRESS;             // stack pointer
    FuncTableEntry: Pointer;        // pointer to pdata/fpo or NULL
    Params: array[0..3] of DWORD;   // possible arguments to the function
    bFar: LONGBOOL;                 // WOW far call
    bVirtual: LONGBOOL;             // is this a virtual frame?
    Reserved: array[0..2] of DWORD;
    KdHelp: KDHELP;
    AddrBStore: ADDRESS;            // backing store pointer
  end;

  PIMAGEHLP_LINE = ^IMAGEHLP_LINE;
  IMAGEHLP_LINE = record
    SizeOfStruct: DWORD;           // set to sizeof(IMAGEHLP_LINE)
    Key: Pointer;                  // internal
    LineNumber: DWORD;             // line number in file
    FileName: PChar;               // full filename
    Address: DWORD;                // first instruction of line
  end;

  PREAD_PROCESS_MEMORY_ROUTINE = function(hProcess: THandle; lpBaseAddress: DWORD;
    lpBuffer: Pointer; nSize: DWORD; var lpNumberOfBytesRead: DWORD): Boolean; stdcall;

  PFUNCTION_TABLE_ACCESS_ROUTINE = function(hProcess: THandle; AddrBase: DWORD): Pointer; stdcall;

  PGET_MODULE_BASE_ROUTINE = function(hProcess: THandle; Address: DWORD): DWORD; stdcall;

  PTRANSLATE_ADDRESS_ROUTINE = function(hProcess, hThread: THandle; lpaddr: LPADDRESS): DWORD; stdcall;

const
  SDbgHelpDll = 'dbghelp.dll';

  function StackWalk(MachineType: DWORD; hProcess, hThread: THandle;
    StackFrame: LPSTACKFRAME; ContextRecord: Pointer;
    ReadMemoryRoutine: PREAD_PROCESS_MEMORY_ROUTINE;
    FunctionTableAccessRoutine: PFUNCTION_TABLE_ACCESS_ROUTINE;
    GetModuleBaseRoutine: PGET_MODULE_BASE_ROUTINE;
    TranslateAddress: PTRANSLATE_ADDRESS_ROUTINE): Integer; stdcall; external SDbgHelpDll;
  function SymFunctionTableAccess(hProcess: THandle; AddrBase: DWORD): Pointer; stdcall; external SDbgHelpDll;
  function SymGetModuleBase(hProcess: THandle; Address: DWORD): DWORD; stdcall; external SDbgHelpDll;

function GetEIP : DWORD; assembler;
asm
	mov EAX, dword ptr [ESP]
end;

function GetESP : DWORD; assembler;
asm
	mov EAX, ESP
end;

function GetEBP : DWORD; assembler;
asm
	mov EAX, EBP
end;

procedure InitContext(var Context: TContext);
begin
	FillChar(Context, sizeof(TContext), 0);
	Context.ContextFlags := CONTEXT_FULL;

	Context.Eip:=GetEIP;
	Context.Esp:=GetESP+4;
	Context.Ebp:=GetEBP;
end;

procedure Prepare(var Stack: STACKFRAME; const Context: TContext);
begin
  FillChar(Stack, sizeof(STACKFRAME), 0);
  Stack.AddrPC.Offset := Context.Eip;
  Stack.AddrPC.Mode := DWORD(AddrModeFlat);
  Stack.AddrStack.Offset := Context.Esp;
  Stack.AddrStack.Mode   := DWORD(AddrModeFlat);
  Stack.AddrFrame.Offset := Context.Ebp;
  Stack.AddrFrame.Mode   := DWORD(AddrModeFlat);
end;

function GetNextFrame(var Stack: STACKFRAME; var Context: TContext): Pointer;
begin
  if (StackWalk(IMAGE_FILE_MACHINE_I386, GetCurrentProcess(), GetCurrentThread(),
      @Stack, @Context, nil, SymFunctionTableAccess, SymGetModuleBase, nil) <> 0) then
  begin
    Result := Pointer(Stack.AddrPC.Offset);
  end
  else
    Result := nil;
end;

function DbgHelpStackTrace(IgnoredFrames: Integer; Data: PPointer;
  Size: Integer): Integer;
var
  Context: TContext;
  Stack: STACKFRAME;
  i: Integer;
  Addr: Pointer;
begin
  InitContext(Context);
  Prepare(Stack, Context);
  Result := 0;

  // First skip ignored frames
  for i := 0 to IgnoredFrames - 1 do
  begin
    Addr := GetNextFrame(Stack, Context);
    if not Assigned(Addr) then
      Exit;
  end;

  // Then record the trace
  for i := 0 to Size  - 1 do
  begin
    Addr := GetNextFrame(Stack, Context);
    if not Assigned(Addr) then
      Exit;
    Inc(Result);
    Data^ := Addr;
    Inc(Data);
  end;
end;

end.
