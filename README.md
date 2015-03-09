# Delphi LeakCheck #

This is a repository for the Delphi LeakCheck library.

## Basic description ##

LeakCheck is a memory manager extension that adds leak checking functionality. Main difference from the default memory manager is multi-platform implementation of leak checking and DUnit integration.

## Setup ##

* Add `LeakCheck` as the first unit in the project
* Optionally add `LeakCheck.Utils` unit to your project if you want to enable class detection on Posix (or if you want to use any of its utility functions)
* Enable `ReportMemoryLeaksOnShutdown`
* Run the app

### Testing: ###
* Follow the steps above
* Add `External\DUnit` to your search path so our modifications of the `TestFramework` unit can be found (and the memory manager can plug into DUnit)
* Add `LeakCheck.DUnit` to your project (this is where the the memory manager plugs into DUnit) - there will be compile errors if you do the step above incorrectly.
* Enable leak reporting in your DUnit runner
* Run the tests

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
* `tkLString`, `tkUString` - ignore apropriate string type leaks
* `tkClass` - ignore object leaks (see bellow)
* `tkUnknown` - ignore other types of leaks

In addition to ignoring all classes, each class type can be inspected and ignored separately byt assigning `InstanceIgnoredProc` (this can be usefull to ignore globally allocated objects from RTL or other sources, like `System.Rtti` collections of objects and alike). This can also be used to ignore unreleased closures (anonymous method pointers). (See `LeakCheck.Utils` for more details).

### It plugs into default ReportMemoryLeaksOnShutdown ###

You can use `ReportMemoryLeaksOnShutdown` on any platforms.

The output varies across platforms:

On Windows message box containing the leaks is shown, this behavior can be changed by defining `NO_MESSAGEBOX` conditional in which case the output will be sent into the IDE Event log (by `OutputDebugString`)

On Android the output is sent to logcat on `WARN` level using `leak` tag. You can use `adb logcat -s leak:*` to see it in console (`adb` can be found under `platform-tools` directory of your Android SDK installation). It is highly recommended to ignore `tkUnknown` leaks on Android (ARC) since the RTL will allocate data for weak references that are mistreated for leaks, `System` will release them during finalization.

## Thanks to ##

* FastMM team
* DUnit team

## License ##

Unless stated explicitly otherwise (in the code), the sources of this library is licensed under Apache License 2.0 (http://www.apache.org/licenses/LICENSE-2.0).