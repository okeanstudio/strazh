import 'package:flutter_test/flutter_test.dart';
import 'package:strazh/core/services/app_update_service.dart';

void main() {
  test('detects a server version newer than the installed app', () {
    expect(AppUpdateService.isNewerVersion('1.1.0', '3.0.179'), isTrue);
    expect(AppUpdateService.isNewerVersion('3.0.178', '3.0.179'), isTrue);
  });

  test('does not report an update for the same or an older version', () {
    expect(AppUpdateService.isNewerVersion('3.0.179', '3.0.179'), isFalse);
    expect(AppUpdateService.isNewerVersion('3.1.0', '3.0.179'), isFalse);
  });
}
