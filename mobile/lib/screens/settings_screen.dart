import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
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
          // The AI provider lives server-side (stored in the vault DB, shared
          // with the web app) — only reachable once the connection works, so
          // it stays hidden during first-run onboarding.
          if (!widget.firstRun) ...[
            const SizedBox(height: 36),
            Divider(color: colors.line),
            const SizedBox(height: 24),
            const _AiProviderSection(),
          ],
        ],
      ),
    );
  }
}

/// Edits the server-side AI provider config (key, URL, model) via
/// `/api/settings/ai`. The key is stored in the vault and never echoed back, so
/// the field starts blank and a blank key on save means "leave it as is".
class _AiProviderSection extends StatefulWidget {
  const _AiProviderSection();

  @override
  State<_AiProviderSection> createState() => _AiProviderSectionState();
}

class _AiProviderSectionState extends State<_AiProviderSection> {
  final _key = TextEditingController();
  final _url = TextEditingController();
  final _model = TextEditingController();
  bool _obscure = true;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  AiSettings? _ai;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _key.dispose();
    _url.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final ai = await ApiClient.instance.getAiSettings();
      if (!mounted) return;
      setState(() {
        _ai = ai;
        _url.text = ai.apiUrl ?? '';
        _model.text = ai.model ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save({bool clearKey = false}) async {
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'api_url': _url.text.trim(),
      'model': _model.text.trim(),
    };
    // Blank key field means "keep the saved key" — only send api_key to set a
    // new one or, via the Clear button, to wipe it back to the env fallback.
    if (clearKey) {
      body['api_key'] = '';
    } else if (_key.text.trim().isNotEmpty) {
      body['api_key'] = _key.text.trim();
    }
    try {
      final ai = await ApiClient.instance.updateAiSettings(body);
      if (!mounted) return;
      setState(() {
        _ai = ai;
        _url.text = ai.apiUrl ?? '';
        _model.text = ai.model ?? '';
        _key.clear();
        _saving = false;
      });
      _toast(clearKey ? 'AI key cleared' : 'AI settings saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Save failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 18, color: colors.accentInk),
            const SizedBox(width: 8),
            Text(
              'AI provider',
              style: TextStyle(
                fontFamily: KronicleTheme.ui,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Any OpenAI-compatible chat-completions endpoint — DeepSeek, OpenAI, '
          'OpenRouter, a local model… Stored in the vault, shared with the web app.',
          style: TextStyle(
            fontFamily: KronicleTheme.ui,
            fontSize: 12.5,
            height: 1.4,
            color: colors.inkFaint,
          ),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_loadError != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  "Couldn't load AI settings: $_loadError",
                  style: TextStyle(
                    fontFamily: KronicleTheme.ui,
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          )
        else
          _form(colors),
      ],
    );
  }

  Widget _form(KronicleColors colors) {
    final ai = _ai!;
    final hint = ai.apiKeyHint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _key,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'API key',
            hintText: ai.apiKeySet ? 'saved (${hint ?? '…'})' : 'sk-…',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              tooltip: _obscure ? 'Show key' : 'Hide key',
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          switch (ai.apiKeySource) {
            'settings' =>
              "A key is saved here${hint != null ? ' ($hint)' : ''}. Enter a new "
                  'one to replace it — it’s stored in the vault and never shown in full.',
            'env' =>
              "Using the Worker’s env key. Saving one here overrides it.",
            _ => 'No key configured — AI chat is off until you add one.',
          },
          style: TextStyle(
            fontFamily: KronicleTheme.ui,
            fontSize: 12,
            height: 1.4,
            color: colors.inkFaint,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'API URL',
            hintText: 'https://api.deepseek.com',
            helperText: 'Include the version prefix, e.g. …/v1. Blank = default.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _model,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Model',
            hintText: 'deepseek-chat',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            if (ai.apiKeySource == 'settings')
              TextButton.icon(
                onPressed: _saving ? null : () => _save(clearKey: true),
                icon: const Icon(Icons.delete_outline, size: 18),
                style: TextButton.styleFrom(foregroundColor: colors.rejected),
                label: const Text('Clear key'),
              ),
            const Spacer(),
            FilledButton(
              onPressed: _saving ? null : () => _save(),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}
