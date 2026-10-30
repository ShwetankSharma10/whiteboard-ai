import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:boardmate/features/board/data/app_check_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Stage S9: Security Hardening & App Check', () {
    test(
      'AppCheckService initializes safely and falls back in local environment',
      () async {
        const service = AppCheckService();

        // In unit test environment, Firebase Core is not initialized
        await AppCheckService.initialize();

        // Should not throw and should handle uninitialized state gracefully
        final token = await service.getToken();
        expect(token, isNull);
      },
    );

    test(
      'ProGuard / R8 rules file exists and contains security directives',
      () {
        final file = File('android/app/proguard-rules.pro');
        expect(
          file.existsSync(),
          isTrue,
          reason: 'proguard-rules.pro must exist',
        );

        final content = file.readAsStringSync();
        expect(content, contains('com.google.firebase'));
        expect(content, contains('com.google.firebase.appcheck'));
        expect(content, contains('play.core.integrity'));
        expect(content, contains('io.flutter'));
        expect(content, contains('com.boardmate.boardmate'));
      },
    );

    test(
      'GitHub Actions CI workflow file exists and defines test and build gates',
      () {
        final file = File('.github/workflows/ci.yml');
        expect(file.existsSync(), isTrue, reason: 'ci.yml must exist');

        final content = file.readAsStringSync();
        expect(content, contains('flutter analyze'));
        expect(content, contains('flutter test'));
        expect(content, contains('flutter build web'));
        expect(content, contains('flutter build apk'));
      },
    );
  });
}
