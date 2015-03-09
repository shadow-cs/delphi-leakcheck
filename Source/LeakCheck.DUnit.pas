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

unit LeakCheck.DUnit;

interface

uses
  LeakCheck,
  System.SysUtils,
  TestFramework;

type
  TLeakCheckMonitor = class(TInterfacedObject, IMemLeakMonitor, IDUnitMemLeakMonitor)
  private

    /// <summary>
    ///   Asserts that snapshot is valid as long as it is needed (not thread
    ///   safe).
    /// </summary>
    FSnapshotAsserter: IInterface;
    FSnapshot: Pointer;
  private
    function LeakDetail(TempSnapshot: Pointer): string;
  public
    procedure AfterConstruction; override;

    // IMemLeakMonitor
    function MemLeakDetected(out LeakSize: Integer): Boolean; overload;

    // IDUnitMemLeakMonitor
    function MemLeakDetected(const AllowedLeakSize: Integer;
                             const FailOnMemoryRecovery: Boolean;
                             out   LeakSize: Integer): Boolean; overload;
    function MemLeakDetected(const AllowedValuesGetter: TListIterator;
                             const FailOnMemoryRecovery: Boolean;
                             out   LeakIndex: integer;
                             out   LeakSize: Integer): Boolean; overload;
    function GetMemoryUseMsg(const FailOnMemoryRecovery: Boolean;
                             const TestProcChangedMem: Integer;
                             out   ErrorMsg: string): Boolean; overload;
    function GetMemoryUseMsg(const FailOnMemoryRecovery: boolean;
                             const TestSetupChangedMem: Integer;
                             const TestProcChangedMem: Integer;
                             const TestTearDownChangedMem: Integer;
                             const TestCaseChangedMem: Integer;
                             out   ErrorMsg: string): boolean; overload;
    procedure MarkMemInUse;
    procedure TestMethodDone(const Test: ITest);
  end;

implementation

uses
  LeakCheck.Utils;

{ TLeakCheckMonitor }

function TLeakCheckMonitor.GetMemoryUseMsg(const FailOnMemoryRecovery: Boolean;
  const TestProcChangedMem: Integer; out ErrorMsg: string): Boolean;
begin
  ErrorMsg := '';

  if TestProcChangedMem > 0 then
    ErrorMsg := IntToStr(TestProcChangedMem) +
      ' Bytes Memory Leak in Test Procedure'
  else
  if (TestProcChangedMem  < 0) and (FailOnMemoryRecovery) then
    ErrorMsg := IntToStr(Abs(TestProcChangedMem)) +
     ' Bytes Memory Recovered in Test Procedure';

  Result := Length(ErrorMsg) = 0;
end;

procedure TLeakCheckMonitor.AfterConstruction;
begin
  inherited;
  MarkMemInUse;
end;

function TLeakCheckMonitor.LeakDetail(TempSnapshot: Pointer): string;
var
  Report: LeakString;
begin
  // See Snapshot in GetMemoryUseMsg
  TLeakCheck.MarkNotLeaking(TempSnapshot);
  Report := TLeakCheck.GetReport(FSnapshot);
  // Report is ASCII so it can be easily treated as UTF-8
  Result := sLineBreak + UTF8ToString(Report);
  Report.Free;
end;

function TLeakCheckMonitor.GetMemoryUseMsg(const FailOnMemoryRecovery: boolean;
  const TestSetupChangedMem, TestProcChangedMem, TestTearDownChangedMem,
  TestCaseChangedMem: Integer; out ErrorMsg: string): boolean;
var
  // Will mark any internal allocations of this functions as not a leak
  Snapshot: Pointer;
  Location: string;
begin
  Result := False;
  ErrorMsg := '';
  Snapshot := TLeakCheck.CreateSnapshot;

  if (TestSetupChangedMem = 0) and (TestProcChangedMem = 0) and
     (TestTearDownChangedMem = 0) and (TestCaseChangedMem <> 0) then
  begin
    ErrorMsg :=
      'Test leaked memory. No leaks in Setup, TestProc or Teardown but '+
      IntToStr(TestCaseChangedMem) +
      ' Bytes Memory Leak reported across TestCase' + LeakDetail(Snapshot);
    Exit;
  end;

  if (TestSetupChangedMem + TestProcChangedMem + TestTearDownChangedMem) <>
    TestCaseChangedMem then
  begin
    ErrorMsg :=
      'Test leaked memory. Sum of Setup, TestProc and Teardown leaks <> '+
      IntToStr(TestCaseChangedMem) +
      ' Bytes Memory Leak reported across TestCase' + LeakDetail(Snapshot);
    Exit;
  end;

  Result := True;
  if TestCaseChangedMem = 0 then
    Exit; // Don't waste further time here

  if (TestCaseChangedMem < 0) and not FailOnMemoryRecovery then
    Exit; // Don't waste further time here


  // We get to here because there is a memory use imbalance to report.
  if (TestCaseChangedMem > 0) then
    ErrorMsg := IntToStr(TestCaseChangedMem) + ' Bytes memory leak  ('
  else
    ErrorMsg := IntToStr(TestCaseChangedMem) + ' Bytes memory recovered  (';

  Location := '';

  if (TestSetupChangedMem <> 0) then
    Location := 'Setup= ' + IntToStr(TestSetupChangedMem) + '  ';
  if (TestProcChangedMem <> 0) then
    Location := Location + 'TestProc= ' + IntToStr(TestProcChangedMem) + '  ';
  if (TestTearDownChangedMem <> 0) then
    Location := Location + 'TearDown= ' + IntToStr(TestTearDownChangedMem) + '  ';

  ErrorMsg := ErrorMsg + Location + ')' + LeakDetail(Snapshot);
  Result := (Length(ErrorMsg) = 0);
end;

procedure TLeakCheckMonitor.MarkMemInUse;
begin
  FSnapshotAsserter := TInterfacedObject.Create;
  FSnapshot := TLeakCheck.CreateSnapshot;
  // Make sure our asserter is not marked as a leak
  TLeakCheck.MarkNotLeaking(FSnapshot);
end;

function TLeakCheckMonitor.MemLeakDetected(out LeakSize: Integer): Boolean;
var
  Leaks: TLeaks;
begin
  Leaks := TLeakCheck.GetLeaks(FSnapshot);
  Result := Leaks.Length > 0;
  LeakSize := Leaks.TotalSize;
  Leaks.Free;
end;

function TLeakCheckMonitor.MemLeakDetected(const AllowedLeakSize: Integer;
  const FailOnMemoryRecovery: Boolean; out LeakSize: Integer): Boolean;
begin
  LeakSize := 0;
  MemLeakDetected(LeakSize);
  Result := ((LeakSize > 0) and (LeakSize <> AllowedLeakSize)) or
    ((LeakSize < 0) and (FailOnMemoryRecovery) and (LeakSize <> AllowedLeakSize));
end;

function TLeakCheckMonitor.MemLeakDetected(
  const AllowedValuesGetter: TListIterator; const FailOnMemoryRecovery: Boolean;
  out LeakIndex, LeakSize: Integer): Boolean;
var
  AllowedLeakSize: Integer;
begin
  LeakIndex := 0;
  LeakSize  := 0;
  Result := False;
  MemLeakDetected(LeakSize);

  if LeakSize = 0 then
    Exit;

  // Next line access value stored via SetAllowedLeakSize, if any
  if LeakSize = AllowedValuesGetter then
    Exit;

  // Loop over values stored via SetAllowedLeakArray
  repeat
    Inc(LeakIndex);
    AllowedLeakSize := AllowedValuesGetter;
    if (LeakSize = AllowedLeakSize) then
      Exit;
  until AllowedLeakSize = 0;

  Result := (LeakSize > 0) or ((LeakSize < 0) and FailOnMemoryRecovery);
end;

type
  TAbstractTestAccess = class(TAbstractTest);

procedure TLeakCheckMonitor.TestMethodDone(const Test: ITest);
var
  AbstractTest: TAbstractTestAccess;
begin
  if Test is TAbstractTest then
  begin
    AbstractTest := TAbstractTestAccess(Test as TObject);
    if Assigned(AbstractTest.FStatusStrings) then
      IgnoreStrings(AbstractTest.FStatusStrings);
  end;
end;

initialization
  TestFramework.MemLeakMonitorClass := TLeakCheckMonitor;

end.
