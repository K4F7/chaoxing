import { COURSE_API_ORIGIN, NOTICE_ORIGIN } from "./constants";
import type { CourseSpace } from "./course-catalog";
import { isTrustedChaoxingUri } from "./url-policy";

export function tryParseUrl(value: string, base?: string): URL | null {
  try {
    return base === undefined ? new URL(value) : new URL(value, base);
  } catch {
    return null;
  }
}

export function readUrlParam(url: string, key: string): string | null {
  const parsed = tryParseUrl(url);
  if (parsed === null) {
    return null;
  }
  const value = parsed.searchParams.get(key);
  return value && value.length > 0 ? value : null;
}

export function readUrlParamAny(
  url: string,
  keys: readonly string[],
): string | null {
  const parsed = tryParseUrl(url);
  if (parsed === null) {
    return null;
  }
  for (const key of keys) {
    for (const [entryKey, entryValue] of parsed.searchParams.entries()) {
      if (entryKey.toLowerCase() === key.toLowerCase() && entryValue.length > 0) {
        return entryValue;
      }
    }
  }
  return null;
}

export function isWorkOrExamLink(link: string): boolean {
  return (
    /workOrExam=(?:work|exam)/i.test(link) ||
    /\/(?:work|exam|exam-ans|mooc-ans)\b/i.test(link) ||
    readUrlParamAny(link, ["taskrefId", "workId", "examId", "taskId", "jobid"]) !==
      null
  );
}

export function buildCourseTaskListUrl(
  course: CourseSpace,
  source: "course_work" | "course_exam",
): string {
  const path =
    source === "course_exam"
      ? "/mooc-ans/exam/phone/task-list"
      : "/work/task-list";
  const url = new URL(path, COURSE_API_ORIGIN);
  url.searchParams.set("courseId", course.courseId);
  url.searchParams.set("classId", course.classId);
  url.searchParams.set("cpi", course.cpi);
  return url.toString();
}

export function buildNoticeDetailPageUrl(
  id: string,
  sendTag: unknown,
): string {
  const url = new URL(`/pc/notice/${id}/detail`, NOTICE_ORIGIN);
  if (sendTag != null) {
    url.searchParams.set("sendTag", String(sendTag));
  }
  return url.toString();
}

export function resolveTrustedUrl(
  raw: string,
  baseUrl: string,
): URL | null {
  const decoded = raw.trim();
  const candidate = decoded.startsWith("//") ? `https:${decoded}` : decoded;
  const parsed = tryParseUrl(candidate) ?? tryParseUrl(candidate, baseUrl);
  if (parsed === null || !isTrustedChaoxingUri(parsed)) {
    return null;
  }
  return parsed;
}
