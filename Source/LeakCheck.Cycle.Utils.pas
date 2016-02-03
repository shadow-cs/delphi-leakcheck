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

unit LeakCheck.Cycle.Utils;

{$I LeakCheck.inc}

interface

uses
  LeakCheck,
  LeakCheck.Trace,
  LeakCheck.Utils,
  LeakCheck.Cycle;

type
  TGraphIgnorer = class(TScanner)
  strict protected
    { Do not use TypeStart! Since AFieldName is sometimes passed here if
      inspecting first class field and then class instance, false positives may
      be reached which would lead to errors and always use more specific
      functions. }
    procedure ScanClassInternal(const Instance: TObject); override;
  end;

/// <summary>
///   Ignore all leaks in object graph given by entry-point. Note that all
///   object inside the graph have to have all object fields with valid
///   references. If invalid reference is kept in any of the fields and is
///   freed without nil-ing the field, AV will probably be raised. May also
///   cause issues if used in multi-threaded environment (that have
///   race-condition issues).
/// </summary>
procedure IgnoreGraphLeaks(const Entrypoint: TObject; Flags: TScanFlags = [];
  InstanceIgnoreProc: TScanner.TIsInstanceIgnored = nil);

type
  TIgnore<T: class> = class(LeakCheck.Utils.TIgnore<T>)
  public
    /// <summary>
    ///   Ignore the class and all fields from it and all objects within its
    ///   object graph (all nested object that are referenced from this
    ///   object). May easily ignore large portions of your memory. Use with
    ///   care.
    /// </summary>
    class function AnyAndGraph(const Instance: TObject; ClassType: TClass): Boolean; static;
  end;

  TIgnoreInterface<I: IUnknown> = class(LeakCheck.Utils.TIgnoreInterface<I>)
  public
    /// <summary>
    ///   Ignore the implementing class and all fields from it and all objects
    ///   within itsobject graph (all nested object that are referenced from
    ///   this object). May easily ignore large portions of your memory. Use
    ///   with care.
    /// </summary>
    class function ImplementsAndGraph(const Instance: TObject; ClassType: TClass): Boolean; static;
  end;

implementation

procedure IgnoreGraphLeaks(const Entrypoint: TObject; Flags: TScanFlags = [];
  InstanceIgnoreProc: TScanner.TIsInstanceIgnored = nil);
begin
  TGraphIgnorer.Scan(Entrypoint, TGraphIgnorer, Flags, InstanceIgnoreProc);
end;

{$REGION 'TGraphIgnorer'}

procedure TGraphIgnorer.ScanClassInternal(const Instance: TObject);
begin
  inherited;
  if Assigned(Instance) then
  begin
{$IFDEF LEAKCHECK_TRACE}
    Trace('Ignoring: ' + Instance.QualifiedClassName);
{$ENDIF}
    RegisterExpectedMemoryLeak(Instance);
  end;
end;

{$ENDREGION}

{$REGION 'TIgnore<T>'}

class function TIgnore<T>.AnyAndGraph(const Instance: TObject;
  ClassType: TClass): Boolean;
begin
  Result := ClassType.InheritsFrom(T);
  if Result then
    IgnoreGraphLeaks(Instance, [TScanFlag.UseExtendedRtti]);
end;

{$ENDREGION}

{$REGION 'TIgnoreInterface<I>'}

class function TIgnoreInterface<I>.ImplementsAndGraph(const Instance: TObject;
  ClassType: TClass): Boolean;
begin
  Result := Implements(Instance, ClassType);
  if Result then
    IgnoreGraphLeaks(Instance, [TScanFlag.UseExtendedRtti]);
end;

{$ENDREGION}

end.
