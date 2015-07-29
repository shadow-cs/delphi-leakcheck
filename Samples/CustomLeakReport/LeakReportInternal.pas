unit LeakReportInternal;

interface

uses
  LeakCheck;

var
  /// <summary>
  ///   Some other unit must set this callback. It will be called just before
  ///   LeakCheck finalizes but unlike this unit, it may use some higher level
  ///   functionality. This hacks the way how unit initialization and
  ///   finalization works so use with care.
  /// </summary>
  GetReport: procedure(const snapshot: TLeakCheck.TSnapshot);

implementation

var
  snapshot: TLeakCheck.TSnapshot;

initialization
  // Create a snapshot to hide some accidental allocations made by internal
  // units.
  snapshot.Create;

finalization
  // Run high level stuff from other unit after all other units have finalized
  // (dangerous if you don't know what you're doing).
  GetReport(snapshot);

end.
