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

unit LeakCheck.Trace.Map;

{$I LeakCheck.inc}

interface

uses
  LeakCheck,
  LeakCheck.MapFile;

/// <summary>
///   Based on own implementation that does not use global caching and is safe
///   to use after finalization. Supports function names and line numbers with
///   displacement. Does not have any external dependencies.
/// </summary>
function MapStackTraceFormatter: TLeakCheck.IStackTraceFormatter;

implementation

uses
  SysUtils,
  Generics.Collections,
  Math,
  AnsiStrings,
  Windows;

type
  TMapStackTraceFormatter = class(TInterfacedObject, TLeakCheck.IStackTraceFormatter)
  private type
    TMAPCache = TObjectDictionary<string, TMAPCollection>;
  private
    FMaps: TMAPCache;
    function GetSymobls(Addr: Pointer; var ModuleName: string): TMAPCollection;
  public
    constructor Create;
    destructor Destroy; override;

    function FormatLine(Addr: Pointer; const Buffer: MarshaledAString;
      Size: Integer): Integer;
  end;

{ TMapStackTraceFormatter }

constructor TMapStackTraceFormatter.Create;
begin
  inherited Create;
  FMaps := TMAPCache.Create([doOwnsValues]);
end;

destructor TMapStackTraceFormatter.Destroy;
begin
  FMaps.Free;
  inherited;
end;

function TMapStackTraceFormatter.FormatLine(Addr: Pointer;
  const Buffer: MarshaledAString; Size: Integer): Integer;
var
  OldTracer: TLeakCheck.TGetStackTrace;
  ModuleName: string;
  s: string;
  ansi: AnsiString;
  Map: TMAPCollection;
  Displacement: NativeUInt;
  i, j: Integer;
begin
  OldTracer := TLeakCheck.GetStackTraceProc;
  TLeakCheck.GetStackTraceProc := nil;
  TLeakCheck.BeginIgnore;
  try
    Map := GetSymobls(Addr, ModuleName);
    s := '$' + IntToHex(NativeUInt(Addr), SizeOf(Pointer) * 2) + ' - ' +
      ExtractFileName(ModuleName);
    if Assigned(Map) then
    begin
      // Format line
      s:=s + ' - ' + Map.GetNearestSymbol(NativeUInt(Addr), Displacement);
      s:=s + ' + $' + IntToHex(Displacement, 0);
      if (Map.HasLines and (Displacement < $40000)) then
      begin
        // Get the beginning line of the function
        i := Map.GetNearestLine(NativeUInt(Addr) - Displacement, Displacement);
        // Should be 0 but in case we don't have debug DCUs ot there
        // are no symbols for this particular unit, it will be bigger
        if (Displacement <= $2000) then
        begin
          j := Map.GetNearestLine(NativeUInt(Addr), Displacement);
          s := s + ' (' +IntToStr(j);
          if (Displacement <> 0) then
          s := s + ' + $' + IntToHex(Displacement, 0);
          s := s + ' +' + IntToStr(j - i) + ')';
        end;
      end;
      // else most likely way off code
    end;

    Result := Min(Length(s), Size - 1);
    if Result > 0 then
    begin
      ansi := AnsiString(s);
      Move(ansi[1], Buffer^, Result + 1); // Add trailing zero
    end;
  finally
    TLeakCheck.EndIgnore;
    TLeakCheck.GetStackTraceProc := OldTracer;
  end;
end;

function TMapStackTraceFormatter.GetSymobls(Addr: Pointer;
  var ModuleName: string): TMAPCollection;
var
  MapName: string;
  mbi: MEMORY_BASIC_INFORMATION;
begin
  VirtualQuery(Addr, mbi, sizeof(mbi));
  SetLength(ModuleName, MAX_PATH+1);
  SetLength(ModuleName, GetModuleFileName(Cardinal(mbi.AllocationBase),
    PChar(ModuleName), MAX_PATH));
  if not FMaps.TryGetValue(ModuleName, Result) then
  begin
    MapName := ChangeFileExt(ModuleName, '.map');
    if (FileExists(MapName)) then begin
      Result:=TMAPCollection.Create;
      try
        Result.CodeBase:=NativeUInt(mbi.AllocationBase);
        Result.LoadFromFile(MapName);
      except
        Result.Free;
        raise;
      end;
    end
    else
      Result := nil;
    FMaps.Add(ModuleName, Result);
  end;
end;

function MapStackTraceFormatter: TLeakCheck.IStackTraceFormatter;
begin
  Result := TMapStackTraceFormatter.Create;
end;

end.
