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

{$I LeakCheck.inc}

interface

uses
  LeakCheck,
  SysUtils,
  TypInfo,
  TestFramework,
  LeakCheck.Cycle,
  LeakCheck.DUnit;

type
  /// <summary>
  ///   In addition to detecting leaks, it also detect reference cycles in
  ///   those leaks. Must be enabled manually.
  /// </summary>
  TLeakCheckCycleMonitor = class(TLeakCheckMonitor, IDUnitMemLeakMonitor)
  strict private class var
    FUseExtendedRtti: Boolean;
    FOnInstanceIgnored: TScanner.TIsInstanceIgnored;
  strict protected
    FFormat: TCycle.TCycleFormats;
    ScanProc: function(const Instance: TObject; Flags: TScanFlags;
      InstanceIgnoreProc: TScanner.TIsInstanceIgnored): TCycles;
    procedure AppendCycles(var ErrorMsg: string; ASnapshot: Pointer);
  public
    procedure AfterConstruction; override;
    function GetMemoryUseMsg(const FailOnMemoryRecovery: Boolean;
                             const TestProcChangedMem: Integer;
                             out   ErrorMsg: string): Boolean; overload;
    function GetMemoryUseMsg(const FailOnMemoryRecovery: boolean;
                             const TestSetupChangedMem: Integer;
                             const TestProcChangedMem: Integer;
                             const TestTearDownChangedMem: Integer;
                             const TestCaseChangedMem: Integer;
                             out   ErrorMsg: string): boolean; overload;
    class property UseExtendedRtti: Boolean read FUseExtendedRtti write FUseExtendedRtti;
    class property OnInstanceIgnored: TScanner.TIsInstanceIgnored read FOnInstanceIgnored write FOnInstanceIgnored;
  end;

  /// <summary>
  ///   Extends <see cref="LeakCheck.DUnitCycle|TLeakCheckCycleMonitor" />
  ///   functionality by outputing Graphviz DOT compatible format that can be
  ///   converted to graphical representation.
  /// </summary>
  TLeakCheckCycleGraphMonitor = class(TLeakCheckCycleMonitor)
  public
    procedure AfterConstruction; override;
  end;

  /// <summary>
  ///   Extends <see cref="LeakCheck.DUnitCycle|TLeakCheckCycleMonitor" />
  ///   functionality by outputing Graphviz DOT compatible format that can be
  ///   converted to graphical representation. But instead of scanning just for
  ///   cycles, it outputs the entire object structure tree. Warning: it can be
  ///   a lot of data.
  /// </summary>
  TLeakCheckGraphMonitor = class(TLeakCheckCycleMonitor)
  public
    procedure AfterConstruction; override;
  end;

implementation

{$REGION 'TLeakCheckCycleMonitor'}

function TLeakCheckCycleMonitor.GetMemoryUseMsg(
  const FailOnMemoryRecovery: Boolean; const TestProcChangedMem: Integer;
  out ErrorMsg: string): Boolean;
var
  // Will mark any internal allocations of this functions as not a leak
  LSnapshot: TLeakCheck.TSnapshot;
begin
  LSnapshot.Create;
  Result := inherited;
  if not Result then
    AppendCycles(ErrorMsg, LSnapshot.Snapshot);
end;

procedure TLeakCheckCycleMonitor.AfterConstruction;
begin
  inherited;
  ScanProc := ScanForCycles;
  // It is always useful but only supported with extended RTTI and not appended
  // otherwise.
  FFormat := [TCycleFormat.WithField];
end;

procedure TLeakCheckCycleMonitor.AppendCycles(var ErrorMsg: string; ASnapshot: Pointer);
var
  Leaks: TLeaks;
  Leak: TLeak;
  Cycles: TCycles;
  Flags: TScanFlags;
  Formatter: TCyclesFormatter;
begin
  Formatter := TCyclesFormatter.Create(FFormat);
  // See LSnapshot in GetMemoryUseMsg
  TLeakCheck.MarkNotLeaking(ASnapshot);

  Flags := [];
  if UseExtendedRtti then
    Include(Flags, TScanFlag.UseExtendedRtti);

  Leaks := TLeakCheck.GetLeaks(Self.Snapshot);
  try
    for Leak in Leaks do
      if Leak.TypeKind = LeakCheck.tkClass then
    begin
      Cycles := ScanProc(Leak.Data, Flags, OnInstanceIgnored);
      Formatter.Append(Cycles);
    end;
  finally
    Leaks.Free;
  end;

  ErrorMsg := ErrorMsg + sLineBreak + Formatter.ToString;
end;

function TLeakCheckCycleMonitor.GetMemoryUseMsg(
  const FailOnMemoryRecovery: boolean; const TestSetupChangedMem,
  TestProcChangedMem, TestTearDownChangedMem, TestCaseChangedMem: Integer;
  out ErrorMsg: string): boolean;
var
  // Will mark any internal allocations of this functions as not a leak
  LSnapshot: TLeakCheck.TSnapshot;
begin
  LSnapshot.Create;
  Result := inherited;
  if not Result then
    AppendCycles(ErrorMsg, LSnapshot.Snapshot);
end;

{$ENDREGION}

{$REGION 'TLeakCheckCycleGraphMonitor'}

procedure TLeakCheckCycleGraphMonitor.AfterConstruction;
begin
  inherited;
  FFormat := [TCycleFormat.Graphviz, TCycleFormat.WithAddress,
    TCycleFormat.WithField];
end;

{$ENDREGION}

{$REGION 'TLeakCheckGraphMonitor'}

procedure TLeakCheckGraphMonitor.AfterConstruction;
begin
  inherited;
  FFormat := TCyclesFormatter.CompleteGraph;
  ScanProc := ScanGraph;
end;

{$ENDREGION}

end.
