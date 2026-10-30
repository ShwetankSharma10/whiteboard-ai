import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'features/board/data/app_check_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with the generated FlutterFire options if configured
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    if (!options.apiKey.startsWith('YOUR_') &&
        !options.projectId.startsWith('your-')) {
      await Firebase.initializeApp(options: options);
      debugPrint('[Firebase] Initialized - cloud sync enabled.');
    } else {
      debugPrint(
        '[Firebase] Placeholder config detected, running in local mode.',
      );
    }
  } catch (e) {
    debugPrint('[Firebase] Not configured, running in local mode ($e).');
  }

  // Initialize Firebase App Check & Play Integrity security
  await AppCheckService.initialize();

  runApp(const ProviderScope(child: SyncBoardApp()));
}

class SyncBoardApp extends ConsumerWidget {
  const SyncBoardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'SyncBoard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
