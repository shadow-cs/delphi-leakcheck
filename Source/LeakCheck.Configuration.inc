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

  /// <summary>
  ///   Maximum depth of stack traces. If greater than zero, stack trace will be
  ///   acquired when memory is allocated.
  /// </summary>
  MaxStackSize = 64;

  /// <summary>
  ///   If enabled virtual calls on freed object will be intercepted and
  ///   reported.
  /// </summary>
  EnableVirtualCallsOnFreedObjectIntercetion = True;
  /// <summary>
  ///   If enabled fake VMT is assigned to freed objects so other utilities do
  ///   not raise AVs if they reach dangling pointer of a freed object (if they
  ///   do freed object checking). If freed object virtual call interception is
  ///   not enabled. Virtual call on this pointer will raise NPE.
  /// </summary>
  EnableFreedObjectDetection = EnableVirtualCallsOnFreedObjectIntercetion or True;
  // Used internally
  EnableFreeCleanup = EnableFreedObjectDetection;

  /// <summary>
  ///   If enabled (together with <c>MaxStackSize</c>) stack trace is acquired
  ///   also when memory is released.
  /// </summary>
  RecordFreeStackTrace = EnableVirtualCallsOnFreedObjectIntercetion or False;

  /// <summary>
  ///   Enable sanitation of object pointers in a scanner. The scanner will
  ///   put object through series of tests to determine whether the given
  ///   pointer is valid and some basic class fields are readable.
  ///   (See LeakCheck.GetObjectClass)
  /// </summary>
  ScannerEnableObjectPointerSanitation = True;

