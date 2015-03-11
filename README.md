# Delphi LeakCheck #

This is a repository for the Delphi LeakCheck library.

## Basic description ##

LeakCheck is a memory manager extension that adds leak checking functionality. Main difference from the default memory manager is multi-platform implementation of leak checking and DUnit integration.

## Setup ##

* Add `LeakCheck` as the first unit in the project
* Optionally add `LeakCheck.Utils` unit to your project if you want to enable class detection on Posix (or if you want to use any of its utility functions, on mobile you need to add `External\Backtrace\Source` to your search path)
* Enable `ReportMemoryLeaksOnShutdown`
* Run the app

### Testing: ###
* Follow the steps above
* Add `External\DUnit` to your search path so our modifications of the `TestFramework` unit can be found (and the memory manager can plug into DUnit)
* Add `LeakCheck.DUnit` to your project (this is where the the memory manager plugs into DUnit) - there will be compile errors if you do the step above incorrectly.
* Enable leak reporting in your DUnit runner
* Run the tests (I recommend using TestInsight https://bitbucket.org/sglienke/testinsight/ to run the tests, but note that you have to enable leak reporting manually in the `TestInsight.DUnit.RunRegisteredTests` set `result.FailsIfMemoryLeaked` to `True`.)

## Tested on ##
* Win32
* Win64
* Android

## Detailed description ##

Main goal of this library is providing pure pascal implementation of leak checking so it can be used across platforms, it also provides simple cross platform implementation of some basic functionality for synchronization and ansi char handling that is used internally.

It can be used as a replacement of FastMM full debug mode but keep in mind that it is implemented to be safe and platform independent not as fast as possible so its use is recommended for testing only.

### It can create memory snapshots ###

So you can detect leaks between snapshot and last allocation. This is what DUnit integration does. In test results, you'll be able to see detailed leak information including class names, reference count, string and memory dumps.

### It is configurable ####

You can specify (using `TTypeKind`) what type of leak to report but only few kinds are supported:

* `tkLString`, `tkUString` - ignore appropriate string type leaks
* `tkClass` - ignore object leaks (see bellow)
* `tkUnknown` - ignore other types of leaks

In addition to ignoring all classes, each class type can be inspected and ignored separately by assigning `InstanceIgnoredProc` (this can be useful to ignore globally allocated objects from RTL or other sources, like `System.Rtti` collections of objects and alike). This can also be used to ignore unreleased closures (anonymous method pointers). (See `LeakCheck.Utils` for more details).

### It plugs into default ReportMemoryLeaksOnShutdown ###

You can use `ReportMemoryLeaksOnShutdown` on any platforms.

The output varies across platforms:

On Windows message box containing the leaks is shown, this behavior can be changed by defining `NO_MESSAGEBOX` conditional in which case the output will be sent into the IDE Event log (by `OutputDebugString`)

On Android the output is sent to logcat on `WARN` level using `leak` tag. You can use `adb logcat -s leak:*` to see it in console (`adb` can be found under `platform-tools` directory of your Android SDK installation). It is highly recommended to ignore `tkUnknown` leaks on Android (ARC) since the RTL will allocate data for weak references that are mistreated for leaks, `System` will release them during finalization.

### It can detect reference cycles ###

`LeakCheck.DUnitCycle` unit implements cycle detection scanner that if given a reference will scan its reference graph to find any instances creating a reference cycle thus preventing the instance from freeing. This works only for managed fields ie. interfaces (and objects on NextGen). It can scan inside other objects, records, `TValues`, anonymous method closures, static and dynamic arrays (which mean it supports any of the `System.Generics.Collections` types).

You can also manually register `TLeakCheckCycleMonitor` as `TestFramework.MemLeakMonitorClass` to integrate it into your tests.

### Delphi support ###

* Delphi XE7
* Delphi XE6 (Android not tested since XE6 doesn't support Lollipop)

Support for older version may be added in the future.

### Note ###

Although this library was tested on fairly large projects it comes with no guarantees, use at your own risk.

This is a low level library at a very early stage of development so you may expect errors if you use it incorrectly or if you have memory issues in your application that the default memory manager survives somehow. But I'd like to get any input about issues you may run into, but please don't say it crashed my application, include stack traces or other technical information that may help me figure out the problem or better yet, submit patches.

## Thanks to ##

* FastMM team
* DUnit team
* Stefan Glienke - for creation of TestInsight

## License ##

Unless stated explicitly otherwise (in the code), the sources of this library is licensed under Apache License 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
