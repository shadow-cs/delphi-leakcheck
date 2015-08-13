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

unit LeakCheck.Report;

interface

{$I LeakCheck.inc}

uses
  LeakCheck;

var
  /// <summary>
  ///   Some other unit must set this callback. It will be called just before
  ///   LeakCheck finalizes but unlike this unit, it may use some higher level
  ///   functionality. This hacks the way how unit initialization and
  ///   finalization works so use with care.
  /// </summary>
  GetReport: procedure(const Snapshot: TLeakCheck.TSnapshot);

implementation

var
  Snapshot: TLeakCheck.TSnapshot;

initialization
  // Create a Snapshot to hide some accidental allocations made by internal
  // units.
  Snapshot.Create;

finalization
  // Run high level stuff from other unit after all other units have finalized
  // (dangerous if you don't know what you're doing).
  if Assigned(GetReport) then
    GetReport(Snapshot);
end.
