import { asRecord } from "./json";

export type CourseSpace = {
  courseId: string;
  classId: string;
  cpi: string;
  title: string;
};

export type CoursePreference = {
  course: CourseSpace;
  monitored: boolean;
};

export type CourseCatalog = {
  courses: readonly CoursePreference[];
  lastDiscoveredAt: Date | null;
};

export const emptyCourseCatalog: CourseCatalog = {
  courses: [],
  lastDiscoveredAt: null,
};

export function courseSpaceKey(course: CourseSpace): string {
  return `${course.courseId}:${course.classId}`;
}

export function courseSpaceFromJson(json: Record<string, unknown>): CourseSpace {
  return {
    courseId: typeof json.courseId === "string" ? json.courseId : "",
    classId: typeof json.classId === "string" ? json.classId : "",
    cpi: typeof json.cpi === "string" ? json.cpi : "",
    title: typeof json.title === "string" ? json.title : "",
  };
}

export function courseSpaceToJson(course: CourseSpace): Record<string, string> {
  return {
    courseId: course.courseId,
    classId: course.classId,
    cpi: course.cpi,
    title: course.title,
  };
}

export function coursePreferenceFromJson(
  json: Record<string, unknown>,
): CoursePreference {
  return {
    course: courseSpaceFromJson(asRecord(json.course) ?? {}),
    monitored: json.monitored !== false,
  };
}

export function coursePreferenceToJson(
  preference: CoursePreference,
): Record<string, unknown> {
  return {
    course: courseSpaceToJson(preference.course),
    monitored: preference.monitored,
  };
}

export function catalogHasRecords(catalog: CourseCatalog): boolean {
  return catalog.courses.length > 0;
}

export function monitoredCourses(catalog: CourseCatalog): CourseSpace[] {
  return catalog.courses
    .filter((preference) => preference.monitored)
    .map((preference) => preference.course);
}

export function mergeDiscoveredCourses(
  catalog: CourseCatalog,
  discovered: readonly CourseSpace[],
  discoveredAt: Date,
): CourseCatalog {
  const existing = new Map(
    catalog.courses.map((value) => [courseSpaceKey(value.course), value]),
  );
  const merged: CoursePreference[] = [];
  const discoveredKeys = new Set<string>();
  for (const course of discovered) {
    if (course.courseId.length === 0 || course.classId.length === 0) {
      continue;
    }
    const key = courseSpaceKey(course);
    discoveredKeys.add(key);
    merged.push({
      course,
      monitored: existing.get(key)?.monitored ?? true,
    });
  }
  merged.push(
    ...catalog.courses.filter(
      (value) => !discoveredKeys.has(courseSpaceKey(value.course)),
    ),
  );
  return { courses: merged, lastDiscoveredAt: discoveredAt };
}

export function setCourseMonitored(
  catalog: CourseCatalog,
  courseKey: string,
  monitored: boolean,
): CourseCatalog {
  return {
    courses: catalog.courses.map((value) =>
      courseSpaceKey(value.course) === courseKey
        ? { ...value, monitored }
        : value,
    ),
    lastDiscoveredAt: catalog.lastDiscoveredAt,
  };
}

export function isSameLocalDate(left: Date, right: Date): boolean {
  return (
    left.getFullYear() === right.getFullYear() &&
    left.getMonth() === right.getMonth() &&
    left.getDate() === right.getDate()
  );
}

export function shouldDiscoverCourses(input: {
  catalog: CourseCatalog;
  now: Date;
  forceDiscovery: boolean;
}): boolean {
  return (
    input.forceDiscovery ||
    !catalogHasRecords(input.catalog) ||
    input.catalog.lastDiscoveredAt === null ||
    !isSameLocalDate(input.catalog.lastDiscoveredAt, input.now)
  );
}

export function courseCatalogFromJson(
  json: Record<string, unknown>,
): CourseCatalog {
  const rawCourses = json.courses;
  return {
    courses: Array.isArray(rawCourses)
      ? rawCourses
          .map((value) => asRecord(value))
          .filter((value): value is Record<string, unknown> => value !== null)
          .map(coursePreferenceFromJson)
          .filter(
            (value) =>
              value.course.courseId.length > 0 &&
              value.course.classId.length > 0,
          )
      : [],
    lastDiscoveredAt:
      typeof json.lastDiscoveredAt === "string"
        ? (() => {
            const parsed = new Date(json.lastDiscoveredAt);
            return Number.isNaN(parsed.getTime()) ? null : parsed;
          })()
        : null,
  };
}

export function courseCatalogToJson(
  catalog: CourseCatalog,
): Record<string, unknown> {
  return {
    courses: catalog.courses.map(coursePreferenceToJson),
    ...(catalog.lastDiscoveredAt
      ? { lastDiscoveredAt: catalog.lastDiscoveredAt.toISOString() }
      : {}),
  };
}
