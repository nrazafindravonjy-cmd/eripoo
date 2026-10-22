import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/core/logging/log_value.dart';
import 'package:flutter_test/flutter_test.dart';

enum _TestLog implements LogEventCode { started, failed }

enum _Reason { timeout }

void main() {
  late MemoryLogSink sink;
  late AppLogger logger;

  setUp(() {
    sink = MemoryLogSink(capacity: 3);
    logger = AppLogger(sinks: [sink]);
  });

  test('records event code and typed fields', () {
    logger.info(_TestLog.started, {
      'count': const LogInt(3),
      'ok': const LogBool(true),
      'took': const LogDuration(Duration(milliseconds: 42)),
      'reason': const LogEnum(_Reason.timeout),
    });
    final record = sink.records.single;
    expect(record.event, '_TestLog.started');
    expect(record.render(), contains('count=3'));
    expect(record.render(), contains('took=42ms'));
    expect(record.render(), contains('reason=timeout'));
  });

  test('never records an exception message (sentinel)', () {
    const sentinel = 'SENTINEL-mon-projet-secret';
    try {
      throw const FormatException(sentinel);
    } catch (e, s) {
      logger.error(_TestLog.failed, e, s);
    }
    final record = sink.records.single;
    expect(record.errorType, 'FormatException');
    expect(record.render(), isNot(contains(sentinel)));
    expect(record.fields.values.join(), isNot(contains(sentinel)));
  });

  test('redacts identifiers that are not technical ids', () {
    logger.info(_TestLog.started, {
      'record': const LogId('Rakoto a perdu son travail'),
      'valid': const LogId('0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a'),
      'step': const LogContentId('q03.s02'),
      'bad': const LogContentId('Mon idée : vendre du riz'),
    });
    final fields = sink.records.single.fields;
    expect(fields['record'], '<redacted>');
    expect(fields['valid'], '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a');
    expect(fields['step'], 'q03.s02');
    expect(fields['bad'], '<redacted>');
  });

  test('drops fields whose key is not an identifier', () {
    logger.info(_TestLog.started, {'free text key!': const LogInt(1)});
    expect(sink.records.single.fields, isEmpty);
  });

  test('respects the minimum level', () {
    final quiet = AppLogger(sinks: [sink], minLevel: LogLevel.warning);
    quiet.info(_TestLog.started);
    quiet.warning(_TestLog.started);
    expect(sink.records.map((r) => r.level), [LogLevel.warning]);
  });

  test('memory sink keeps only the most recent records', () {
    for (var i = 0; i < 5; i++) {
      logger.info(_TestLog.started, {'i': LogInt(i)});
    }
    expect(sink.records.map((r) => r.fields['i']), ['2', '3', '4']);
  });
}
