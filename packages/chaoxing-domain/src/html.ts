const VOID_TAGS = new Set([
  "area",
  "base",
  "br",
  "col",
  "embed",
  "hr",
  "img",
  "input",
  "link",
  "meta",
  "param",
  "source",
  "track",
  "wbr",
]);

export function decodeBasicHtmlEntities(value: string): string {
  return value
    .replaceAll("&nbsp;", " ")
    .replaceAll("&#160;", " ")
    .replaceAll("&ensp;", " ")
    .replaceAll("&emsp;", " ")
    .replaceAll("&amp;", "&")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&#39;", "'");
}

export function stripHtml(value: string): string {
  return decodeBasicHtmlEntities(
    value
      .replace(/<style[\s\S]*?<\/style>/gi, " ")
      .replace(/<script[\s\S]*?<\/script>/gi, " ")
      .replace(/<[^>]+>/g, " "),
  )
    .replace(/\s+/g, " ")
    .trim();
}

export function normalizeWhitespace(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

export function parseAttributes(raw: string): Record<string, string> {
  const attrs: Record<string, string> = {};
  const pattern =
    /([^\s=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;
  for (const match of raw.matchAll(pattern)) {
    attrs[match[1].toLowerCase()] = decodeBasicHtmlEntities(
      match[2] ?? match[3] ?? match[4] ?? "",
    );
  }
  return attrs;
}

export type HtmlElement = {
  tag: string;
  attrs: Record<string, string>;
  innerHtml: string;
  text: string;
};

export function classList(value: string | undefined): string[] {
  return (value ?? "").split(/\s+/).filter(Boolean);
}

function findMatchingClose(html: string, start: number, tag: string): number {
  const open = new RegExp(`<${tag}\\b[^>]*>`, "gi");
  const close = new RegExp(`</${tag}\\s*>`, "gi");
  let depth = 1;
  let cursor = start;
  while (depth > 0 && cursor < html.length) {
    open.lastIndex = cursor;
    close.lastIndex = cursor;
    const nextOpen = open.exec(html);
    const nextClose = close.exec(html);
    if (nextClose === null) {
      return html.length;
    }
    if (
      nextOpen !== null &&
      nextOpen.index < nextClose.index &&
      !nextOpen[0].trimEnd().endsWith("/>")
    ) {
      depth += 1;
      cursor = nextOpen.index + nextOpen[0].length;
    } else {
      depth -= 1;
      if (depth === 0) {
        return nextClose.index;
      }
      cursor = nextClose.index + nextClose[0].length;
    }
  }
  return html.length;
}

export function findTaggedElements(
  html: string,
  predicate: (tag: string, attrs: Record<string, string>) => boolean,
): HtmlElement[] {
  const results: HtmlElement[] = [];
  const openTag = /<([a-zA-Z][\w:-]*)\b([^>]*)>/g;
  let match: RegExpExecArray | null;
  while ((match = openTag.exec(html)) !== null) {
    const tag = match[1].toLowerCase();
    const attrs = parseAttributes(match[2] ?? "");
    if (!predicate(tag, attrs)) {
      continue;
    }
    if (match[0].trimEnd().endsWith("/>") || VOID_TAGS.has(tag)) {
      results.push({ tag, attrs, innerHtml: "", text: "" });
      continue;
    }
    const startInner = match.index + match[0].length;
    const close = findMatchingClose(html, startInner, tag);
    const innerHtml = html.slice(startInner, close);
    results.push({ tag, attrs, innerHtml, text: stripHtml(innerHtml) });
  }
  return results;
}

export function firstTextBySelectors(
  innerHtml: string,
  selectors: readonly string[],
): string | undefined {
  for (const selector of selectors) {
    if (selector === "p") {
      const element = findTaggedElements(innerHtml, (tag) => tag === "p")[0];
      if (element?.text) {
        return element.text;
      }
      continue;
    }
    if (selector === "dl dt") {
      const definition = findTaggedElements(innerHtml, (tag) => tag === "dl")[0];
      const term = definition
        ? findTaggedElements(definition.innerHtml, (tag) => tag === "dt")[0]
        : undefined;
      if (term?.text) {
        return term.text;
      }
      continue;
    }
    if (selector.startsWith(".")) {
      const className = selector.slice(1);
      const element = findTaggedElements(innerHtml, (_tag, attrs) =>
        classList(attrs.class).includes(className),
      )[0];
      if (element?.text) {
        return element.text;
      }
    }
  }
  return undefined;
}

export function extractPageTitle(html: string): string | null {
  const match = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (match?.[1] === undefined) {
    return null;
  }
  const title = decodeBasicHtmlEntities(match[1]).replace(/\s+/g, " ").trim();
  return title.length === 0 ? null : title;
}

export function decodeBase64Utf8(value: string): string {
  const bytes = Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}
