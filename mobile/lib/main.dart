import 'package:flutter/material.dart';

import 'chat/chat_host.dart';
import 'nav.dart';
import 'shell/app_shell.dart';
import 'theme/theme.dart';

void main() => runApp(const KronicleApp());

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
      home: const AppShell(),
      // The route-aware AI chat is a single shell overlay above every route —
      // a draggable bubble + a non-modal floating panel (DESIGN.md decision 34).
      builder: (context, child) => ChatHost(child: child ?? const SizedBox()),
    );
  }
}
