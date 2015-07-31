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

unit LeakCheck.Collections;

{$I LeakCheck.inc}

interface

uses
  LeakCheck,
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
  Generics.Collections;

type
  IDictionary<TKey,TValue> = interface
    function TryGetValue(const Key: TKey; out Value: TValue): Boolean;
    procedure AddOrSetValue(const Key: TKey; const Value: TValue);
    function GetEnumerator: Generics.Collections.TDictionary<TKey,TValue>.TPairEnumerator;
  end;

  TDictionary<TKey,TValue> = class(Generics.Collections.TDictionary<TKey,TValue>,
    IDictionary<TKey,TValue>)
  protected
{$IFNDEF AUTOREFCOUNT}
    FRefCount: Integer;
{$ENDIF}
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
{$IFNDEF AUTOREFCOUNT}
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
    class function NewInstance: TObject; override;
{$ENDIF}
  end;

implementation

{ TDictionary<TKey, TValue> }

{$IFNDEF AUTOREFCOUNT}
procedure TDictionary<TKey, TValue>.AfterConstruction;
begin
  inherited;
// Release the constructor's implicit refcount
{$IFNDEF MSWINDOWS}
  AtomicDecrement(FRefCount);
{$ELSE MSWINDOWS}
  InterlockedDecrement(FRefCount);
{$ENDIF MSWINDOWS}
end;

procedure TDictionary<TKey, TValue>.BeforeDestruction;
begin
  if FRefCount <> 0 then
    System.Error(reInvalidPtr);
  inherited;
end;

class function TDictionary<TKey, TValue>.NewInstance: TObject;
begin
  Result := inherited NewInstance;
  TDictionary<TKey, TValue>(Result).FRefCount := 1;
end;
{$ENDIF}

function TDictionary<TKey, TValue>.QueryInterface(const IID: TGUID;
  out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := 0
  else
    Result := E_NOINTERFACE;
end;

function TDictionary<TKey, TValue>._AddRef: Integer;
begin
{$IFNDEF AUTOREFCOUNT}
{$IFNDEF MSWINDOWS}
  Result := AtomicIncrement(FRefCount);
{$ELSE MSWINDOWS}
  Result := InterlockedIncrement(FRefCount);
{$ENDIF MSWINDOWS}
{$ELSE AUTOREFCOUNT}
  Result := __ObjAddRef;
{$ENDIF AUTOREFCOUNT}
end;

function TDictionary<TKey, TValue>._Release: Integer;
begin
{$IFNDEF AUTOREFCOUNT}
{$IFNDEF MSWINDOWS}
  Result := AtomicDecrement(FRefCount);
{$ELSE MSWINDOWS}
  Result := InterlockedDecrement(FRefCount);
{$ENDIF MSWINDOWS}
  if Result = 0 then
    Destroy;
{$ELSE AUTOREFCOUNT}
  Result := __ObjRelease;
{$ENDIF AUTOREFCOUNT}
end;

end.
