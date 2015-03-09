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

type
  TFieldInfo = packed record
    TypeInfo: PPTypeInfo;
    case Integer of
    0: ( Offset: Cardinal );
    1: ( _Dummy: NativeUInt );
  end;

  PFieldTable = ^TFieldTable;
  TFieldTable = packed record
    X: Word;
    Size: Cardinal;
    Count: Cardinal;
    Fields: array [0..0] of TFieldInfo;
  end;

  PDynArrayRec = ^TDynArrayRec;
  TDynArrayRec = packed record
  {$IF SizeOf(Pointer) = 8}
    _Padding: LongInt; // Make 16 byte align for payload..
  {$IFEND}
    RefCnt: LongInt;
    Length: NativeInt;
  end;

  PNativeUint = ^NativeUInt;

  PValueData = ^TValueData;
  PValue = ^TValue;