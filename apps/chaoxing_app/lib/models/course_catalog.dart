class CourseSpace {
  const CourseSpace({
    required this.courseId,
    required this.classId,
    required this.cpi,
    required this.title,
  });

  final String courseId;
  final String classId;
  final String cpi;
  final String title;

  String get key => '$courseId:$classId';

  factory CourseSpace.fromJson(Map<String, dynamic> json) {
    return CourseSpace(
      courseId: json['courseId'] is String ? json['courseId'] as String : '',
      classId: json['classId'] is String ? json['classId'] as String : '',
      cpi: json['cpi'] is String ? json['cpi'] as String : '',
      title: json['title'] is String ? json['title'] as String : '',
    );
  }

  Map<String, dynamic> toJson() => {
    'courseId': courseId,
    'classId': classId,
    'cpi': cpi,
    'title': title,
  };
}

class CoursePreference {
  const CoursePreference({required this.course, this.monitored = true});

  final CourseSpace course;
  final bool monitored;

  CoursePreference copyWith({CourseSpace? course, bool? monitored}) {
    return CoursePreference(
      course: course ?? this.course,
      monitored: monitored ?? this.monitored,
    );
  }

  factory CoursePreference.fromJson(Map<String, dynamic> json) {
    final rawCourse = json['course'];
    return CoursePreference(
      course: CourseSpace.fromJson(
        rawCourse is Map
            ? rawCourse.cast<String, dynamic>()
            : const <String, dynamic>{},
      ),
      monitored: json['monitored'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
    'course': course.toJson(),
    'monitored': monitored,
  };
}

class CourseCatalog {
  const CourseCatalog({this.courses = const [], this.lastDiscoveredAt});

  final List<CoursePreference> courses;
  final DateTime? lastDiscoveredAt;

  static const empty = CourseCatalog();

  bool get hasRecords => courses.isNotEmpty;

  List<CourseSpace> get monitoredCourses => courses
      .where((preference) => preference.monitored)
      .map((preference) => preference.course)
      .toList();

  CourseCatalog mergeDiscovered(
    List<CourseSpace> discovered, {
    required DateTime discoveredAt,
  }) {
    final existing = {for (final value in courses) value.course.key: value};
    final merged = <CoursePreference>[];
    final discoveredKeys = <String>{};
    for (final course in discovered) {
      if (course.courseId.isEmpty || course.classId.isEmpty) {
        continue;
      }
      discoveredKeys.add(course.key);
      merged.add(
        CoursePreference(
          course: course,
          monitored: existing[course.key]?.monitored ?? true,
        ),
      );
    }
    merged.addAll(
      courses.where((value) => !discoveredKeys.contains(value.course.key)),
    );
    return CourseCatalog(courses: merged, lastDiscoveredAt: discoveredAt);
  }

  CourseCatalog setMonitored(String courseKey, bool monitored) {
    return CourseCatalog(
      courses: courses
          .map(
            (value) => value.course.key == courseKey
                ? value.copyWith(monitored: monitored)
                : value,
          )
          .toList(),
      lastDiscoveredAt: lastDiscoveredAt,
    );
  }

  factory CourseCatalog.fromJson(Map<String, dynamic> json) {
    final rawCourses = json['courses'];
    return CourseCatalog(
      courses: rawCourses is List
          ? rawCourses
                .whereType<Map>()
                .map(
                  (value) =>
                      CoursePreference.fromJson(value.cast<String, dynamic>()),
                )
                .where(
                  (value) =>
                      value.course.courseId.isNotEmpty &&
                      value.course.classId.isNotEmpty,
                )
                .toList()
          : const [],
      lastDiscoveredAt: DateTime.tryParse(
        json['lastDiscoveredAt'] is String
            ? json['lastDiscoveredAt'] as String
            : '',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'courses': courses.map((value) => value.toJson()).toList(),
    if (lastDiscoveredAt != null)
      'lastDiscoveredAt': lastDiscoveredAt!.toIso8601String(),
  };
}
