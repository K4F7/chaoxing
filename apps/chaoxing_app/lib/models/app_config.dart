class AppConfig {
  const AppConfig({
    required this.cookie,
    required this.inboxPageLimit,
    required this.inboxItemLimit,
    required this.refreshMinutes,
    required this.remindersEnabled,
    this.showNotificationDetails = false,
    this.courseSourcesEnabled = true,
    this.courseLimit = 20,
    this.legacyWorkerConfigDetected = false,
  });

  final String cookie;
  final int inboxPageLimit;
  final int inboxItemLimit;
  final int refreshMinutes;
  final bool remindersEnabled;
  final bool showNotificationDetails;
  final bool courseSourcesEnabled;
  final int courseLimit;
  final bool legacyWorkerConfigDetected;

  bool get isConfigured => cookie.trim().isNotEmpty;

  AppConfig normalized() {
    return AppConfig(
      cookie: cookie.trim(),
      inboxPageLimit: _boundedOrDefault(inboxPageLimit, 1, 20, 3),
      inboxItemLimit: _boundedOrDefault(inboxItemLimit, 1, 500, 60),
      refreshMinutes: _normalizedRefreshMinutes(refreshMinutes),
      remindersEnabled: remindersEnabled,
      showNotificationDetails: showNotificationDetails,
      courseSourcesEnabled: courseSourcesEnabled,
      courseLimit: _boundedOrDefault(courseLimit, 1, 100, 20),
      legacyWorkerConfigDetected: legacyWorkerConfigDetected,
    );
  }

  AppConfig copyWith({
    String? cookie,
    int? inboxPageLimit,
    int? inboxItemLimit,
    int? refreshMinutes,
    bool? remindersEnabled,
    bool? showNotificationDetails,
    bool? courseSourcesEnabled,
    int? courseLimit,
    bool? legacyWorkerConfigDetected,
  }) {
    return AppConfig(
      cookie: cookie ?? this.cookie,
      inboxPageLimit: inboxPageLimit ?? this.inboxPageLimit,
      inboxItemLimit: inboxItemLimit ?? this.inboxItemLimit,
      refreshMinutes: refreshMinutes ?? this.refreshMinutes,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      showNotificationDetails:
          showNotificationDetails ?? this.showNotificationDetails,
      courseSourcesEnabled: courseSourcesEnabled ?? this.courseSourcesEnabled,
      courseLimit: courseLimit ?? this.courseLimit,
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
    showNotificationDetails: false,
    courseSourcesEnabled: true,
    courseLimit: 20,
  );
}

int _boundedOrDefault(int value, int minimum, int maximum, int fallback) {
  if (value < minimum) {
    return fallback;
  }
  return value > maximum ? maximum : value;
}

int _normalizedRefreshMinutes(int value) {
  if (value == 0) {
    return 0;
  }
  if (value < 0) {
    return 60;
  }
  if (value < 15) {
    return 15;
  }
  return value > 180 ? 180 : value;
}
