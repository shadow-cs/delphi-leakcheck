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

unit LeakCheck.DUnitCycle;

interface

uses
  LeakCheck,
  TestFramework,
  LeakCheck.Cycle,
  LeakCheck.DUnit;

type

  /// <summary>
  ///   In addition to detecting leaks, it also detect reference cycles in
  ///   those leaks. Must be enabled manually.
  /// </summary>
  TLeakCheckCycleMonitor = class(TLeakCheckMonitor, IDUnitMemLeakMonitor)
  strict protected
    procedure AppendCycles(var ErrorMsg: string; ASnapshot: Pointer);
  public
    function GetMemoryUseMsg(const FailOnMemoryRecovery: Boolean;
                             const TestProcChangedMem: Integer;
                             out   ErrorMsg: string): Boolean; overload;
    function GetMemoryUseMsg(const FailOnMemoryRecovery: boolean;
                             const TestSetupChangedMem: Integer;
                             const TestProcChangedMem: Integer;
                             const TestTearDownChangedMem: Integer;
                             const TestCaseChangedMem: Integer;
                             out   ErrorMsg: string): boolean; overload;
  end;

implementation

{$REGION 'TLeakCheckCycleMonitor'}

function TLeakCheckCycleMonitor.GetMemoryUseMsg(
  const FailOnMemoryRecovery: Boolean; const TestProcChangedMem: Integer;
  out ErrorMsg: string): Boolean;
var
  // Will mark any internal allocations of this functions as not a leak
  LSnapshot: Pointer;
begin
  LSnapshot := TLeakCheck.CreateSnapshot;
  Result := inherited;
  if not Result then
    AppendCycles(ErrorMsg, LSnapshot);
end;

procedure TLeakCheckCycleMonitor.AppendCycles(var ErrorMsg: string; ASnapshot: Pointer);
var
  Leaks: TLeaks;
  Leak: TLeak;
  Cycles: TCycles;
  Cycle: TCycle;
begin
  // See LSnapshot in GetMemoryUseMsg
  TLeakCheck.MarkNotLeaking(ASnapshot);
  Leaks := TLeakCheck.GetLeaks(Self.Snapshot);
  try
    for Leak in Leaks do
      if Leak.TypeKind = tkClass then
    begin
      Cycles := ScanForCycles(Leak.Data);
      for Cycle in Cycles do
        ErrorMsg := ErrorMsg + sLineBreak + Cycle.ToString;
    end;
  finally
    Leaks.Free;
  end;
end;

function TLeakCheckCycleMonitor.GetMemoryUseMsg(
  const FailOnMemoryRecovery: boolean; const TestSetupChangedMem,
  TestProcChangedMem, TestTearDownChangedMem, TestCaseChangedMem: Integer;
  out ErrorMsg: string): boolean;
var
  // Will mark any internal allocations of this functions as not a leak
  LSnapshot: Pointer;
begin
  LSnapshot := TLeakCheck.CreateSnapshot;
  Result := inherited;
  if not Result then
    AppendCycles(ErrorMsg, LSnapshot);
end;

{$ENDREGION}

end.
