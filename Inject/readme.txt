This diretory holds sources for LeakCheck injector.

The injector may be used to inject LeakCheck.Inject.dll into any process using
the LeakCheck.Injector.exe.

The process must be properly configured (built with RTL runtime package) and the
injection must be done in given time: Put a breakpoint at System._StartExe on
the InitUnits line. Step into InitUnits and step through the initialization code
as soon as System.pas has been initialized (it should mostly be the second
initialization code to execute - SysInit being the first, it is recommended
that this is done by hand using Step into and verifying the correct location)
and the code returns back to InitUnits run LeakCheck.Injector.exe with correct
PID and immediately hit Run in the debugger. LeakCheck.Injector.exe will inject
the DLL into given process (you shold be able to verify this using Event Log).

If done corectly all allocations will now be directed though LeakCheck. Note
that this is EXPERIMENTAL feature, finalization will not work correctly and
if the initialization is done incorerctly your app will raise exceptions or
hang.

Why is this useful?
If you're having memory issues (AVs) in an application that loads your module
as DLL or BPL and uses runtime packages, you may track your memory using
LeakCheck even if the host application do not include LeakCheck. Only terminate
the debugging before finalization is ran. All released classes and other memory
issues will be reported. You may also use LeakCheck leak reporting using the
snapshot feature (check no dangling pointers originate from your library when it
frees). Using LeakCheck while debugging BDS IDE packages and experts is
supported!

USE AT YOUR OWN RISK!!!
