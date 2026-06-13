/// Runtime configuration, supplied at build/run time with --dart-define.
///
/// The Flutter APK embeds the bearer token — an accepted risk for a personal
/// device (DESIGN.md, Auth). There is no in-app login: Cloudflare Access gates
/// the *web* app, the phone just carries the token.
///
///   flutter run \
///     --dart-define=KRONICLE_API_URL=http://10.0.2.2:8787 \
///     --dart-define=KRONICLE_API_TOKEN=dev-token
///
/// Defaults target the local Worker from the Android emulator, where
/// 10.0.2.2 is the host machine's 127.0.0.1 (DESIGN.md dev quirk: the Worker
/// binds 127.0.0.1, not localhost). On a physical device over USB/Wi-Fi,
/// pass the host's LAN IP or the deployed kronicle-api.workers.dev URL.
class Config {
  static const String apiBaseUrl = String.fromEnvironment(
    'KRONICLE_API_URL',
    defaultValue: 'http://10.0.2.2:8787',
  );

  static const String apiToken = String.fromEnvironment(
    'KRONICLE_API_TOKEN',
    defaultValue: 'dev-token',
  );
}
