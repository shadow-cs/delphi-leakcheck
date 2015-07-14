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

unit LeakCheck.TestDUnitX;

interface

uses
  LeakCheck,
  SysUtils,
  DUnitX.TestFramework,
  DUnitX.Attributes;

type
  {$M+}
  TTestLeaks = class
  published
    procedure TestNoLeaks;
    procedure TestWithLeaks;
  end;

  TTestSetup = class
  protected
    FObj: Pointer;
  public
    [SetUp]
    procedure SetUp;
  published
    procedure TestReleased;
    procedure TestNotReleased;
  end;

  TTestTeardown = class
  protected
    FObj: Pointer;
  public
    [TearDown]
    procedure TearDown;
  published
    procedure TestReleased;
  end;

  TTestTeardownThatLeaks = class
  public
    [TearDown]
    procedure TearDown;
  published
    procedure TestNotReleased;
  end;

  TTestExceptionDisablesLeakIgnoreBase = class
  public
    destructor Destroy; override;

  end;

  TTestExceptionDisablesLeakIgnore = class(TTestExceptionDisablesLeakIgnoreBase)
  published
    procedure Test;
  end;

  TTestSetUpExceptionDisablesLeakIgnore = class(TTestExceptionDisablesLeakIgnoreBase)
  public
    [SetUp]
    procedure SetUp;
  published
    procedure Test;
  end;

  TTestTearDownExceptionDisablesLeakIgnore = class(TTestExceptionDisablesLeakIgnoreBase)
  public
    [TearDown]
    procedure TearDown;
  published
    procedure Test;
  end;

  TTestStatusDoesNotLeak = class
  published
    procedure TestStatus;
  end;

implementation

uses
  LeakCheck.Utils,
  TypInfo,
  Rtti;

{$ASSERTIONS ON}

var
  KnownLeaks: TArray<Pointer>;

procedure AddKnownLeak(Leak: Pointer);
var
  Len: Integer;
begin
  Len := Length(KnownLeaks);
  SetLength(KnownLeaks, Len + 1);
  KnownLeaks[Len] := Leak;
  IgnoreDynamicArray(KnownLeaks);
end;

{ TTestLeaks }

procedure TTestLeaks.TestNoLeaks;
begin
  TObject.Create{$IFNDEF AUTOREFCOUNT}.Free{$ENDIF};
  Assert.Pass;
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
  Assert.Pass;
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
  Assert.Pass;
end;

procedure TTestSetup.TestReleased;
begin
  TObject(FObj).Free;
  Assert.Pass;
end;

procedure TTestTeardown.TearDown;
begin
  inherited;
  TObject(FObj).Free;
end;

procedure TTestTeardown.TestReleased;
begin
  TObject(FObj) := TObject.Create;
  Assert.Pass;
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
  Assert.Pass;
end;

{ TTestStatusDoesNotLeak }

procedure TTestStatusDoesNotLeak.TestStatus;
var
  s: string;
begin
  s := 'This is a status test';
  UniqueString(s); // Make this a dynamic text
  with TDUnitX.CurrentRunner do
    Status(s);
  Assert.Pass;
end;

{ TTestExceptionDisablesLeakIgnoreBase }

destructor TTestExceptionDisablesLeakIgnoreBase.Destroy;
var
  Snapshot: TLeakCheck.TSnapshot;
  s: string;
begin
  Snapshot.Create;
  SetLength(s, 1);
  System.Assert(Snapshot.LeakSize > 0);
  s:='';
  inherited;
end;

{ TTestExceptionDisablesLeakIgnore }

procedure TTestExceptionDisablesLeakIgnore.Test;
begin
  Abort;
end;

{ TTestSetUpExceptionDisablesLeakIgnore }

procedure TTestSetUpExceptionDisablesLeakIgnore.SetUp;
begin
  Abort;
end;

procedure TTestSetUpExceptionDisablesLeakIgnore.Test;
begin

end;

{ TTestTearDownExceptionDisablesLeakIgnore }

procedure TTestTearDownExceptionDisablesLeakIgnore.TearDown;
begin
  Abort;
end;

procedure TTestTearDownExceptionDisablesLeakIgnore.Test;
begin

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

initialization
  TDUnitX.RegisterTestFixture(TTestLeaks);
  TDUnitX.RegisterTestFixture(TTestSetup);
  TDUnitX.RegisterTestFixture(TTestTeardown);
  TDUnitX.RegisterTestFixture(TTestTeardownThatLeaks);
  TDUnitX.RegisterTestFixture(TTestExceptionDisablesLeakIgnore);
  TDUnitX.RegisterTestFixture(TTestSetUpExceptionDisablesLeakIgnore);
  TDUnitX.RegisterTestFixture(TTestTearDownExceptionDisablesLeakIgnore);
  TDUnitX.RegisterTestFixture(TTestStatusDoesNotLeak);

finalization
  FinalizeLeaks;

end.
