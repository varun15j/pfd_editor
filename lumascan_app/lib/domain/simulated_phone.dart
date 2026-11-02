/// Debug builds only: a cheaper phone the app can act as, to see how it
/// copes on one while testing on a fast phone (docs/phone-simulation.md).
///
/// An app cannot take memory or cores away from the phone it runs on, so
/// this changes what the app sees and how much it allows itself:
/// - the memory and cores the app reads ([totalMb], [cores]), so the
///   animation profile, the background text check and the camera's frame
///   analysis decide as they would on that phone
/// - how many page pictures render at once ([renderSlots])
/// - the size of the decoded picture cache ([imageCacheMb])
/// - optionally, busy work on the other cores so the app gets about
///   [fastCoreShare] of the CPU ([busyCoresOn])
///
/// The performance overlay compares the app's memory with [memoryBudgetMb].
enum SimulatedPhone {
  /// An Android Go phone: 1 GB, four very slow cores (MT6739 / SC9863A
  /// class). Android marks these as low memory devices.
  go1gb(
    '1 GB Go',
    totalMb: 900,
    cores: 4,
    renderSlots: 1,
    imageCacheMb: 16,
    memoryBudgetMb: 200,
    fastCoreShare: 1,
    lowRamDevice: true,
  ),

  /// A ₹7,000-10,000 phone: 2 GB, four slow cores (Helio A22 / Unisoc class).
  entry2gb(
    '2 GB entry',
    totalMb: 1840,
    cores: 4,
    renderSlots: 1,
    imageCacheMb: 32,
    memoryBudgetMb: 350,
    fastCoreShare: 1.5,
  ),

  /// A ₹12,000-15,000 phone: 4 GB, eight mid cores (Helio G85 / SD 680 class).
  mid4gb('4 GB mid', totalMb: 3650, cores: 8, renderSlots: 2, imageCacheMb: 64, memoryBudgetMb: 700, fastCoreShare: 3);

  const SimulatedPhone(
    this.label, {
    required this.totalMb,
    required this.cores,
    required this.renderSlots,
    required this.imageCacheMb,
    required this.memoryBudgetMb,
    required this.fastCoreShare,
    this.lowRamDevice = false,
  });

  final String label;

  /// All memory in MB as Android would report it on that phone.
  final int totalMb;

  /// CPU cores that phone has.
  final int cores;

  /// Page pictures rendered at the same time.
  final int renderSlots;

  /// Decoded picture cache, in MB (Flutter's default is 100).
  final int imageCacheMb;

  /// About how much memory, in MB, the app can hold in the foreground on
  /// that phone before Android starts closing it.
  final int memoryBudgetMb;

  /// That phone's CPU, in cores of a recent flagship: its whole CPU does
  /// about as much as this many fast cores.
  final double fastCoreShare;

  /// Android counts that phone as a low memory device (Android Go).
  final bool lowRamDevice;

  /// Cores to keep busy on a phone with [realCores] so the app is left with
  /// about [fastCoreShare] of them. At least one core stays free.
  int busyCoresOn(int realCores) => (realCores - fastCoreShare.ceil()).clamp(0, realCores - 1);

  /// Free memory that phone would have when this one has [realFreeMb] of
  /// [realTotalMb]: the same share, never more than this phone has free.
  int freeMbFor({required int realFreeMb, required int realTotalMb}) {
    if (realTotalMb <= 0) return totalMb ~/ 4;
    final share = realFreeMb / realTotalMb;
    return (totalMb * share).round().clamp(0, realFreeMb);
  }
}
