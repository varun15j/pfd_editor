/// How long each step of making a picture took, in microseconds, for the
/// debug image-loading profiler. Plain data, so it crosses isolates.
class StageTimes {
  final Map<String, int> micros = {};

  /// Runs [step] and adds its time to [stage].
  T time<T>(String stage, T Function() step) {
    final sw = Stopwatch()..start();
    try {
      return step();
    } finally {
      add(stage, sw.elapsedMicroseconds);
    }
  }

  void add(String stage, int elapsedMicros) => micros[stage] = (micros[stage] ?? 0) + elapsedMicros;
}
