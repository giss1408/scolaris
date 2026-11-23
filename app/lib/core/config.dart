/// Build-time settings: `--dart-define=API_BASE_URL=... --dart-define=AUTH_BASE_URL=...` (see env/*.json).
abstract final class Config {
  static const apiBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'https://scolaris-api.regisse.com');
  static const authBase = String.fromEnvironment('AUTH_BASE_URL', defaultValue: 'https://auth-api.regisse.com');
  static const product = 'scolaris';
  static const authApp = 'staff';
  static const version = '0.1.0';
}
