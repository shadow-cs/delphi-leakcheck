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

unit LeakCheck.TestCycle;

interface

uses
  SysUtils,
  StrUtils,
  TypInfo,
  Rtti,
  Generics.Collections,
  LeakCheck.Cycle,
  TestFramework;

type
  TTestCycle = class(TTestCase)
  private
    FResult: TCycles;
  protected
    procedure TearDown; override;
  published
    procedure TestOwnsSelf;
    procedure TestOwnsOtherThenSelf;
    procedure TestOwnsSelfInArray;
    procedure TestOwnsSelfInDynArray;
    procedure TestOwnsSelfInRecord;
    procedure TestOwnsSelfInTValue;
    procedure TestOwnsSelfInTValueAndArray;
    procedure TestOwnsSelfInTValueAndInterface;
    procedure TestOwnsSelfInTList;
    procedure TestToString;
    procedure TestAnonymousMethodClosure;
{$IFDEF AUTOREFCOUNT}
    procedure TestOwnsSelfObject;
{$ENDIF}
  end;

  TTestLeaksWithACycle = class(TTestCase)
  published
    procedure TestCycle;
  end;

type
  TArray2OfIInterface = array[0..1] of IInterface;
  TRecordWithIInterface = record
    s: string;
    FIntf: IInterface;
  end;

  TOwner<T> = class(TInterfacedObject)
  public
    F: T;
  end;

  TOwnsInterface = class(TOwner<IInterface>);
  TOwnsArrayInterface = class(TOwner<TArray2OfIInterface>);
  TOwnsDynArrayInterface = class(TOwner<TArray<IInterface>>);
  TOwnsRecordWithInterface = class(TOwner<TRecordWithIInterface>);
  TOwnsTValue = class(TOwner<TValue>);
  TOwnsRefToProc = class(TOwner<TProc>);
  TOwnsObject = class(TOwner<TObject>);

implementation

uses LeakCheck.Utils;

var
  TheLeak: TOwnsInterface = nil;

{$REGION 'TTestCycle'}

procedure TTestCycle.TearDown;
begin
  inherited;
  FResult := Default(TCycles);
end;

procedure TTestCycle.TestAnonymousMethodClosure;
const
  PathStart = 'TOwnsRefToProc -> TProc -> TTestCycle.TestAnonymousMethodClosure$';
  PathEnd = '$ActRec -> IInterface -> TOwnsRefToProc';
var
  inst: TOwnsRefToProc;
  intf: IInterface;
  s: string;
begin
  inst := TOwnsRefToProc.Create;
  intf := inst;
  inst.F := procedure
    begin
      intf._Release;
    end;
  try
    FResult := ScanForCycles(inst);
    CheckEquals(1, Length(FResult));
    s := FResult[0].ToString;
    CheckEquals(4, FResult[0].Length, s);
    CheckTrue(FResult[0][0].TypeInfo = inst.ClassInfo, s);
    CheckTrue(FResult[0][3].TypeInfo = TypeInfo(IInterface), s);
    CheckTrue(StartsStr(PathStart, s), PathStart + PathEnd + ' vs ' + s);
    CheckTrue(EndsStr(PathEnd, s), PathStart + PathEnd + ' vs ' + s);
  finally
    inst.F := nil;
  end;
end;

procedure TTestCycle.TestOwnsOtherThenSelf;
var
  inst1: TOwnsInterface;
  inst2: TOwnsInterface;
  s: string;
begin
  inst1 := TOwnsInterface.Create;
  inst2 := TOwnsInterface.Create;
  inst1.F := inst2;
  inst2.F := inst1;
  try
    FResult := ScanForCycles(inst1);
    CheckEquals(1, Length(FResult));
    s := FResult[0].ToString;
    CheckEquals(4, FResult[0].Length, s);
    CheckTrue(FResult[0][0].TypeInfo = inst1.ClassInfo, s);
    CheckTrue(FResult[0][1].TypeInfo = TypeInfo(IInterface), s);
    CheckTrue(FResult[0][2].TypeInfo = inst1.ClassInfo, s);
    CheckTrue(FResult[0][3].TypeInfo = TypeInfo(IInterface), s);
  finally
    inst1.F := nil;
  end;
end;

procedure TTestCycle.TestOwnsSelf;
var
  inst: TOwnsInterface;
  s: string;
begin
  inst := TOwnsInterface.Create;
  inst.F := inst;
  try
    FResult := ScanForCycles(inst);
    CheckEquals(1, Length(FResult));
    s := FResult[0].ToString;
    CheckEquals(2, FResult[0].Length, s);
    CheckTrue(FResult[0][0].TypeInfo = inst.ClassInfo, s);
    CheckTrue(FResult[0][1].TypeInfo = TypeInfo(IInterface), s);
  finally
    inst.F := nil;
  end;
end;

procedure TTestCycle.TestOwnsSelfInArray;
var
  inst: TOwnsArrayInterface;
  s: string;
begin
  inst := TOwnsArrayInterface.Create;
  inst.F[1] := inst;
  try
    FResult := ScanForCycles(inst);
    CheckEquals(1, Length(FResult));
    s := FResult[0].ToString;
    CheckEquals(3, FResult[0].Length, s);
    CheckTrue(FResult[0][0].TypeInfo = inst.ClassInfo, s);
    CheckTrue(FResult[0][1].TypeInfo = TypeInfo(TArray2OfIInterface), s);
    CheckTrue(FResult[0][2].TypeInfo = TypeInfo(IInterface), s);
  finally
    inst.F[1] := nil;
  end;
end;

procedure TTestCycle.TestOwnsSelfInDynArray;
var
  inst: TOwnsDynArrayInterface;
  s: string;
begin
  inst := TOwnsDynArrayInterface.Create;
  SetLength(inst.F, 2);
  inst.F[1] := inst;
  try
    FResult := ScanForCycles(inst);
    CheckEquals(1, Length(FResult));
    s := FResult[0].ToString;
    CheckEquals(3, FResult[0].Length, s);
    CheckTrue(FResult[0][0].TypeInfo = inst.ClassInfo, s);
    CheckTrue(FResult[0][1].TypeInfo = TypeInfo(TArray<IInterface>), s);
    CheckTrue(FResult[0][2].TypeInfo = TypeInfo(IInterface), s);
  finally
    inst.F := nil;
  end;
end;

procedure TTestCycle.TestOwnsSelfInRecord;
var
  inst: TOwnsRecordWithInterface;
  s: string;
begin
  inst := TOwnsRecordWithInterface.Create;
  inst.F.FIntf := inst;
  try
    FResult := ScanForCycles(inst);
    CheckEquals(1, Length(FResult));
    s := FResult[0].ToString;
    CheckEquals(3, FResult[0].Length, s);
    CheckTrue(FResult[0][0].TypeInfo = inst.ClassInfo, s);
    CheckTrue(FResult[0][1].TypeInfo = TypeInfo(TRecordWithIInterface), s);
    CheckTrue(FResult[0][2].TypeInfo = TypeInfo(IInterface), s);
  finally
    inst.F.FIntf := nil;
  end;
end;

procedure TTestCycle.TestOwnsSelfInTList;
var
  inst: TOwnsTValue;
  list: TList<IInterface>;
  s: string;
begin
  // We have to use TValue to make it work on non-ARC
  inst := TOwnsTValue.Create;
  list := TList<IInterface>.Create;
  inst.F := list;
  try
    list.Add(nil);
    list.Add(inst);
    FResult := ScanForCycles(inst);
    CheckEquals(1, Length(FResult));
    s := FResult[0].ToString;
    CheckEquals(6, FResult[0].Length, s);
    CheckTrue(FResult[0][0].TypeInfo = inst.ClassInfo, s);
    CheckTrue(FResult[0][1].TypeInfo = TypeInfo(TValue), s);

    // Type duplicated see ScanTValue
    CheckTrue(FResult[0][2].TypeInfo = list.ClassInfo, s);
    CheckTrue(FResult[0][3].TypeInfo = list.ClassInfo, s);

    CheckTrue(FResult[0][4].TypeInfo^.Kind = tkDynArray, s);
    CheckTrue(FResult[0][5].TypeInfo = TypeInfo(IInterface), s);
  finally
    inst.F := TValue.Empty;
    list.Free;
  end;
end;

procedure TTestCycle.TestOwnsSelfInTValue;
var
  inst: TOwnsTValue;
  s: string;
begin
  inst := TOwnsTValue.Create;
  inst.F := inst;
  try
    FResult := ScanForCycles(inst);
    CheckEquals(1, Length(FResult));
    s := FResult[0].ToString;
    CheckEquals(3, FResult[0].Length, s);
    CheckTrue(FResult[0][0].TypeInfo = inst.ClassInfo, s);
    CheckTrue(FResult[0][1].TypeInfo = TypeInfo(TValue), s);
    // Type duplicated see ScanTValue
    CheckTrue(FResult[0][2].TypeInfo = inst.ClassInfo, s);
  finally
    inst.F := TValue.Empty;
    inst.Free;
  end;
end;

procedure TTestCycle.TestOwnsSelfInTValueAndArray;
var
  inst: TOwnsTValue;
  value: TArray2OfIInterface;
  s: string;
begin
  inst := TOwnsTValue.Create;
  value[1] := inst;
  inst.F := TValue.From(value);
  try
    FResult := ScanForCycles(inst);
    CheckEquals(1, Length(FResult));
    s := FResult[0].ToString;
    CheckEquals(4, FResult[0].Length, s);
    CheckTrue(FResult[0][0].TypeInfo = inst.ClassInfo, s);
    CheckTrue(FResult[0][1].TypeInfo = TypeInfo(TValue), s);
    CheckTrue(FResult[0][2].TypeInfo = TypeInfo(TArray2OfIInterface), s);
    CheckTrue(FResult[0][3].TypeInfo = TypeInfo(IInterface), s);
  finally
    inst.F := TValue.Empty;
    value[1] := nil;
  end;
end;

procedure TTestCycle.TestOwnsSelfInTValueAndInterface;
var
  inst: TOwnsTValue;
  s: string;
begin
  inst := TOwnsTValue.Create;
  inst.F := TValue.From<IInterface>(inst);
  try
    FResult := ScanForCycles(inst);
    CheckEquals(1, Length(FResult));
    s := FResult[0].ToString;
    CheckEquals(3, FResult[0].Length, s);
    CheckTrue(FResult[0][0].TypeInfo = inst.ClassInfo, s);
    CheckTrue(FResult[0][1].TypeInfo = TypeInfo(TValue), s);
    CheckTrue(FResult[0][2].TypeInfo = TypeInfo(IInterface), s);
  finally
    inst.F := TValue.Empty;
  end;
end;

{$IFDEF AUTOREFCOUNT}

procedure TTestCycle.TestOwnsSelfObject;
var
  inst: TOwnsObject;
  s: string;
begin
  inst := TOwnsObject.Create;
  inst.F := inst;
  try
    FResult := ScanForCycles(inst);
    CheckEquals(1, Length(FResult));
    s := FResult[0].ToString;
    CheckEquals(2, FResult[0].Length, s);
    CheckTrue(FResult[0][0] = inst.ClassInfo, s);
    CheckTrue(FResult[0][1] = TypeInfo(TObject), s);
  finally
    inst.F := nil;
  end;
end;

{$ENDIF}

procedure TTestCycle.TestToString;
var
  inst: TOwnsInterface;
begin
  inst := TOwnsInterface.Create;
  inst.F := inst;
  try
    FResult := ScanForCycles(inst);
    CheckEquals(1, Length(FResult));
    CheckEquals('TOwnsInterface -> IInterface -> TOwnsInterface',
      FResult[0].ToString);
  finally
    inst.F := nil;
  end;
end;

{$ENDREGION}

{$REGION 'TTestLeaksWithACycle'}

procedure TTestLeaksWithACycle.TestCycle;
var
  inst1: TOwnsInterface;
  inst2: TOwnsInterface;
begin
  inst1 := TOwnsInterface.Create;
  inst2 := TOwnsInterface.Create;
  TheLeak := inst1;
  inst1.F := inst2;
  inst2.F := inst1;
  Check(True);
end;

{$ENDREGION}

initialization
  RegisterTests([TTestCycle.Suite, TTestLeaksWithACycle.Suite]);

finalization
  if Assigned(TheLeak) then
    TheLeak.F := nil;

end.
