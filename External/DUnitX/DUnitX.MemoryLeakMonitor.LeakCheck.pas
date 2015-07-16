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

unit DUnitX.MemoryLeakMonitor.LeakCheck;

{$I DUnitX.inc}

interface

uses
  LeakCheck,
  Rtti,
  DUnitX.TestFramework;

{$IF CompilerVersion >= 25} // >= XE4
  {$LEGACYIFEND ON}
{$IFEND}

type
  TDUnitXLeakCheckMemoryLeakMonitor = class(TInterfacedObject,IMemoryLeakMonitor
{$IF Declared(IMemoryLeakMonitor2)} // Check if newer leak monitor is available
  ,IMemoryLeakMonitor2
{$IFEND}
  )
  private class var
    FRunnerLogMessages: TRttiField;
    class function GetRunnerLogMessages: TRttiField;
  private
    FPreSetUpSnapshot: TLeakCheck.TSnapshot;
    FPreTestSnapshot: TLeakCheck.TSnapshot;
    FPreTearDownSnapshot: TLeakCheck.TSnapshot;
    FSetUpAllocated: Int64;
    FTestAllocated: Int64;
    FTearDownAllocated: Int64;
    /// <summary>
    ///   Set to true of there are any leaks detected anywhere in the test
    ///   (SetUp/Test/TearDown). If false it indicates that all allocation
    ///   functions should return zero.
    /// </summary>
    FTestLeaked: Boolean;
    FLeaksIgnored: Boolean;
    // Utility functions that are safe to use even in case of an exception
    // (not thread-safe)
    procedure BeginIgnore;
    procedure EndIgnore;
    function GetSnapshot: Pointer;
  strict protected
    property Snapshot: Pointer read GetSnapshot;
  public
    procedure AfterConstruction; override;
    destructor Destroy; override;

    procedure PreSetup;
    procedure PostSetUp;
    procedure PreTest;
    procedure PostTest;
    procedure PreTearDown;
    procedure PostTearDown;

    function SetUpMemoryAllocated: Int64;
    function TearDownMemoryAllocated: Int64;
    function TestMemoryAllocated: Int64;

    function GetReport: string; virtual;
  end;

implementation

uses
  LeakCheck.Utils,
  Classes,
  DUnitX.MemoryLeakMonitor.Default,
  DUnitX.IoC,
  DUnitX.TestRunner;

{$REGION 'TDUnitXLeakCheckMemoryLeakMonitor'}

// Basic idea is that all allocations made outside of the test object are
// considered as not leaks. Since the leak monitor is short-lived and guaranteed
// to free itself safely (since it is ref counted), we can safely disable leak
// monitoring for short period of time.

procedure TDUnitXLeakCheckMemoryLeakMonitor.AfterConstruction;
begin
  inherited;
  FPreSetUpSnapshot.Create;
  BeginIgnore;
end;

procedure TDUnitXLeakCheckMemoryLeakMonitor.BeginIgnore;
begin
  if not FLeaksIgnored then
  begin
    FLeaksIgnored := True;
    TLeakCheck.BeginIgnore;
  end;
end;

destructor TDUnitXLeakCheckMemoryLeakMonitor.Destroy;
begin
  EndIgnore;
  inherited;
end;

procedure TDUnitXLeakCheckMemoryLeakMonitor.EndIgnore;
begin
  if FLeaksIgnored then
  begin
    FLeaksIgnored := False;
    TLeakCheck.EndIgnore;
  end;
end;

function TDUnitXLeakCheckMemoryLeakMonitor.GetReport: string;
var
  Report: LeakString;
begin
  Report := TLeakCheck.GetReport(Snapshot);
  // Report is ASCII so it can be easily treated as UTF-8
  Result := sLineBreak + UTF8ToString(Report);
  Report.Free;
end;

class function TDUnitXLeakCheckMemoryLeakMonitor.GetRunnerLogMessages: TRttiField;

  procedure InitLogMessages;
  var
    Ctx: TRttiContext;
  begin
    Ctx := TRttiContext.Create;
    FRunnerLogMessages := Ctx.GetType(TDUnitXTestRunner).GetField('FLogMessages');
  end;

begin
  if not Assigned(FRunnerLogMessages) then
    InitLogMessages;
  Result := FRunnerLogMessages;
end;

function TDUnitXLeakCheckMemoryLeakMonitor.GetSnapshot: Pointer;
begin
  Result := FPreSetUpSnapshot.Snapshot;
end;

procedure TDUnitXLeakCheckMemoryLeakMonitor.PostSetUp;
begin
  FSetUpAllocated := FPreSetUpSnapshot.LeakSize;
  BeginIgnore;
end;

procedure TDUnitXLeakCheckMemoryLeakMonitor.PostTearDown;
begin
  FTearDownAllocated := FPreTearDownSnapshot.LeakSize;
  BeginIgnore;
end;

procedure TDUnitXLeakCheckMemoryLeakMonitor.PostTest;
begin
  FTestAllocated := FPreTestSnapshot.LeakSize;
  BeginIgnore;
end;

procedure TDUnitXLeakCheckMemoryLeakMonitor.PreSetup;
begin
  System.Assert(Assigned(FPreSetUpSnapshot.Snapshot));
  EndIgnore;
end;

procedure TDUnitXLeakCheckMemoryLeakMonitor.PreTearDown;
begin
  FPreTearDownSnapshot.Create;
  EndIgnore;
end;

procedure TDUnitXLeakCheckMemoryLeakMonitor.PreTest;
begin
  FPreTestSnapshot.Create;
  EndIgnore;
end;

function TDUnitXLeakCheckMemoryLeakMonitor.SetUpMemoryAllocated: Int64;
var
  Runner: TObject;
begin
  Runner := TDUnitX.CurrentRunner as TObject;
  if Runner is TDUnitXTestRunner then
  begin
    // Fixes issues that made DUnitX disable leak checking in commit 4d2f444.
    IgnoreStrings(GetRunnerLogMessages.GetValue(Runner).AsObject as TStrings);
  end;
  // Evaluate here as this is the first function guaranteed to run during leak
  // evaluation.
  FTestLeaked := FPreSetUpSnapshot.LeakSize > 0;
{$IFOPT C+}
  if FTestLeaked then
    System.Assert(FSetUpAllocated + FTestAllocated + FTearDownAllocated > 0);
  // else summation may be not zero since we do not support negative leak size
{$ENDIF}

  // If there are no leaks after teardown the test was OK
  if not FTestLeaked then
    Exit(0);

  Result := FSetUpAllocated;
end;

function TDUnitXLeakCheckMemoryLeakMonitor.TearDownMemoryAllocated: Int64;
begin
  // If there are no leaks after teardown the test was OK
  if not FTestLeaked then
    Exit(0);

  Result := FTearDownAllocated;
end;

function TDUnitXLeakCheckMemoryLeakMonitor.TestMemoryAllocated: Int64;
begin
  // If there are no leaks after teardown the test was OK
  if not FTestLeaked then
    Exit(0);

  Result := FTestAllocated;
end;

{$ENDREGION}

procedure Inititalize;
begin
  TDUnitXIoC.DefaultContainer.RegisterType<IMemoryLeakMonitor>(
    function : IMemoryLeakMonitor
    begin
      result := TDUnitXLeakCheckMemoryLeakMonitor.Create;
    end);
end;

initialization
  Inititalize;

end.

