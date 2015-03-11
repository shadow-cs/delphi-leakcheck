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

unit LeakCheck.Cycle;

interface

uses
  System.TypInfo,
  System.Generics.Collections,
  System.Rtti;

type
  TCycle = TArray<PTypeInfo>;
  TCycles = TArray<TCycle>;

  TScanner = class
  strict protected type
    TSeenInstancesSet = TDictionary<Pointer, Boolean>;
    TCurrentPathStack = TStack<PTypeInfo>;
    {$INCLUDE LeakCheck.Types.inc}
  strict protected
    FCurrentPath: TCurrentPathStack;
    FInstance: Pointer;
    FResult: TCycles;
    FSeenInstances: TSeenInstancesSet;

    procedure CycleFound;
    procedure ScanArray(P: Pointer; TypeInfo: PTypeInfo; ElemCount: NativeUInt);
    procedure ScanClass(const Instance: TObject);
    procedure ScanClassInternal(const Instance: TObject);
    procedure ScanDynArray(var A: Pointer; TypeInfo: Pointer);
    procedure ScanInterface(const Instance: IInterface);
    procedure ScanRecord(P: Pointer; TypeInfo: PTypeInfo);
    procedure ScanTValue(const Value: PValue);
    procedure TypeEnd; inline;
    procedure TypeStart(TypeInfo: PTypeInfo); inline;
  protected
    constructor Create(AInstance: Pointer);
    function Scan: TCycles;
  public
    destructor Destroy; override;
  end;

  TCycleHelper = record helper for TCycle
  public
    function ToString: string;
  end;

/// <summary>
///   Scans for reference cycles in managed fields. It can ONLY scan inside
///   managed fields so it can scan for interface cycles on any platform but
///   can only find object cycles on NextGen generated code. On non-NextGen it
///   cannot find cycles produced by referencing interface from owned object.
///   Main goal of this function is to detect cycles on NextGen in places where
///   you might have forgot to put <c>Weak</c> attribute.
/// </summary>
function ScanForCycles(const Instance: TObject): TCycles;

implementation

function ScanForCycles(const Instance: TObject): TCycles;
var
  Scanner: TScanner;
begin
  Scanner := TScanner.Create(Instance);
  try
    Result := Scanner.Scan;
  finally
    Scanner.Free;
  end;
end;

{$REGION 'TScanner'}

constructor TScanner.Create(AInstance: Pointer);
begin
  inherited Create;
  FInstance := AInstance;
  FCurrentPath := TCurrentPathStack.Create;
  FSeenInstances := TSeenInstancesSet.Create;
end;

procedure TScanner.CycleFound;
var
  Len: Integer;
begin
  Len := Length(FResult);
  SetLength(FResult, Len + 1);
  FResult[Len] := FCurrentPath.ToArray;
end;

destructor TScanner.Destroy;
begin
  FSeenInstances.Free;
  FCurrentPath.Free;
  inherited;
end;

function TScanner.Scan: TCycles;
begin
  try
    ScanClassInternal(FInstance);
    Result := FResult;
  finally
    FResult := Default(TCycles);
    FSeenInstances.Clear;
  end;
end;

procedure TScanner.ScanArray(P: Pointer; TypeInfo: PTypeInfo;
  ElemCount: NativeUInt);
var
  FT: PFieldTable;
begin
  TypeStart(TypeInfo);
  if ElemCount > 0 then
  begin
    case TypeInfo^.Kind of
      // TODO: Variants
      tkClass:
        while ElemCount > 0 do
        begin
          ScanClass(TObject(P^));
          Inc(PByte(P), SizeOf(Pointer));
          Dec(ElemCount);
        end;
      tkInterface:
        while ElemCount > 0 do
        begin
          ScanInterface(IInterface(P^));
          Inc(PByte(P), SizeOf(Pointer));
          Dec(ElemCount);
        end;
      tkDynArray:
        while ElemCount > 0 do
        begin
          // See System._FinalizeArray for why we call it like that
          ScanDynArray(PPointer(P)^, typeInfo);
          Inc(PByte(P), SizeOf(Pointer));
          Dec(ElemCount);
        end;
      tkArray:
        begin
          FT := PFieldTable(PByte(typeInfo) + Byte(PTypeInfo(typeInfo).Name{$IFNDEF NEXTGEN}[0]{$ENDIF}));
          while ElemCount > 0 do
          begin
            ScanArray(P, FT.Fields[0].TypeInfo^, FT.Count);
            Inc(PByte(P), FT.Size);
            Dec(ElemCount);
          end;
        end;
      tkRecord:
        begin
          FT := PFieldTable(PByte(TypeInfo) + Byte(PTypeInfo(TypeInfo).Name{$IFNDEF NEXTGEN}[0]{$ENDIF}));
          while ElemCount > 0 do
          begin
            if TypeInfo = System.TypeInfo(TValue) then
              ScanTValue(PValue(P))
            else
              ScanRecord(P, TypeInfo);
            Inc(PByte(P), FT.Size);
            Dec(ElemCount);
          end;
        end;
    end;
  end;
  TypeEnd;
end;

procedure TScanner.ScanClass(const Instance: TObject);
begin
  if not Assigned(Instance) then
    // NOP
  else if Instance = FInstance then
    CycleFound
  else if not FSeenInstances.ContainsKey(Instance) then
  begin
    FSeenInstances.Add(Instance, True);
    ScanClassInternal(Instance);
  end;
end;

procedure TScanner.ScanClassInternal(const Instance: TObject);
var
  InitTable: PTypeInfo;
  LClassType: TClass;
begin
  TypeStart(Instance.ClassInfo);
  LClassType := Instance.ClassType;
  repeat
    InitTable := PPointer(PByte(LClassType) + vmtInitTable)^;
    if Assigned(InitTable) then
      ScanRecord(Instance, InitTable);
    LClassType := LClassType.ClassParent;
  until LClassType = nil;
  TypeEnd;
end;

procedure TScanner.ScanDynArray(var A: Pointer; TypeInfo: Pointer);
var
  P: Pointer;
  Rec: PDynArrayRec;
begin
  // Do not push another type, we already did in previous call

  P := A;
  if P <> nil then
  begin
    Rec := PDynArrayRec(PByte(P) - SizeOf(TDynArrayRec));

    // If refcount is negative the array is released
    if (Rec^.RefCnt > 0) and (Rec^.Length <> 0) then
    begin
      // Fetch the type descriptor of the elements
      Inc(PByte(TypeInfo), PDynArrayTypeInfo(TypeInfo)^.name);
      if PDynArrayTypeInfo(TypeInfo)^.elType <> nil then
      begin
        TypeInfo := PDynArrayTypeInfo(TypeInfo)^.elType^;
        ScanArray(P, TypeInfo, Rec^.Length);
      end;
    end;
  end;
end;

procedure TScanner.ScanInterface(const Instance: IInterface);
begin
  // Do not push another type, we cannot be sure of the type information
  // Cast should return nil not raise an exception if interface is not class
  ScanClass(TObject(Instance));
end;

procedure TScanner.ScanRecord(P: Pointer; TypeInfo: PTypeInfo);
var
  I: Cardinal;
  FT: PFieldTable;
begin
  // Do not push another type, ScanArray will do it later
  FT := PFieldTable(PByte(TypeInfo) + Byte(PTypeInfo(TypeInfo).Name{$IFNDEF NEXTGEN}[0]{$ENDIF}));
  if FT.Count > 0 then
  begin
    for I := 0 to FT.Count - 1 do
    begin
{$IFDEF WEAKREF}
      if FT.Fields[I].TypeInfo = nil then
        Exit; // Weakref separator
        // TODO: Wekrefs???
{$ENDIF}
      ScanArray(Pointer(PByte(P) + IntPtr(FT.Fields[I].Offset)),
        FT.Fields[I].TypeInfo^, 1);
    end;
  end;
end;

procedure TScanner.ScanTValue(const Value: PValue);
var
  ValueData: PValueData absolute Value;
begin
  // Do not push another type, ScanArray already did
  if (not Value^.IsEmpty) and Assigned(ValueData^.FValueData) then
  begin
    // Performance optimization, keep only supported types here to avoid adding
    // strings
    case Value^.Kind of
      // TODO: Variants
      tkClass,
      tkInterface,
      tkDynArray,
      tkArray,
      tkRecord:
        // If TValue contains the instance directly it will duplicate it
        // but it is totally OK, otherwise some other type holding the instance
        // might get hidden. The type is the actual type TValue holds.
        ScanArray(Value^.GetReferenceToRawData, Value.TypeInfo, 1);
    end;
  end;
end;

procedure TScanner.TypeEnd;
begin
  FCurrentPath.Pop;
end;

procedure TScanner.TypeStart(TypeInfo: PTypeInfo);
begin
  FCurrentPath.Push(TypeInfo);
end;

{$ENDREGION}

{$REGION 'TCycleHelper'}

function TCycleHelper.ToString: string;
const
  Separator = ' -> ';
var
  TypeInfo: PTypeInfo;
begin
  Result := '';
  if Length(Self) = 0 then
    Exit;

  for TypeInfo in Self do
  begin
    if Byte(TypeInfo^.Name{$IFNDEF NEXTGEN}[0]{$ENDIF}) > 0 then
    begin
      if Result <> '' then
        Result := Result + Separator;

      Result := Result + TypeInfo^.NameFld.ToString;
    end;
  end;
  // Complete the circle
  Result := Result + Separator + Self[0]^.NameFld.ToString;
end;

{$ENDREGION}

end.
