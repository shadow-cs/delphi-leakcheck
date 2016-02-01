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

library LeakCheck.Inject;

uses
  LeakCheck,
  LeakCheck.Report,
  LeakCheck.Setup.Trace,
  LeakCheck.Report.Utils,
  LeakCheck.Report.FileLog;

{$R *.res}

procedure ReportNow;
var
  Snapshot: TLeakCheck.TSnapshot;
begin
  // Report all - internal snapshot is nil
  Snapshot := Default(TLeakCheck.TSnapshot);
  GetReport(Snapshot);
end;

exports
  ReportNow;

begin
  // ReportFormat := [TReportFormat.WithLog];
end.
