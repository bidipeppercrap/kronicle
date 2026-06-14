import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../shell/app_shell.dart';
import '../theme/theme.dart';

/// Server URL + bearer token entry, persisted to encrypted storage (Config).
///
/// Shown as onboarding on a fresh (unconfigured) install via [firstRun], and
/// reachable any time from the Home app bar. Saving verifies the credentials
/// against the Worker before letting a first-run user through.
class SettingsScreen extends StatefulWidget {
  final bool firstRun;
  const SettingsScreen({super.key, this.firstRun = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url =
      TextEditingController(text: Config.apiBaseUrl);
  late final TextEditingController _token =
      TextEditingController(text: Config.apiToken);
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _url.text.trim();
    final token = _token.text.trim();
    if (url.isEmpty || token.isEmpty) {
      setState(() => _error = 'Both the server URL and token are required.');
      return;
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
      setState(() => _error = 'Enter a full URL including http:// or https://.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await Config.save(url: url, token: token);
    // Verify before committing the user — a wrong token/URL is the most likely
    // first-run mistake, and a silent save would just look like a broken app.
    try {
      await ApiClient.instance.listEntities(limit: 1);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Saved, but the server rejected it: $e';
      });
      return;
    }
    if (!mounted) return;
    if (widget.firstRun) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.firstRun ? 'Connect to your vault' : 'Settings'),
        automaticallyImplyLeading: !widget.firstRun,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (widget.firstRun)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Enter the address of your Kronicle Worker and its access '
                'token. The token is stored encrypted on this device and is '
                'never shared.',
                style: TextStyle(
                  fontFamily: KronicleTheme.ui,
                  color: colors.inkFaint,
                  height: 1.4,
                ),
              ),
            ),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'https://kronicle-api.<account>.workers.dev',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _token,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Access token',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                tooltip: _obscure ? 'Show token' : 'Hide token',
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                fontFamily: KronicleTheme.ui,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.firstRun ? 'Connect' : 'Save'),
          ),
        ],
      ),
    );
  }
}
