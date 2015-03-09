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

program TestProject;

uses
  LeakCheck in '..\..\Source\LeakCheck.pas',
  System.StartUpCopy,
  LeakCheck.Utils in '..\..\Source\LeakCheck.Utils.pas',
  FMX.Forms,
  TestFramework in '..\..\External\DUnit\TestFramework.pas',
  TestInsight.DUnit,
  Posix.Proc in '..\..\External\Backtrace\Source\Posix.Proc.pas',
  LeakCheck.TestUnit in '..\LeakCheck.TestUnit.pas',
  LeakCheck.TestDUnit in '..\LeakCheck.TestDUnit.pas',
  LeakCheck.TestForm in '..\LeakCheck.TestForm.pas' {frmLeakCheckTest},
  LeakCheck.DUnit in '..\..\Source\LeakCheck.DUnit.pas';

{$R *.res}

begin
  ReportMemoryLeaksOnShutdown := True;

  // Simple test of functionality
  RunTests;

  // DUnit integration
{$IFDEF WEAKREF}
  TLeakCheck.IgnoredLeakTypes := [tkUnknown];
{$ENDIF}
  RunRegisteredTests;

{$IFDEF GUI}
  // FMX Leak detection
  Application.Initialize;
  Application.CreateForm(TfrmLeakCheckTest, frmLeakCheckTest);
  Application.Run;
{$ENDIF}
end.

