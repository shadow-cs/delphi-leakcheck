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

unit LeakCheck.TestUnit;

{$ASSERTIONS ON}

interface

procedure RunTests;

implementation

uses LeakCheck;

var
  LeakSnapshot: Pointer;

procedure TestFirstLast;
var
  P: Pointer;
  L: TLeaks;
begin
  GetMem(P, 16);
  L := TLeakCheck.GetLeaks(LeakSnapshot);
  Assert(L.Length = 1);
  Assert(L[0] = P);
  L.Free;
  FreeMem(P);
  L := TLeakCheck.GetLeaks(LeakSnapshot);
  Assert(L.Length = 0);
end;

procedure TestLast;
var
  P1, P2, P3: Pointer;
  L: TLeaks;
begin
  GetMem(P1, 16);
  GetMem(P2, 16);
  GetMem(P3, 16);
  FreeMem(P3);
  L := TLeakCheck.GetLeaks(LeakSnapshot);
  Assert(L.Length = 2);
  Assert(L[0] = P1);
  Assert(L[1] = P2);
  L.Free;
  FreeMem(P2);
  FreeMem(P1);
end;

procedure TestFirst;
var
  P1, P2, P3: Pointer;
  L: TLeaks;
begin
  GetMem(P1, 16);
  GetMem(P2, 16);
  GetMem(P3, 16);
  FreeMem(P1);
  L := TLeakCheck.GetLeaks(LeakSnapshot);
  Assert(L.Length = 2);
  Assert(L[0] = P2);
  Assert(L[1] = P3);
  L.Free;
  FreeMem(P2);
  FreeMem(P3);
end;

procedure TestMid;
var
  P1, P2, P3: Pointer;
  L: TLeaks;
begin
  GetMem(P1, 16);
  GetMem(P2, 16);
  GetMem(P3, 16);
  FreeMem(P2);
  L := TLeakCheck.GetLeaks(LeakSnapshot);
  Assert(L.Length = 2);
  Assert(L[0] = P1);
  Assert(L[1] = P3);
  L.Free;
  FreeMem(P1);
  FreeMem(P3);
end;

procedure TestReport;
var
  P, PP: PByte;
  Leak: LeakString;
  i: Integer;
  s: string;
  o: TObject;
begin
  GetMem(P, 48);
  PP := P;
  for i := 0 to 48 - 1 do
  begin
    PP^ := i;
    Inc(PP);
  end;
  Leak := TLeakCheck.GetReport(LeakSnapshot);
  FreeMem(P);
  Assert(not Leak.IsEmpty);
  Leak.Free;
  TLeakCheck.Report(LeakSnapshot);
  Leak := TLeakCheck.GetReport(LeakSnapshot);
  Assert(Leak.IsEmpty);
  Leak.Free;

  s := 'Test';
  UniqueString(s);
  TLeakCheck.Report(LeakSnapshot);
  s := '';
  Assert(TLeakCheck.GetReport(LeakSnapshot).IsEmpty);
  o := TObject.Create;
  TLeakCheck.Report(LeakSnapshot);
  o.Free;
  Assert(TLeakCheck.GetReport(LeakSnapshot).IsEmpty);
end;

procedure RunTests;
begin
  LeakSnapshot := TLeakCheck.CreateSnapshot;
  TestFirstLast;
  TestLast;
  TestFirst;
  TestMid;
  TestReport;
end;

end.
