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

unit LeakCheck.Report.FileLog;

{$I LeakCheck.inc}

interface

uses
  LeakCheck,
  LeakCheck.Report.Utils;

implementation

{$IF CompilerVersion >= 25} // >= XE4
  {$LEGACYIFEND ON}
{$IFEND}

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF}
{$IFDEF POSIX}
  Posix.Unistd,
{$ENDIF}
{$IFDEF ANDROID}
  Androidapi.Log,
{$ENDIF}
  IOUtils,
  SysUtils;

type
  TLeakCheckFileReporter = class(TLeakCheckReporter)
  private
    FLogFileName: string;
    FGraphFileName: string;
    FLog: TextFile;
  protected
    constructor Create; override;
    procedure NoLeaks; override;
    procedure BeginLog; override;
    procedure WritelnLog(Log: MarshaledAString); override;
    procedure EndLog; override;
    procedure WriteGraph(const Graph: string); override;
    procedure ShowMessage; override;
  end;

{ TLeakCheckFileReporter }

procedure TLeakCheckFileReporter.BeginLog;
begin
  inherited;
  AssignFile(FLog, FLogFileName);
  Rewrite(FLog);
end;

constructor TLeakCheckFileReporter.Create;
var
  BasePath, BaseName: string;
begin
  inherited;

{$IF Defined(MACOS) OR Defined(IOS) OR Defined(LEAK_REPORT_DOCUMENTS)}
  BasePath := TPath.GetDocumentsPath;
  BaseName := ExtractFileName(ParamStr(0));
{$ELSEIF Defined(MSWINDOWS)}
  BasePath := ExtractFilePath(ParamStr(0));
  BaseName := ExtractFileName(ParamStr(0));
{$ELSEIF Defined(ANDROID)}
  // Note that this requires Read/Write External Storage permissions
  // Write permissions option is enough, reading will be available as well
  BasePath := '/storage/emulated/0/';
  BaseName := 'LeakCheck_Log';
{$IFEND}
  BasePath := TPath.Combine(BasePath, ChangeFileExt(BaseName, ''));

  FLogFileName := BasePath + '.log';
  FGraphFileName := BasePath + '.dot';
end;

procedure TLeakCheckFileReporter.EndLog;
begin
  inherited;
  CloseFile(FLog);
end;

procedure TLeakCheckFileReporter.NoLeaks;
begin
  inherited;
  DeleteFile(FLogFileName);
  DeleteFile(FGraphFileName);
end;

procedure TLeakCheckFileReporter.ShowMessage;
{$IFDEF ANDROID}
const
  TAG: MarshaledAString = MarshaledAString('leak');
var
  M: TMarshaller;
{$ENDIF}
var
  Msg: string;
begin
  inherited;
  Msg := 'Memory leak detected, see ' + FLogFileName + ' and ' + FGraphFileName;
{$IFDEF MSWINDOWS}
  MessageBox(0, PChar(Msg), 'Memory leak', MB_ICONERROR);
{$ENDIF}
{$IFDEF ANDROID}
  __android_log_write(ANDROID_LOG_WARN, TAG, M.AsAnsi(Msg).ToPointer);
{$ENDIF}
end;

procedure TLeakCheckFileReporter.WriteGraph(const Graph: string);
var
  f: TextFile;
begin
  inherited;
  AssignFile(f, FGraphFileName);
  Rewrite(f);
  try
    Writeln(f, Graph);
  finally
    CloseFile(f);
  end;
end;

procedure TLeakCheckFileReporter.WritelnLog(Log: MarshaledAString);
begin
  inherited;
  Writeln(FLog, Log);
end;

initialization
  ReporterClass := TLeakCheckFileReporter;

end.
