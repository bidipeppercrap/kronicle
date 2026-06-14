import 'package:flutter/material.dart';

import 'chat/chat_host.dart';
import 'config.dart';
import 'nav.dart';
import 'screens/settings_screen.dart';
import 'shell/app_shell.dart';
import 'theme/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Config.load();
  runApp(const KronicleApp());
}

class KronicleApp extends StatelessWidget {
  const KronicleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kronicle',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: KronicleTheme.light(),
      darkTheme: KronicleTheme.dark(),
      themeMode: ThemeMode.system,
      // A fresh / distributed install has no token yet — open onto Settings
      // until the user connects to their Worker (DESIGN.md, Auth).
      home: Config.isConfigured
          ? const AppShell()
          : const SettingsScreen(firstRun: true),
      // The route-aware AI chat is a single shell overlay above every route —
      // a draggable bubble + a non-modal floating panel (DESIGN.md decision 34).
      builder: (context, child) => ChatHost(child: child ?? const SizedBox()),
    );
  }
}
