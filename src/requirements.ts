export type AssignmentRequirement = {
  sourceTitle: string;
  sourceSendTime: string | null;
  sourceContent: string | null;
  entryUrl: string;
  finalUrl: string;
  pageTitle: string | null;
  status: number;
  courseId: string | null;
  classId: string | null;
  workId: string | null;
  answerId: string | null;
  workStatus: "answering" | "view" | "preview" | "prompt" | "unknown";
  timeWindow: {
    start: string | null;
    end: string | null;
  };
  prompt: string | null;
  questions: AssignmentQuestion[];
};

export type AssignmentQuestion = {
  id: string | null;
  number: string | null;
  type: string | null;
  text: string | null;
  images: string[];
  options: string[];
};

export function parseAssignmentRequirement(input: {
  html: string;
  entryUrl: string;
  finalUrl: string;
  status: number;
  sourceTitle: string;
  sourceSendTime: string | null;
  sourceContent: string | null;
}): AssignmentRequirement {
  const pageTitle = extractTitle(input.html);
  const finalUrl = input.finalUrl;

  return {
    sourceTitle: input.sourceTitle,
    sourceSendTime: input.sourceSendTime,
    sourceContent: input.sourceContent,
    entryUrl: input.entryUrl,
    finalUrl,
    pageTitle,
    status: input.status,
    courseId: readUrlParam(finalUrl, "courseId"),
    classId: readUrlParam(finalUrl, "classId"),
    workId: readUrlParam(finalUrl, "workId") || readHiddenValue(input.html, "workId"),
    answerId:
      readUrlParam(finalUrl, "answerId") || readHiddenValue(input.html, "answerId"),
    workStatus: inferWorkStatus(pageTitle, finalUrl),
    timeWindow: extractTimeWindow(input.html, input.sourceContent),
    prompt: extractPromptText(input.html),
    questions: extractQuestions(input.html),
  };
}

export function extractQuestions(html: string): AssignmentQuestion[] {
  const blocks = html.match(
    /<div\b[^>]*\bclass=["'][^"']*\bquestionLi\b[^"']*["'][\s\S]*?(?=<div\b[^>]*\bclass=["'][^"']*\b(?:padBom50|marBom60)[^"']*\bquestionLi\b|<div\s+id=["']ariaHtmlEnd["']|<div\s+class=["']dtk|$)/gi,
  );
  if (!blocks) {
    return [];
  }

  return blocks.map((block, index) => {
    const heading = block.match(/<h3\b[\s\S]*?<\/h3>/i)?.[0] || block;
    const type =
      readAttribute(block, "typeName") ||
      stripHtml(heading.match(/<span\b[^>]*class=["'][^"']*colorShallow[^"']*["'][^>]*>([\s\S]*?)<\/span>/i)?.[1] || "")
        .replace(/[()（）]/g, "")
        .trim() ||
      null;
    const number = heading.match(/>\s*(\d+)[.．、]/)?.[1] || String(index + 1);
    const text = normalizeQuestionText(heading);
    const images = extractImageUrls(heading);

    return {
      id: block.match(/\bid=["']question([^"']+)["']/i)?.[1] || null,
      number,
      type,
      text,
      images,
      options: [],
    };
  });
}

function extractTimeWindow(
  html: string,
  sourceContent: string | null,
): { start: string | null; end: string | null } {
  const htmlWindow = html.match(
    /作答时间:\s*<em>([^<]+)<\/em>\s*至\s*<em>([^<]+)<\/em>/,
  );
  if (htmlWindow) {
    return { start: htmlWindow[1].trim(), end: htmlWindow[2].trim() };
  }

  const contentWindow = sourceContent?.match(
    /开始时间[:：]\s*([0-9:-]+\s+[0-9:]+)\s+结束时间[:：]\s*([0-9:-]+\s+[0-9:]+)/,
  );
  if (contentWindow) {
    return { start: contentWindow[1].trim(), end: contentWindow[2].trim() };
  }

  return { start: null, end: null };
}

function extractPromptText(html: string): string | null {
  if (!/<title[^>]*>\s*提示\s*<\/title>/i.test(html)) {
    return null;
  }

  const body = html.match(/<body\b[^>]*>([\s\S]*?)<\/body>/i)?.[1] || html;
  return stripHtml(body) || null;
}

function inferWorkStatus(
  pageTitle: string | null,
  finalUrl: string,
): AssignmentRequirement["workStatus"] {
  if (/dowork/.test(finalUrl) || pageTitle === "作业作答") {
    return "answering";
  }
  if (/\/work\/view/.test(finalUrl) || pageTitle === "作业详情") {
    return "view";
  }
  if (/\/work\/preview/.test(finalUrl) || pageTitle === "查看详情") {
    return "preview";
  }
  if (pageTitle === "提示") {
    return "prompt";
  }
  return "unknown";
}

function normalizeQuestionText(headingHtml: string): string | null {
  const withoutType = headingHtml.replace(
    /<span\b[^>]*class=["'][^"']*colorShallow[^"']*["'][^>]*>[\s\S]*?<\/span>/gi,
    " ",
  );
  return stripHtml(withoutType).replace(/^\d+[.．、]\s*/, "").trim() || null;
}

function extractImageUrls(html: string): string[] {
  return [
    ...html.matchAll(/<img\b[^>]*\bsrc=["']([^"']+)["'][^>]*>/gi),
  ]
    .map((match) => match[1])
    .filter((url) => !/popClose|blank|loading/i.test(url))
    .map((url) => normalizeProtocolRelative(url));
}

function normalizeProtocolRelative(url: string): string {
  return url.startsWith("//") ? `https:${url}` : url;
}

function readHiddenValue(html: string, id: string): string | null {
  return (
    html.match(
      new RegExp(`<input[^>]+id=["']${escapeRegExp(id)}["'][^>]+value=["']([^"']*)["']`, "i"),
    )?.[1] || null
  );
}

function readUrlParam(url: string, key: string): string | null {
  try {
    return new URL(url).searchParams.get(key);
  } catch {
    return null;
  }
}

function readAttribute(html: string, name: string): string | null {
  return html.match(new RegExp(`\\b${name}=["']([^"']+)["']`, "i"))?.[1] || null;
}

function extractTitle(html: string): string | null {
  return stripHtml(html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] || "") || null;
}

function stripHtml(value: string): string {
  return value
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim();
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
