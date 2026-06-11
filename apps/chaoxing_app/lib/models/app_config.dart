class AppConfig {
  const AppConfig({
    required this.cookie,
    required this.inboxPageLimit,
    required this.inboxItemLimit,
    required this.refreshMinutes,
    required this.remindersEnabled,
    this.legacyWorkerConfigDetected = false,
  });

  final String cookie;
  final int inboxPageLimit;
  final int inboxItemLimit;
  final int refreshMinutes;
  final bool remindersEnabled;
  final bool legacyWorkerConfigDetected;

  bool get isConfigured => cookie.trim().isNotEmpty;

  AppConfig copyWith({
    String? cookie,
    int? inboxPageLimit,
    int? inboxItemLimit,
    int? refreshMinutes,
    bool? remindersEnabled,
    bool? legacyWorkerConfigDetected,
  }) {
    return AppConfig(
      cookie: cookie ?? this.cookie,
      inboxPageLimit: inboxPageLimit ?? this.inboxPageLimit,
      inboxItemLimit: inboxItemLimit ?? this.inboxItemLimit,
      refreshMinutes: refreshMinutes ?? this.refreshMinutes,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      legacyWorkerConfigDetected:
          legacyWorkerConfigDetected ?? this.legacyWorkerConfigDetected,
    );
  }

  static const empty = AppConfig(
    cookie: '',
    inboxPageLimit: 3,
    inboxItemLimit: 60,
    refreshMinutes: 60,
    remindersEnabled: true,
  );
}
