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

program LeakCheck.Injector;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  Windows, TlHelp32,
  SysUtils;

const
  THREAD_SUSPEND_RESUME = $0002;

function OpenThread(dwDesiredAccess: DWORD; bInheritHandle: BOOL;
  dwThreadId: DWORD): THandle; winapi; external 'kernel32.dll';

function ListThreads(hProcess: HMODULE): TArray<THandle>;
var
  hThreadSnap: THandle;
  te32: TThreadEntry32;
  dwOwnerPID: DWORD;
  ids: TArray<TThreadId>;
  thread: TThreadId;
begin
  Result := nil;

  dwOwnerPID := GetProcessId(hProcess);
  // Take a snapshot of all running threads
  hThreadSnap := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if (hThreadSnap = INVALID_HANDLE_VALUE) then
    RaiseLastOSError;
  try
    // Fill in the size of the structure before using it.
    te32.dwSize := sizeof(THREADENTRY32);

    // Retrieve information about the first thread,
    // and exit if unsuccessful
    if(not Thread32First(hThreadSnap, te32)) then
      RaiseLastOSError;

    // Now walk the thread list of the system,
    // and display information about each thread
    // associated with the specified process
    repeat
      if (te32.th32OwnerProcessID = dwOwnerPID) then
        ids := ids + [te32.th32ThreadID];
    until not Thread32Next(hThreadSnap, te32);
  finally
    CloseHandle(hThreadSnap);
  end;

  for thread in ids do
  begin
    Result := Result + [OpenThread(THREAD_SUSPEND_RESUME, False, thread)];
    Writeln('Main thread: ', thread, ': ', Result[0]);
    Break;
  end;
end;

procedure Inject(hProcess: HMODULE);
const
  sLoadLibrary = 'LoadLibrary' + {$IFDEF UNICODE}'W'{$ELSE}'A'{$ENDIF};
var
  hThread: THandle;
  sLibPath: string;
  szLibPath: array[0..MAX_PATH - 1] of Char;  //The name of library we want to load (including full path!)
  pLibRemote: Pointer;   // The address (in the remote process) where szLibPath will be copied to
  hLibModule: HMODULE;   // Base address of loaded module (==HMODULE);
  hKernel32: HMODULE;
  sWritten: SIZE_T;
  dwThreadId: DWORD;
  threads: TArray<THandle>;
  i: Integer;
begin
  hKernel32 := GetModuleHandle('Kernel32');
  Writeln('Kernel32 base: $' + IntToHex(hKernel32, 0));

  // initialize szLibPath
  FillChar(szLibPath, sizeof(szLibPath), 0);
  sLibPath := 'LeakCheck.Inject.dll';
  sLibPath := ExpandFileName(sLibPath);
  Writeln('DLL path: ', sLibPath);
  Move(sLibPath[1], szLibPath, (Length(sLibPath) + 1) * SizeOf(Char));

  // 1. Allocate memory in the remote process for szLibPath
  // 2. Write szLibPath to the allocated memory
  pLibRemote := VirtualAllocEx(hProcess, nil, sizeof(szLibPath), MEM_COMMIT,
    PAGE_READWRITE);
  if pLibRemote = nil then
    RaiseLastOSError;
  try
    if not WriteProcessMemory(hProcess, pLibRemote, @szLibPath[0],
      sizeof(szLibPath), sWritten) then
        RaiseLastOSError;
    Writeln('Virtual memory written');

    threads := ListThreads(hProcess);
    try
      for hThread in threads do
        i:=SuspendThread(hThread);
      // Load library into the remote process (via CreateRemoteThread & LoadLibrary)
      hThread := CreateRemoteThread(hProcess, nil, 0,
        GetProcAddress(hKernel32, sLoadLibrary), pLibRemote, 0, dwThreadId);
      if hThread = 0 then
        RaiseLastOSError;
      Writeln('Thread created');

      try
        case WaitForSingleObject(hThread, 3000) of
          WAIT_OBJECT_0: ; // Signaled
          WAIT_TIMEOUT:
          begin
            Writeln('Wait for thread timeout, forcibly resuming');
            // Resume our thread no matter what happens under the hood
            ResumeThread(hThread);
            if (WaitForSingleObject(hThread, INFINITE) <> WAIT_OBJECT_0) then
            begin
              Writeln('Thread wait error');
              Exit;
            end;
          end
          else
            Writeln('Thread wait error');
        end;

        // Get handle of the loaded module
        GetExitCodeThread(hThread, DWORD(hLibModule));
        Writeln('User module handle: ', hLibModule);
      finally
        // Clean up
        CloseHandle(hThread);
      end;
    finally
      for hThread in threads do
      begin
        ResumeThread(hThread);
        CloseHandle(hThread);
      end;
    end;
  finally
    VirtualFreeEx(hProcess, pLibRemote, sizeof(szLibPath), MEM_RELEASE);
  end;
end;

var
  hProcess: HMODULE;
begin
  try
    hProcess := OpenProcess(PROCESS_CREATE_THREAD or PROCESS_QUERY_INFORMATION
      or PROCESS_VM_OPERATION or PROCESS_VM_WRITE,
      True, StrToInt(ParamStr(1)));
    try
      Inject(hProcess);
    finally
      CloseHandle(hProcess);
    end
  except
    on E: Exception do
      Writeln('Exception ', E.ClassName, ': ', E.Message);
  end;
end.
