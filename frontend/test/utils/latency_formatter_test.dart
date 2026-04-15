import 'package:flutter_test/flutter_test.dart';
import 'package:work_order/utils/latency_formatter.dart';

void main() {
  group('formatStageLatency', () {
    test('null renders as em-dash', () {
      expect(formatStageLatency(null), '—');
    });

    test('0 to 99 renders as less than 1s', () {
      expect(formatStageLatency(0), '<1s');
      expect(formatStageLatency(50), '<1s');
      expect(formatStageLatency(99), '<1s');
    });

    test('100 to 999 renders with one decimal', () {
      expect(formatStageLatency(100), '0.1s');
      expect(formatStageLatency(500), '0.5s');
      expect(formatStageLatency(999), '1.0s');
    });

    test('1000 to 59999 renders seconds with one decimal', () {
      expect(formatStageLatency(1000), '1.0s');
      expect(formatStageLatency(1200), '1.2s');
      expect(formatStageLatency(22400), '22.4s');
      expect(formatStageLatency(59999), '60.0s');
    });

    test('60000 and above renders minutes and seconds', () {
      expect(formatStageLatency(60000), '1m 0s');
      expect(formatStageLatency(75000), '1m 15s');
      expect(formatStageLatency(125000), '2m 5s');
    });
  });
}
