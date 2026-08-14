import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  group('Traceparent', () {
    test('formats W3C header', () {
      const tp = Traceparent(
        traceId: '0af7651916cd43dd8448eb211c80319c',
        spanId: 'b7ad6b7169203331',
        sampled: true,
      );
      expect(
        tp.toHeader(),
        '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01',
      );
    });

    test('parses valid header', () {
      final parsed = Traceparent.tryParse(
        '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01',
      );
      expect(parsed, isNotNull);
      expect(parsed!.traceId, '0af7651916cd43dd8448eb211c80319c');
      expect(parsed.spanId, 'b7ad6b7169203331');
      expect(parsed.sampled, isTrue);
    });

    test('rejects all-zero ids and junk', () {
      expect(
        Traceparent.tryParse(
          '00-00000000000000000000000000000000-b7ad6b7169203331-01',
        ),
        isNull,
      );
      expect(Traceparent.tryParse('not-a-header'), isNull);
      expect(Traceparent.tryParse(null), isNull);
      expect(Traceparent.tryParse(''), isNull);
    });

    test('generates valid non-zero ids', () {
      final traceId = Traceparent.newTraceId();
      final spanId = Traceparent.newSpanId();
      expect(Traceparent.isTraceId(traceId), isTrue);
      expect(Traceparent.isSpanId(spanId), isTrue);
      expect(traceId, isNot('0' * 32));
      expect(spanId, isNot('0' * 16));
    });
  });
}
