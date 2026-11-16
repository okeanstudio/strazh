import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/core/utils/date_time_utils.dart';

void main() {
  test('parses UTC timestamps into the device local timezone', () {
    const timestamp = '2026-10-17T19:14:00.000Z';

    expect(parseDateTimeSafely(timestamp), DateTime.parse(timestamp).toLocal());
    expect(parseDateTimeSafely(timestamp).isUtc, isFalse);
  });

  test('converts UTC DateTime values into the device local timezone', () {
    final timestamp = DateTime.utc(2026, 10, 17, 19, 14);

    expect(parseDateTimeSafely(timestamp), timestamp.toLocal());
    expect(parseDateTimeSafely(timestamp).isUtc, isFalse);
  });
}
