/// What the opt-in statistics count (decision D7): a fixed list, the same
/// as the server's (migration 20261022000001_usage_stats.sql). Never
/// content, never an identifier.
enum UsageEvent {
  appOpened('app_opened'),
  diagnosticCompleted('diagnostic_completed'),
  questCompleted('quest_completed'),
  missionCompleted('mission_completed'),
  pdfExported('pdf_exported');

  const UsageEvent(this.token);
  final String token;
}
