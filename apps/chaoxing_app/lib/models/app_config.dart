class AppConfig {
  const AppConfig({
    required this.baseUrl,
    required this.token,
    required this.refreshMinutes,
  });

  final String baseUrl;
  final String token;
  final int refreshMinutes;

  bool get isConfigured => baseUrl.trim().isNotEmpty && token.trim().isNotEmpty;

  AppConfig copyWith({String? baseUrl, String? token, int? refreshMinutes}) {
    return AppConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      token: token ?? this.token,
      refreshMinutes: refreshMinutes ?? this.refreshMinutes,
    );
  }

  static const empty = AppConfig(baseUrl: '', token: '', refreshMinutes: 60);
}
