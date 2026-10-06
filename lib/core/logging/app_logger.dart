import 'dart:collection';
import 'dart:developer' as developer;

import 'log_value.dart';

enum LogLevel { debug, info, warning, error }

/// An event code. Each feature declares its own enum implementing this
/// interface, so event names are compile-time constants:
///
/// ```dart
/// enum SyncLog implements LogEventCode { cycleStarted, pushFailed }
/// ```
abstract interface class LogEventCode implements Enum {}

/// A log entry. Contains no user content by construction.
final class LogRecord {
  const LogRecord({
    required this.level,
    required this.event,
    required this.fields,
    this.errorType,
    this.stackTrace,
  });

  final LogLevel level;

  /// `Type.name`, e.g. `SyncLog.pushFailed`.
  final String event;
  final Map<String, String> fields;

  /// Runtime type of the error. The error **message** is never recorded: it
  /// may contain user input (e.g. a `FormatException` quoting its source).
  final String? errorType;
  final StackTrace? stackTrace;

  String render() {
    final buffer = StringBuffer('[${level.name}] $event');
    fields.forEach((key, value) => buffer.write(' $key=$value'));
    if (errorType != null) buffer.write(' error=$errorType');
    return buffer.toString();
  }
}

/// Receives log records.
abstract interface class LogSink {
  void write(LogRecord record);
}

/// Writes to the developer console (debug builds).
final class DeveloperLogSink implements LogSink {
  const DeveloperLogSink();

  @override
  void write(LogRecord record) => developer.log(
    record.render(),
    name: 'eripoo',
    level: switch (record.level) {
      LogLevel.debug => 500,
      LogLevel.info => 800,
      LogLevel.warning => 900,
      LogLevel.error => 1000,
    },
    stackTrace: record.stackTrace,
  );
}

/// Keeps the most recent records in memory, for future error reports.
final class MemoryLogSink implements LogSink {
  MemoryLogSink({this.capacity = 200});

  final int capacity;
  final _records = ListQueue<LogRecord>();

  List<LogRecord> get records => List.unmodifiable(_records);

  @override
  void write(LogRecord record) {
    if (_records.length == capacity) _records.removeFirst();
    _records.addLast(record);
  }
}

/// Redacting logger. Accepts only event codes and typed [LogValue]s.
final class AppLogger {
  AppLogger({required List<LogSink> sinks, this.minLevel = LogLevel.debug})
    : _sinks = List.unmodifiable(sinks);

  final List<LogSink> _sinks;
  final LogLevel minLevel;

  static final _fieldKey = RegExp(r'^[a-z][a-zA-Z0-9]{0,31}$');

  void debug(LogEventCode event, [Map<String, LogValue> fields = const {}]) =>
      _log(LogLevel.debug, event, fields);

  void info(LogEventCode event, [Map<String, LogValue> fields = const {}]) =>
      _log(LogLevel.info, event, fields);

  void warning(LogEventCode event, [Map<String, LogValue> fields = const {}]) =>
      _log(LogLevel.warning, event, fields);

  /// Records the error **type** and stack trace, never its message.
  void error(
    LogEventCode event,
    Object error,
    StackTrace stackTrace, [
    Map<String, LogValue> fields = const {},
  ]) => _log(
    LogLevel.error,
    event,
    fields,
    errorType: error.runtimeType.toString(),
    stackTrace: stackTrace,
  );

  void _log(
    LogLevel level,
    LogEventCode event,
    Map<String, LogValue> fields, {
    String? errorType,
    StackTrace? stackTrace,
  }) {
    if (level.index < minLevel.index) return;
    final rendered = <String, String>{
      for (final entry in fields.entries)
        if (_fieldKey.hasMatch(entry.key)) entry.key: entry.value.render(),
    };
    final record = LogRecord(
      level: level,
      event: '${event.runtimeType}.${event.name}',
      fields: rendered,
      errorType: errorType,
      stackTrace: stackTrace,
    );
    for (final sink in _sinks) {
      sink.write(record);
    }
  }
}
