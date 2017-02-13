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

const
  LeakCheckEnabled = {$IFNDEF LEAKCHECK_DISABLE}True{$ELSE}False{$ENDIF};
  /// <summary>
  ///   Maximum depth of stack traces. If greater than zero, stack trace will be
  ///   acquired when memory is allocated.
  /// </summary>
  MaxStackSize = 64;

  /// <summary>
  ///   Footer can be used to detect memory corruption and range errors. Enabled
  ///   if greater than 0. (Size in multiples of pointer size)
  /// </summary>
  FooterSize = 0;

  /// <summary>
  ///   If enabled virtual calls on freed object will be intercepted and
  ///   reported.
  /// </summary>
  EnableVirtualCallsOnFreedObjectInterception = True and LeakCheckEnabled;
  /// <summary>
  ///   If enabled interface calls on freed object will be intercepted and
  ///   reported. If not used together with VTablesFastFill significant
  ///   slow-down will be exhibited.
  /// </summary>
  EnableInterfaceCallsOnFreedObjectInterception = False and LeakCheckEnabled;
  /// <summary>
  ///   Since checking for class type is pretty slow, enabling this option will
  ///   use just a faster move but will clear all memory not just objects.
  /// </summary>
  EnableInterfaceVTablesFastFill = True and
    EnableInterfaceCallsOnFreedObjectInterception;
  /// <summary>
  ///   If enabled fake VMT is assigned to freed objects so other utilities do
  ///   not raise AVs if they reach dangling pointer of a freed object (if they
  ///   do freed object checking). If freed object virtual call interception is
  ///   not enabled. Virtual call on this pointer will raise NPE.
  /// </summary>
  EnableFreedObjectDetection = (True or
    EnableVirtualCallsOnFreedObjectInterception or
    EnableInterfaceCallsOnFreedObjectInterception) and LeakCheckEnabled;
  // Used internally
  EnableFreeCleanup = EnableFreedObjectDetection;
  // Used internally
  NeedsIndexTypes =
    EnableVirtualCallsOnFreedObjectInterception or
    EnableInterfaceCallsOnFreedObjectInterception;

  /// <summary>
  ///   If enabled (together with <c>MaxStackSize</c>) stack trace is acquired
  ///   also when memory is released.
  /// </summary>
  RecordFreeStackTrace = False or
    EnableVirtualCallsOnFreedObjectInterception or
    EnableInterfaceCallsOnFreedObjectInterception;

  /// <summary>
  ///   Use separate heap for internal allocations, disable if you leak count
  ///   is getting bigger and the internal functions fail to function.
  ///   Enabling this option will ensure that freed memory of current process
  ///   will not be overwritten by LeakCheck internal data.
  ///   (MS Windows only)
  /// </summary>
  UseInternalHeap = True;

{$IF Declared(TScanner)}
type
  /// <summary>
  ///   Type of sanitation to be done.
  /// </summary>
  TScannerSanitationType = (
    /// <summary>
    ///   No sanitation at all.
    /// </summary>
    None,
    /// <summary>
    ///   Check for <c>TLeckCheck.TFreedObject</c>, but do not perform more
    ///   complex tests (faster).
    /// </summary>
    FreedObject,
    /// <summary>
    ///   The scanner will put object through series of tests to determine
    ///   whether the given pointer is valid and some basic class fields are
    ///   readable (About 10x slower, See <c>LeakCheck.GetObjectClass</c>).
    /// </summary>
    Complex);

const
  /// <summary>
  ///   Enable sanitation of object pointers in a scanner.
  /// </summary>
  ScannerEnableObjectPointerSanitation =
    {$IF EnableFreedObjectDetection}
      TScannerSanitationType.FreedObject
    {$ELSE}
      TScannerSanitationType.Complex
    {$IFEND}
    ;
{$IFEND}
