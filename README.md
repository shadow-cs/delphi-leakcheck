# Delphi LeakCheck #

This is a repository for the Delphi LeakCheck library.

## Basic description ##

LeakCheck is a memory manager extension that adds leak checking functionality. Main difference from the default memory manager is multi-platform implementation of leak checking with DUnit and DUnitX integration.

## Main features ##

* Multi-platform leak checking
* Testing framework integration (DUnit and DUnit), compares true allocations not just allocation size
* Allocation stack tracing (with symbols)
* Allocation snapshots (not thread safe)
* Independent object structure scanning (with object cycle detection, complete allocation visualization and graph generation - with aid of Graphviz)
* Complex leak ignoring options (including object graph ignore from entry point)

## Setup ##

* Add `LeakCheck` as the first unit in the project
* Optionally add `LeakCheck.Utils` unit to your project if you want to enable class detection on Posix (or if you want to use any of its utility functions, on mobile you need to add `External\Backtrace\Source` to your search path)
* Enable `ReportMemoryLeaksOnShutdown`
* Run the app

### Testing: ###
* Follow the steps above

DUnit :

* Add `External\DUnit` to your search path so our modifications of the `TestFramework` unit can be found (and the memory manager can plug into DUnit)
* Add `LeakCheck.DUnit` to your project (this is where the the memory manager plugs into DUnit) - there will be compile errors if you do the step above incorrectly.
* Enable leak reporting in your DUnit runner
* Run the tests (I recommend using TestInsight https://bitbucket.org/sglienke/testinsight/ to run the tests, but note that you have to enable leak reporting manually in the `TestInsight.DUnit.RunRegisteredTests` set `result.FailsIfMemoryLeaked` to `True`.)

DUnitX:

* Add `DUnitX.MemoryLeakMonitor.LeakCheck` to your project (it will register the default memory monitor)
* Run the tests

I recommend checking the latest DUnitX sources with extended reporting options (commit 918608a) but other versions should be supported.

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

`LeakCheck.DUnitCycle` and `DUnitX.MemoryLeakMonitor.LeakCheckCycle` units implement cycle detection scanner that if given a reference will scan its reference graph to find any instances creating a reference cycle thus preventing the instance from freeing. This works only for managed fields ie. interfaces (and objects on NextGen) or if used together with `UseExtendedRtti` (enabled manually) any field with RTTI is supported. It can scan inside other objects, records, `TValues`, anonymous method closures, static and dynamic arrays (which mean it supports any of the `System.Generics.Collections` types).

You need to manually register `TLeakCheckCycleMonitor` (or any descendants with more scanning options) as `TestFramework.MemLeakMonitorClass` to integrate it into your DUnit tests.

You need to manually register `TDUnitXLeakCheckCycleMemoryLeakMonitor` (or any descendants with more scanning options) into the DUnitX's IoC container to integrate it into your DUnitX tests.

    TDUnitXIoC.DefaultContainer.RegisterType<IMemoryLeakMonitor>(
      function : IMemoryLeakMonitor
      begin
        result := TDUnitXLeakCheckGraphMemoryLeakMonitor.Create;
      end);

Cycle detector scanner can optionaly use extended RTTI information (see `TScanFlags`), so scanning for object (not just using interfaces) cycles in non ARC environment is possible, but note that RTTI generation is required, for objects not supporting extended RTTI (ie. closures), there is a fallback mechanism to classic solution. When using extended RTTI, the reference scanner may output field names holding the references as well (and add it as named edges for Graphviz, see bellow).

This extension isn't tied to the memory manager itself and doesn't need it to run. So it can be used to generate object graphs in any application at any point of its execution, just give it appropriate entry point reference.

### It can generate visual cycle representation ###

`LeakCheck.Cycle` supports format flags in the `TCycle.ToString` method that can be set to generate Graphviz DOT format output. Combined with `TLeakCheckCycleGraphMonitor` that appends another needed information, test cycle output can be copied to a file (make sure to copy only the graph specification not the entire error message) and converted using Graphviz (`dot -O -T png cycle.dot`) to visual representation. You can also select different memory monitor `TLeakCheckGraphMonitor` which will generate full reference tree not just cycles.

![Cycle visualization](https://bitbucket.org/repo/B876R6/images/1334247331-cycle.png)

### It can acquire stack traces ###

If registered, LeakCheck memory manager may acquire stack traces when some block is allocated which is then displayed in leak output either as pure addresses or formatted (if trace formatter is registered). Multiple stack tracers and formatters are available. Make sure to configure your compiler/linker properly.

It is configurable via the `LeakCheck.Configuration.inc` include file also `GetStackTraceProc` has to be set to one of the predefined implementations or custom one. To get pretty-printed stack traces make sure to also register `GetStackTraceFormatterProc`. Keep in mind that different implementations have some limitations and requirements:

The safest solution is WinApi based stack tracer and MAP file based formatter (MAP file needs to be enabled in the linker settings and symbols generation must be enabled in the compiler to get line numbers etc.). 

JCL implementation offers better stack traces (RAW) on Win32 and offers more options while formatting the output (debug symbols, MAP file, etc.) but needs external caching.

Android implementation cannot show symbols right away but the formatter allows you to feed the output directly to `addr2line` utility which will then output the symbols and line numbers.

### Delphi support ###

* Delphi XE7
* Delphi XE6 (Android not tested since XE6 doesn't support Lollipop)
* Delphi XE5 (Android not tested)
* Delphi XE

Delphi between XE and XE6 should also work but was not tested. If you find any problems, please create an issue.

Support for older version will not be added, some other versions may work but I will not test them nor will I add any patches that would add support to older versions.

### Note ###

Although this library was tested on fairly large projects it comes with no guarantees, use at your own risk.

This is a low level library at a very early stage of development so you may expect errors if you use it incorrectly or if you have memory issues in your application that the default memory manager survives somehow. But I'd like to get any input about issues you may run into, but please don't say it crashed my application, include stack traces or other technical information that may help me figure out the problem or better yet, submit patches.

### Known issues ###

On Android (or actually any platform that needs `libicu`) the program may cause SEGFAULT during System unit finalization. This is caused by System allocating some memory before the memory manager is initialized and not freeing it properly (there are more comments in the `LeakCheck` source code). This should now be prevented in cases when the application doesn't leak any memory.

## Thanks to ##

* FastMM team
* DUnit team
* Stefan Glienke - for creation of TestInsight

## License ##

Unless stated explicitly otherwise (in the code), the sources of this library is licensed under Apache License 2.0 (http://www.apache.org/licenses/LICENSE-2.0).