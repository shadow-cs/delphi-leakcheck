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

unit LeakCheck.MapFile;

interface
uses Windows, Classes, StrUtils, Generics.Defaults, Generics.Collections;

type
  TMAPItem = record
	Name	: string;
	Addr	: DWORD;
  end;

  TMAPCollection = class
  private type
	TItems = TList<TMAPItem>;
	TComparer = class(TInterfacedObject, IComparer<TMAPItem>)
	public
	  function Compare(const Left, Right: TMAPItem): Integer;
	end;
	TSegment = record
		Index	: Integer;
		Start	: NativeUInt;
		Length	: NativeUInt;
		///<summary>
		///    Text is code, IText is initialization and finalization code,
		///    Other are all others like data, BSS, TLS etc.
		///</summary>
		SegType	: (stText, stIText, stOther);
		SegEnd	: NativeUInt;
	end;
	TSegments = TList<TSegment>;
	TLine = record
		Addr	: NativeUInt;
		Line	: Integer;
	end;
	TLines = TList<TLine>;
	TLineComparer = class(TInterfacedObject, IComparer<TLine>)
	public
	  function Compare(const Left, Right: TLine): Integer;
	end;
  private const
	CODE = [stText, stIText];
  private
	FComparer		: IComparer<TMAPItem>;
	FLineComparer	: IComparer<TLine>;
	FItems		: TItems;
	FSegments	: TArray<TSegment>;
	FLines		: TLines;
	FCodeBase	: NativeUInt;
	FHasLines	: Boolean;
	function GetItem(Index: Integer): TMAPItem; inline;
	class procedure ParseSegAddr(const s: string; Start : Integer;
		out Index: Integer; out Addr: NativeUInt); static; inline;
  protected
	procedure Add(const Addr : NativeUInt; const Name : string);
	procedure AddLine(const Addr : NativeUInt; const Line : Integer);
	function IsInCodeSegment(Addr : NativeUInt) : Boolean;
  public
	constructor	Create;
	destructor Destroy; override;

	procedure LoadFromFile(const FileName : string);
	function GetNearestSymbol(Addr : NativeUInt; out Displacement : NativeUInt) : string;
	function GetNearestLine(Addr : NativeUInt; out Displacement : NativeUInt) : Integer;

	property CodeBase : NativeUInt read FCodeBase write FCodeBase;
	property Items[Index: Integer]: TMAPItem read GetItem; default;
	property HasLines : Boolean read FHasLines;
  end;

implementation
uses SysUtils;

function TMAPCollection.GetItem(Index: Integer): TMAPItem;
begin
	Result:=FItems[Index];
end;
//******************************************************************************
constructor	TMAPCollection.Create;
begin
	inherited;
	FComparer:=TComparer.Create;
	FLineComparer:=TLineComparer.Create;

	FCodeBase:=$00401000;
	FItems:=TItems.Create(FComparer);
	FLines:=TLines.Create(FLineComparer);
end;
//******************************************************************************
destructor TMAPCollection.Destroy;
begin
	FItems.Free;
	FLines.Free;
	inherited;
end;
//******************************************************************************
procedure TMAPCollection.Add(const Addr : NativeUInt; const Name : string);
var Item	: TMAPItem;
	Index	: Integer;
begin
	Item.Addr:=Addr;
	if (not FItems.BinarySearch(Item, Index)) then begin
		Item.Name:=Name;
		FItems.Insert(Index, Item);
	end
	//There can be some system utils that do generate same calls
	//else OutputDebugString(PChar('Duplicate symbol address ' + Addr.ToHexString + ' ' + Name));
	//else Assert(false, 'Duplicate symbol address ' + Addr.ToHexString);
end;
//******************************************************************************
procedure TMAPCollection.AddLine(const Addr: NativeUInt; const Line: Integer);
var Item	: TLine;
	Index	: Integer;
begin
	Item.Addr:=Addr;
	if (not FLines.BinarySearch(Item, Index)) then begin
		Item.Line:=Line;
		FLines.Insert(Index, Item);
	end
	//There can be some init code that can share the same address (typicaly 0 in each segment)
	//else OutputDebugString(PChar('Duplicate line address ' + Addr.ToHexString + ' ' + Line.ToString));
	//else Assert(false);
end;
//******************************************************************************
class procedure TMAPCollection.ParseSegAddr(const s : string; Start : Integer;
	out Index : Integer; out Addr : NativeUInt);
begin
	Index:=StrToInt('$'+Copy(s, Start + 0, 4));
	Addr:=NativeUInt(StrToInt('$'+Copy(s, Start + 5, 8)));
end;
//******************************************************************************
procedure TMAPCollection.LoadFromFile(const FileName : string);
var ASegments	: TSegments;
//**********
procedure ParseSegment(const s : string);
var Segment	: TSegment;
	Name	: string;
begin
	ParseSegAddr(s, 2, Segment.Index, Segment.Start);
	Segment.Length:=DWORD(StrToInt('$'+Copy(s, 7+9, 8)));
	Name:=TrimRight(Copy(s, 7+9+8+2, 12));
	if (Name = '.text') then
		Segment.SegType:=stText
	else if (Name = '.itext') then
		Segment.SegType:=stIText
	else Segment.SegType:=stOther;

	if Segment.Length > 0 then
		ASegments.Add(Segment);
end;
//**********
procedure ParseSymbol(const s : string);
var Segment	: TSegment;
	SegIdx	: Integer;
	Addr	: NativeUInt;
begin
	ParseSegAddr(s, 2, SegIdx, Addr);
	Segment:=FSegments[SegIdx - 1];
	if (not (Segment.SegType in CODE)) then Exit; //Not CODE

	//We're relative to code base point, Segment start addr is already normlaized (See note below)
	Addr:=Addr + Segment.Start;
	//Assert(IsInCodeSegment(Addr), 'Not in code ' + Addr.ToHexString);
	Add(Addr, Copy(s, 22, 255));
end;
//**********
procedure ParseLineNumbers(const Reader : TStreamReader);
var s		: string;
	i, j	: Integer;
	Segment	: TSegment;
	SegIdx	: Integer;
	Addr	: NativeUInt;
begin
	s:=Reader.ReadLine;
	Segment.Index:=-1;
	while (s <> '') do begin
		i:=1;

		while (i < Length(s)) do begin
			while (not CharInSet(s[i], ['0'..'9'])) do Inc(i);
			j:=PosEx(' ', s, i);
			if (j < i) then Break;
			Inc(j); //Skip the space
			ParseSegAddr(s, j, SegIdx, Addr);
			if (Segment.Index < 0) then
				Segment:=FSegments[SegIdx - 1]
			else if (Segment.Index <> SegIdx) then
				raise Exception.Create('Inconsistent segments in line numbers');
			Addr:=Addr + Segment.Start;
			{if (not IsInCodeSegment(Addr)) then
				OutputDebugString(PChar('Not in code segment ' + Addr.ToHEXString));}
			AddLine(Addr, StrToInt(Copy(s, i, j - i - 1)));
			i:=j + 4 + 1 + 8;
		end;

		s:=Reader.ReadLine;
	end;
end;
//**********
var Reader	: TStreamReader;
	s		: string;
	i		: Integer;
	Segment	: TSegment;
begin
	//Using the reader saves about 5% parsing time compared to Readln
	Reader:=TStreamReader.Create(TFileStream.Create(FileName,
		fmOpenRead or fmShareDenyWrite), TEncoding.Default);
	try
		Reader.OwnStream;

		FHasLines:=false;

		s:=Reader.ReadLine; //Skip first empty line
		s:=TrimLeft(Reader.ReadLine);
		if (not StartsStr('Start', s)) then
			raise Exception.Create('Segment map not found');
		ASegments:=TSegments.Create;
		try
			while (not Reader.EndOfStream) do begin
				s:=TrimRight(Reader.ReadLine);
				if (s = '') then Break;
				ParseSegment(s);
			end;
			if (ASegments.Count = 0) then
				raise Exception.Create('No segments found');
			Segment:=ASegments[0];
			if (Segment.SegType <> stText) then
				raise Exception.Create('First segment must be .text segment');
			FCodeBase:=Segment.Start;
			FSegments:=ASegments.ToArray;
		finally
			ASegments.Free;
		end;

		//Convert first segment too, it will start at address 0 which is desired
		//after rellocation module base is extracted at runtime and subtracted
		//so while decoding first code address will be (reltive to) 0
		for i:=0 to Length(FSegments) - 1 do begin
			//Convert segment addresses relative to CodeBase
			Segment:=FSegments[i];
			if (Segment.Index <> i + 1) then
				raise Exception.Create('Invalid segment order');

			Segment.Start:=Segment.Start - FCodeBase;
			Segment.SegEnd:=Segment.Start + Segment.Length;
			FSegments[i]:=Segment;
		end;

		//Skip detailed segment map
		repeat
			s:=Reader.ReadLine;
		until (s='  Address             Publics by Name') or Reader.EndOfStream;
		s:=Reader.ReadLine;
		s:=Reader.ReadLine;
		while (s <> '') do begin
			ParseSymbol(s);
			s:=Reader.ReadLine;
		end;
		FItems.TrimExcess;

		//Skip second symbol map ordered by value (contains same values but in different order)
		s:=Reader.ReadLine;
		s:=Reader.ReadLine;
		if (ContainsStr(s, 'Publics by Value')) then begin
			s:=Reader.ReadLine;
			s:=Reader.ReadLine;
			while (s <> '') do s:=Reader.ReadLine;
		end;

		s:=Reader.ReadLine;
		s:=Reader.ReadLine;
		while (StartsStr('Line numbers', s)) do begin
			s:=Reader.ReadLine;
			ParseLineNumbers(Reader);
			s:=Reader.ReadLine;
		end;
		FLines.TrimExcess;
		Assert(s = 'Bound resource files');
		FHasLines:=FLines.Count > 0;
	finally
		Reader.Free;
	end;
end;
//******************************************************************************
function TMAPCollection.GetNearestLine(Addr: NativeUInt;
  out Displacement: NativeUInt): Integer;
var Item	: TLine;
	Index	: Integer;
begin
	Displacement:=Addr;
	Addr:=Addr - CodeBase;
	Result:=-1;
	if (FLines.Count = 0) then Exit;
	if (not IsInCodeSegment(Addr)) then Exit;
	Item.Addr:=Addr;
	if (not FLines.BinarySearch(Item, Index)) then begin
		Dec(Index); //We want the line before the match not after
	end;
	if (Index < 0) or (Index >= FLines.Count) then Exit;

	Item:=FLines[Index];
	Displacement:=Addr - Item.Addr;
	Result:=Item.Line;
end;

function TMAPCollection.GetNearestSymbol(Addr : NativeUInt; out Displacement : NativeUInt) : string;
var Item	: TMAPItem;
	Index	: Integer;
begin
	Displacement:=Addr;
	Addr:=Addr - CodeBase;
	Result:='';
	if (FItems.Count = 0) then Exit;
	if (not IsInCodeSegment(Addr)) then Exit;
	Item.Addr:=Addr;
	if (not FItems.BinarySearch(Item, Index)) then begin
		Dec(Index); //We want the symbol bofore the match not after
	end;
	if (Index < 0) or (Index >= FItems.Count) then Exit;

	Item:=FItems[Index];
	Displacement:=Addr - Item.Addr;
	Result:=Item.Name;
end;

function TMAPCollection.IsInCodeSegment(Addr: NativeUInt): Boolean;
var i		: Integer;
	Segment	: TSegment;
begin
	for i:=0 to High(FSegments) do begin
		Segment:=FSegments[i];
		if ((Segment.SegType in CODE) and (Addr >= Segment.Start) and
			(Addr < Segment.SegEnd)) then Exit(true);
	end;
	Result:=false;
end;

{ TMAPCollection.TComparer }

function TMAPCollection.TComparer.Compare(const Left, Right: TMAPItem): Integer;
begin
	Result:=NativeInt(Left.Addr) - NativeInt(Right.Addr);
end;

{ TMAPCollection.TLineComparer }

function TMAPCollection.TLineComparer.Compare(const Left,
  Right: TLine): Integer;
begin
	Result:=NativeInt(Left.Addr) - NativeInt(Right.Addr);
end;

end.
