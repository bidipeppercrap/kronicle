import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api/api_client.dart';

/// Runtime configuration: the Worker base URL and bearer token.
///
/// These are entered in-app (Settings) and persisted with
/// `flutter_secure_storage` — the token sits encrypted at rest behind the
/// Android Keystore, and the **APK embeds no secret**, so the build can be
/// distributed (DESIGN.md, Auth). There is still no in-app login: each install
/// holds its own token; Cloudflare Access gates the *web* app, not the phone.
///
/// `--dart-define` values remain as *dev seeds* only — they pre-fill an
/// unconfigured install so `flutter run` against the local Worker just works:
///
///   flutter run \
///     --dart-define=KRONICLE_API_URL=http://10.0.2.2:8787 \
///     --dart-define=KRONICLE_API_TOKEN=dev-token
///
/// A release build for distribution passes no defines, so the seeds are empty
/// and the app opens onto the Settings screen until configured.
class Config {
  Config._();

  // Build-time seeds (empty unless passed via --dart-define for local dev).
  static const String _seedUrl =
      String.fromEnvironment('KRONICLE_API_URL', defaultValue: '');
  static const String _seedToken =
      String.fromEnvironment('KRONICLE_API_TOKEN', defaultValue: '');

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kUrl = 'api_base_url';
  static const _kToken = 'api_token';

  static String _url = '';
  static String _token = '';

  /// In-memory accessors — kept synchronous so [ApiClient] stays unchanged.
  static String get apiBaseUrl => _url;
  static String get apiToken => _token;

  /// Whether the app has enough to talk to the Worker. Gates onboarding.
  static bool get isConfigured => _url.isNotEmpty && _token.isNotEmpty;

  /// Load persisted settings into memory at startup, falling back to the
  /// build-time seeds for an unconfigured (e.g. fresh dev) install.
  static Future<void> load() async {
    _url = await _storage.read(key: _kUrl) ?? _seedUrl;
    _token = await _storage.read(key: _kToken) ?? _seedToken;
  }

  /// Persist new settings, update the in-memory values, and drop the response
  /// cache so nothing answered under the old server/token survives.
  static Future<void> save({required String url, required String token}) async {
    _url = url.trim();
    _token = token.trim();
    await _storage.write(key: _kUrl, value: _url);
    await _storage.write(key: _kToken, value: _token);
    ApiClient.instance.clearCache();
  }
}
