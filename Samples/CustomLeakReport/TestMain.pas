unit TestMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls;

type
  TForm1 = class(TForm)
    cmdAddLeak: TButton;
    procedure cmdAddLeakClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

procedure TForm1.cmdAddLeakClick(Sender: TObject);
begin
  TButton.Create(nil); // Create a leak here
end;

end.
