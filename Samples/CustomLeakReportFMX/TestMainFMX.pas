unit TestMainFMX;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.StdCtrls;

type
  TForm2 = class(TForm)
    cmdExit: TButton;
    cmdAddLeak: TButton;
    procedure cmdAddLeakClick(Sender: TObject);
    procedure cmdExitClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form2: TForm2;

implementation

{$R *.fmx}

procedure TForm2.cmdAddLeakClick(Sender: TObject);
var
  o: TObject;
begin
  Pointer(o) := TButton.Create(nil);
end;

procedure TForm2.cmdExitClick(Sender: TObject);
begin
  Application.Terminate;
end;

end.
