import 'package:supabase_flutter/supabase_flutter.dart';

/// Errors raised by the staff_* functions (migration
/// 20261023000001_backoffice.sql), by code.
enum StaffError { conflict, mfaRequired, notStaff, invalid, other }

class StaffException implements Exception {
  const StaffException(this.error);
  final StaffError error;
}

StaffError staffErrorFor(String message) => switch (message) {
  'version_conflict' => StaffError.conflict,
  'mfa_required' => StaffError.mfaRequired,
  'not_staff' => StaffError.notStaff,
  'invalid_document' ||
  'invalid_translation' ||
  'invalid_period' => StaffError.invalid,
  _ => StaffError.other,
};

class DocumentSummary {
  const DocumentSummary(this.path, this.version);
  final String path;
  final int version;
}

class UsageRow {
  const UsageRow(this.day, this.event, this.appVersion, this.count);
  final String day;
  final String event;
  final String appVersion;

  /// Null when the total is under 10 (hidden by the server).
  final int? count;
}

/// The back-office's only access to the database: the staff_* functions.
class StaffApi {
  StaffApi(this._client);
  final SupabaseClient _client;

  Future<Object?> _call(String fn, [Map<String, Object?>? params]) async {
    try {
      return await _client.rpc<Object?>(fn, params: params);
    } on PostgrestException catch (e) {
      throw StaffException(staffErrorFor(e.message));
    }
  }

  Future<List<String>> myRoles() async =>
      ((await _call('staff_my_roles'))! as List<Object?>).cast<String>();

  Future<List<DocumentSummary>> documents() async {
    final rows = (await _call('staff_list_documents'))! as List<Object?>;
    return [
      for (final r in rows.cast<Map<String, Object?>>())
        DocumentSummary(r['path']! as String, r['version']! as int),
    ];
  }

  Future<(Object, int)?> document(String path) async {
    final rows =
        (await _call('staff_get_document', {'p_path': path}))! as List<Object?>;
    if (rows.isEmpty) return null;
    final row = rows.first! as Map<String, Object?>;
    return (row['body']!, row['version']! as int);
  }

  Future<int> saveDocument(
    String path,
    Object body,
    int expectedVersion,
  ) async =>
      (await _call('staff_save_document', {
            'p_path': path,
            'p_body': body,
            'p_expected_version': expectedVersion,
          }))!
          as int;

  Future<int> setTranslation(
    String path,
    List<String> pointer,
    String locale,
    String text,
    int expectedVersion,
  ) async =>
      (await _call('staff_set_translation', {
            'p_path': path,
            'p_pointer': pointer,
            'p_locale': locale,
            'p_text': text,
            'p_expected_version': expectedVersion,
          }))!
          as int;

  Future<List<UsageRow>> usage(DateTime from, DateTime to) async {
    String d(DateTime t) => t.toIso8601String().substring(0, 10);
    final rows =
        (await _call('staff_usage_stats', {'p_from': d(from), 'p_to': d(to)}))!
            as List<Object?>;
    return [
      for (final r in rows.cast<Map<String, Object?>>())
        UsageRow(
          r['day']! as String,
          r['event']! as String,
          r['app_version']! as String,
          r['count'] as int?,
        ),
    ];
  }
}
