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

unit LeakCheck.TestDUnit;

interface

uses
  SysUtils,
  Rtti,
  TestFramework;

type
  TLeakCheckConfiguration = record
  private
    {$I ..\..\Source\LeakCheck.Configuration.inc}
  end;

  TTestLeaks = class(TTestCase)
  published
    procedure TestNoLeaks;
    procedure TestWithLeaks;
  end;

  TTestSetup = class(TTestCase)
  protected
    FObj: Pointer;
    procedure SetUp; override;
  published
    procedure TestReleased;
    procedure TestNotReleased;
  end;

  TTestTeardown = class(TTestCase)
  protected
    FObj: Pointer;
    procedure TearDown; override;
  published
    procedure TestReleased;
  end;

  TTestTeardownThatLeaks = class(TTestCase)
  protected
    procedure TearDown; override;
  published
    procedure TestNotReleased;
  end;

  TTestStatusDoesNotLeak = class(TTestCase)
  published
    procedure TestStatus;
  end;

  TTestIgnoreTValue = class(TTestCase)
  published
    procedure TestCallsIgnoreForObject;
    procedure TestDoesNotCallIgnoreForNonObject;
  end;

  TTestIgnoreTMonitor = class(TTestCase)
  published
    procedure TestIgnoreTMonitor;
  end;

  TTestCorruptionDetection = class(TTestCase)
  private
    procedure CheckAV(Offset: NativeInt);
  published
    procedure TestFooter;
    procedure TestSeparator;
  end;

implementation

uses
  LeakCheck,
  LeakCheck.Utils;

var
  KnownLeaks: TArray<Pointer>;

type
  TTestCaseHelper = class helper for TTestCase
    procedure AddKnownLeak(Leak: Pointer);
  end;

procedure TTestCaseHelper.AddKnownLeak(Leak: Pointer);
var
  Len: Integer;
begin
  Status('This test will fail due to memory leak which is expected');
  TLeakCheck.BeginIgnore;
  Len := Length(KnownLeaks);
  SetLength(KnownLeaks, Len + 1);
  KnownLeaks[Len] := Leak;
  TLeakCheck.EndIgnore;
end;

{ TTestLeaks }

procedure TTestLeaks.TestNoLeaks;
begin
  TObject.Create{$IFNDEF AUTOREFCOUNT}.Free{$ENDIF};
  Check(True);
end;

procedure TTestLeaks.TestWithLeaks;
var
  O: Pointer;
begin
{$IFDEF AUTOREFCOUNT}
  O := nil;
{$ENDIF}
  TObject(O) := TObject.Create;
  AddKnownLeak(O);
  Check(True);
end;

{ TTestSetup }

procedure TTestSetup.SetUp;
begin
  inherited;
  TObject(FObj) := TObject.Create;
end;

procedure TTestSetup.TestNotReleased;
begin
  AddKnownLeak(FObj);
  Check(True);
end;

procedure TTestSetup.TestReleased;
begin
  TObject(FObj).Free;
  Check(True);
end;

{ TTestTeardown }

procedure TTestTeardown.TearDown;
begin
  inherited;
  TObject(FObj).Free;
end;

procedure TTestTeardown.TestReleased;
begin
  TObject(FObj) := TObject.Create;
  Check(True);
end;

{ TTestTeardownThatLeaks }

procedure TTestTeardownThatLeaks.TearDown;
var
  O: Pointer;
begin
  inherited;
{$IFDEF AUTOREFCOUNT}
  O := nil;
{$ENDIF}
  TObject(O) := TObject.Create;
  AddKnownLeak(O);
end;

procedure TTestTeardownThatLeaks.TestNotReleased;
begin
  Check(True);
end;

procedure FinalizeLeaks;
var
  O: Pointer;
begin
  for O in KnownLeaks do
{$IFNDEF AUTOREFCOUNT}
    TObject(O).Free;
{$ELSE}
    TObject(O).__ObjRelease;
{$ENDIF}
  Finalize(KnownLeaks);
end;

{ TTestStatusDoesNotLeak }

procedure TTestStatusDoesNotLeak.TestStatus;
var
  s: string;
begin
  s := 'This is a status test';
  UniqueString(s); // Make this a dynamic text
  Status(s);
  Check(True);
end;

type
  TValueDataImpl = class(TInterfacedObject, IValueData)
  private class var
    Dummy: Pointer;
  private
    FIsObject: Boolean;
  public
    function GetDataSize: Integer;
    procedure ExtractRawData(ABuffer: Pointer);
    procedure ExtractRawDataNoCopy(ABuffer: Pointer);
    function GetReferenceToRawData: Pointer;
    constructor Create(IsObject: Boolean);
    function QueryInterface(const IID: TGUID; out Obj): HRESULT; stdcall;
  end;

{ TValueDataImpl }

constructor TValueDataImpl.Create(IsObject: Boolean);
begin
  inherited Create;
  FIsObject := IsObject;
end;

procedure TValueDataImpl.ExtractRawData(ABuffer: Pointer);
begin

end;

procedure TValueDataImpl.ExtractRawDataNoCopy(ABuffer: Pointer);
begin

end;

function TValueDataImpl.GetDataSize: Integer;
begin
  Result := 0;
end;

function TValueDataImpl.GetReferenceToRawData: Pointer;
begin
  Result := @Dummy;
end;

function TValueDataImpl.QueryInterface(const IID: TGUID; out Obj): HRESULT;
begin
  if FIsObject then
    Result := inherited
  else
    Result := 1;
end;

{ TTestIgnoreTValue }

procedure TTestIgnoreTValue.TestCallsIgnoreForObject;
var
  Snapshot: TLeakCheck.TSnapshot;
  Value: Rtti.TValueData;
begin
  Snapshot.Create;
  Value.FTypeInfo := TypeInfo(TObject);
  Value.FValueData := TValueDataImpl.Create(True);
  IgnoreTValue(@Value);
  CheckEquals(0, Snapshot.LeakSize);
end;

procedure TTestIgnoreTValue.TestDoesNotCallIgnoreForNonObject;
var
  Snapshot: TLeakCheck.TSnapshot;
  Value: Rtti.TValueData;
begin
  Snapshot.Create;
  Value.FValueData := TValueDataImpl.Create(False);
  IgnoreTValue(@Value);
  CheckEquals(TValueDataImpl.InstanceSize, Snapshot.LeakSize);
end;

{ TTestIgnoreTMonitor }

procedure TTestIgnoreTMonitor.TestIgnoreTMonitor;
var
  Inst: TObject;
begin
  Inst := TObject.Create;
  TMonitor.Enter(Inst);
  TMonitor.Exit(Inst);
  AddKnownLeak(Inst);
  RegisterExpectedMemoryLeak(Inst);
  IgnoreAllManagedFields(Inst, TObject);
  Pointer(Inst) := nil;
  Check(true);
end;

{ TTestCorruptionDetection }

procedure TTestCorruptionDetection.CheckAV(Offset: NativeInt);
var
  Data: PByte;
begin
  GetMem(Data, 1);
  (Data + Offset)^ := $AA;
  try
    FreeMem(Data);
    Check(False, 'EAccessViolation expected');
  except
    on EAccessViolation do
      Check(True);
    else Check(False, 'EAccessViolation expected, got different');
  end;
end;

procedure TTestCorruptionDetection.TestFooter;
begin
{$IF TLeakCheckConfiguration.FooterSize > 0}
  CheckAV(1);
  CheckAV(TLeakCheckConfiguration.FooterSize * SizeOf(Pointer));
{$IFEND}
end;

procedure TTestCorruptionDetection.TestSeparator;
begin
{$IF TLeakCheckConfiguration.SeparatorSize > 0}
  CheckAV(-1);
  CheckAV(-TLeakCheckConfiguration.SeparatorSize * SizeOf(Pointer));
{$IFEND}
end;

initialization
  RegisterTests([
    TTestLeaks.Suite,
    TTestSetup.Suite,
    TTestTeardown.Suite,
    TTestTeardownThatLeaks.Suite,
    TTestStatusDoesNotLeak.Suite,
    TTestIgnoreTValue.Suite,
    TTestIgnoreTMonitor.Suite,
    TTestCorruptionDetection.Suite
  ]);

finalization
  FinalizeLeaks;
end.
