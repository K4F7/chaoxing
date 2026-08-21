import { MODERN_COURSE_LIST_ORIGIN } from "./constants";
import type { CourseSpace } from "./course-catalog";
import {
  classList,
  decodeBasicHtmlEntities,
  findTaggedElements,
  firstTextBySelectors,
  normalizeWhitespace,
  stripHtml,
} from "./html";
import { asRecord, firstMapText, nullableString } from "./json";
import { isTrustedChaoxingUrl } from "./url-policy";
import { readUrlParamAny, resolveTrustedUrl } from "./urls";

export type CourseTaskLink = {
  url: string;
  title: string;
  status: string;
};

export function isActionableCourseTask(link: CourseTaskLink): boolean {
  return !["completed", "submitted", "expired", "view", "preview"].includes(
    link.status.toLowerCase(),
  );
}

export function findCourseInteractionUrl(html: string): string | null {
  const matches = html.matchAll(
    /\bdataurl=["']([^"']*\/visit\/interaction[^"']*)["']/gi,
  );
  for (const match of matches) {
    const raw = decodeBasicHtmlEntities(match[1]);
    const url = new URL(raw, MODERN_COURSE_LIST_ORIGIN).toString();
    if (isTrustedChaoxingUrl(url)) {
      return url;
    }
  }
  return null;
}

export function parseCourseSpaces(body: string): CourseSpace[] {
  const htmlCourses = parseCourseSpacesFromHtml(body);
  if (htmlCourses.length > 0) {
    return htmlCourses;
  }

  let decoded: unknown;
  try {
    decoded = JSON.parse(body);
  } catch {
    throw new Error("课程列表返回格式不正确");
  }

  const courses = new Map<string, CourseSpace>();
  const visit = (value: unknown, inheritedCpi = ""): void => {
    if (Array.isArray(value)) {
      for (const child of value) {
        visit(child, inheritedCpi);
      }
      return;
    }
    const record = asRecord(value);
    if (record === null) {
      return;
    }
    const cpi = firstMapText(record, ["cpi", "personId"]) ?? inheritedCpi;
    const title = firstMapText(record, ["courseName", "name", "title"]) ?? "";
    const rawUrl = firstMapText(record, ["courseSquareUrl", "courseUrl", "url"]);
    const normalizedUrl =
      rawUrl === null
        ? null
        : decodeBasicHtmlEntities(rawUrl).replaceAll("\\/", "/");
    const courseId =
      (normalizedUrl === null
        ? null
        : readUrlParamAny(normalizedUrl, ["courseId", "courseid"])) ??
      firstMapText(record, ["courseId", "courseid"]);
    const classId =
      (normalizedUrl === null
        ? null
        : readUrlParamAny(normalizedUrl, ["classId", "clazzId", "clazzid"])) ??
      firstMapText(record, ["classId", "clazzId", "clazzid", "key"]);
    if (courseId !== null && classId !== null) {
      courses.set(`${courseId}:${classId}`, {
        courseId,
        classId,
        cpi,
        title: title.length === 0 ? `课程 ${courseId}` : title,
      });
    }
    for (const child of Object.values(record)) {
      visit(child, cpi);
    }
  };

  visit(decoded);
  if (courses.size === 0) {
    throw new Error("课程列表中未找到可同步课程");
  }
  return [...courses.values()];
}

export function parseCourseTaskLinks(
  html: string,
  baseUrl: string,
  fallbackTitle: string,
): CourseTaskLink[] {
  const linksByUrl = new Map<string, CourseTaskLink>();
  for (const element of findTaggedElements(
    html,
    (_tag, attrs) => attrs.href !== undefined || attrs.data !== undefined,
  )) {
    const rawUrl = element.attrs.href ?? element.attrs.data;
    if (rawUrl === undefined) {
      continue;
    }
    const url = normalizeCourseTaskUrl(rawUrl, baseUrl);
    if (url === null) {
      continue;
    }
    const selectedTitle = firstTextBySelectors(element.innerHtml, [
      "p",
      "dl dt",
      ".course-name",
      ".task-title",
      ".title",
    ]);
    const text = element.text.trim();
    const status = inferListedTaskStatus(element.innerHtml, text);
    const candidate: CourseTaskLink = {
      url,
      title: normalizeWhitespace(
        selectedTitle ?? (text.length === 0 ? fallbackTitle : text),
      ),
      status,
    };
    const previous = linksByUrl.get(url);
    if (previous === undefined || (previous.status === "unknown" && status !== "unknown")) {
      linksByUrl.set(url, candidate);
    }
  }

  const elementPattern =
    /<(?:a|div|li)\b[^>]*\b(?:href|data)=["']([^"']+)["'][^>]*>([\s\S]*?)<\/(?:a|div|li)>/gi;
  for (const match of html.matchAll(elementPattern)) {
    const url = normalizeCourseTaskUrl(match[1], baseUrl);
    if (url === null || linksByUrl.has(url)) {
      continue;
    }
    const title = stripHtml(match[2]);
    linksByUrl.set(url, {
      url,
      title: title.length === 0 ? fallbackTitle : title,
      status: "unknown",
    });
  }

  const attributePattern = /(?:href|data)=["']([^"']+)["']/gi;
  for (const match of html.matchAll(attributePattern)) {
    const url = normalizeCourseTaskUrl(match[1], baseUrl);
    if (url !== null && !linksByUrl.has(url)) {
      linksByUrl.set(url, { url, title: fallbackTitle, status: "unknown" });
    }
  }
  return [...linksByUrl.values()];
}

function parseCourseSpacesFromHtml(body: string): CourseSpace[] {
  if (!body.includes("courseList") && !body.includes("courseid")) {
    return [];
  }
  const list =
    findTaggedElements(
      body,
      (tag, attrs) => tag === "ul" && attrs.id === "courseList",
    )[0]?.innerHtml ?? body;
  const courses = new Map<string, CourseSpace>();
  for (const item of findTaggedElements(
    list,
    (tag, attrs) => tag === "li" && classList(attrs.class).includes("course"),
  )) {
    const courseId = item.attrs.courseid?.trim() ?? "";
    const classId = item.attrs.clazzid?.trim() ?? "";
    const cpi = item.attrs.personid?.trim() ?? "";
    if (courseId.length === 0 || classId.length === 0 || cpi.length === 0) {
      continue;
    }
    const title =
      firstTextBySelectors(item.innerHtml, [".course-name"]) ?? item.text;
    courses.set(`${courseId}:${classId}`, {
      courseId,
      classId,
      cpi,
      title: title.length === 0 ? `课程 ${courseId}` : title,
    });
  }
  return [...courses.values()];
}

function inferListedTaskStatus(innerHtml: string, text: string): string {
  const normalized = normalizeWhitespace(text);
  const imageMarksExpired = findTaggedElements(
    innerHtml,
    (tag) => tag === "img",
  ).some((image) => (image.attrs.src ?? "").toLowerCase().includes("ks_02"));
  if (imageMarksExpired || /已过期|已结束|不可作答/.test(normalized)) {
    return "expired";
  }
  if (/待批阅|已提交/.test(normalized)) {
    return "submitted";
  }
  if (/已完成|已批阅/.test(normalized)) {
    return "completed";
  }
  return "unknown";
}

function normalizeCourseTaskUrl(rawUrl: string, baseUrl: string): string | null {
  const decoded = decodeBasicHtmlEntities(rawUrl).replaceAll("\\/", "/").trim();
  const resolved = resolveTrustedUrl(decoded, baseUrl);
  if (resolved === null) {
    return null;
  }
  const text = resolved.toString();
  if (/\/task-list\b/i.test(text)) {
    return null;
  }
  const hasTaskId =
    readUrlParamAny(text, ["taskrefId", "workId", "examId"]) !== null;
  const hasTaskPath = /\/(?:work|exam|exam-ans|mooc-ans)\b/i.test(text);
  return hasTaskId && hasTaskPath ? text : null;
}

export { nullableString };
