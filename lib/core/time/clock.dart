/// Injectable time source (tests control it). Display only: time is never
/// used to order synchronised changes (docs/OFFLINE_SYNC.md §2).
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now().toUtc();
