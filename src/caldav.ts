import {
  buildCalendarObjectIcs,
  buildTodoObjectIcs,
  type SyncItem,
} from "./sync";

const DAV_NS = "DAV:";
const CALDAV_NS = "urn:ietf:params:xml:ns:caldav";
const ROOT = "/caldav/";
const PRINCIPAL = "/caldav/principals/me/";
const HOME = "/caldav/calendars/me/";
const DEADLINES = "/caldav/calendars/me/deadlines/";
const TODOS = "/caldav/calendars/me/todos/";

export type CalDavOptions = {
  request: Request;
  itemsLoader: () => Promise<SyncItem[]>;
};

type CalendarCollection = {
  path: string;
  displayName: string;
  component: "VEVENT" | "VTODO";
  objectBuilder: (item: SyncItem) => string;
};

const COLLECTIONS: CalendarCollection[] = [
  {
    path: DEADLINES,
    displayName: "学习通截止日期",
    component: "VEVENT",
    objectBuilder: buildCalendarObjectIcs,
  },
  {
    path: TODOS,
    displayName: "学习通待办",
    component: "VTODO",
    objectBuilder: buildTodoObjectIcs,
  },
];

export async function handleCalDav(options: CalDavOptions): Promise<Response> {
  const url = new URL(options.request.url);
  const path = normalizePath(url.pathname);

  if (url.pathname === "/.well-known/caldav") {
    return redirectResponse(new URL(ROOT, url.origin).toString());
  }

  if (options.request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: davHeaders(),
    });
  }

  if (options.request.method === "PROPFIND") {
    const depth = Number(options.request.headers.get("Depth") || "0");
    const items = depth > 0 && findCollection(path) ? await options.itemsLoader() : [];
    return propfindResponse(path, depth, items);
  }

  if (options.request.method === "REPORT") {
    return reportResponse(path, await options.itemsLoader());
  }

  if (options.request.method === "GET" || options.request.method === "HEAD") {
    return getObjectResponse(path, await options.itemsLoader(), options.request.method);
  }

  return new Response("method not allowed", {
    status: 405,
    headers: {
      ...davHeaders(),
      Allow: "OPTIONS, PROPFIND, REPORT, GET, HEAD",
    },
  });
}

function propfindResponse(path: string, depth: number, items: SyncItem[]): Response {
  const responses = [propForPath(path)];
  if (depth > 0) {
    if (path === ROOT) {
      responses.push(propForPath(PRINCIPAL), propForPath(HOME));
    } else if (path === HOME) {
      responses.push(...COLLECTIONS.map((collection) => propForPath(collection.path)));
    } else {
      const collection = findCollection(path);
      if (collection) {
        responses.push(
          ...items
            .filter((item) => item.dueAt)
            .map((item) => {
              const data = collection.objectBuilder(item);
              return responseXml(
                `${collection.path}${objectName(item, collection.component)}`,
                [
                  prop("getetag", etagFor(data)),
                  prop("getcontenttype", "text/calendar; charset=utf-8"),
                  prop("getcontentlength", String(new TextEncoder().encode(data).length)),
                ].join(""),
              );
            }),
        );
      }
    }
  }

  return xmlResponse(multistatus(responses.filter(Boolean).join("")));
}

function reportResponse(path: string, items: SyncItem[]): Response {
  const collection = findCollection(path);
  if (!collection) {
    return new Response("not found", { status: 404, headers: davHeaders() });
  }

  const responses = items
    .filter((item) => item.dueAt)
    .map((item) => {
      const data = collection.objectBuilder(item);
      const href = `${collection.path}${objectName(item, collection.component)}`;
      return responseXml(href, objectProps(collection, data));
    })
    .join("");

  return xmlResponse(multistatus(responses));
}

function getObjectResponse(
  path: string,
  items: SyncItem[],
  method: string,
): Response {
  const collection = COLLECTIONS.find((candidate) => path.startsWith(candidate.path));
  if (!collection) {
    return new Response("not found", { status: 404, headers: davHeaders() });
  }

  const item = items.find((candidate) => {
    return path === `${collection.path}${objectName(candidate, collection.component)}`;
  });
  if (!item) {
    return new Response("not found", { status: 404, headers: davHeaders() });
  }

  const data = collection.objectBuilder(item);
  return new Response(method === "HEAD" ? null : data, {
    headers: {
      ...davHeaders(),
      "Content-Type": "text/calendar; charset=utf-8",
      ETag: etagFor(data),
    },
  });
}

function propForPath(path: string): string {
  if (path === ROOT) {
    return responseXml(
      ROOT,
      [
        prop("displayname", "学习通 CalDAV"),
        prop("resourcetype", `${empty("collection")}`),
        propNs("current-user-principal", DAV_NS, hrefXml(PRINCIPAL)),
        propNs("principal-URL", DAV_NS, hrefXml(PRINCIPAL)),
        propNs("calendar-home-set", CALDAV_NS, hrefXml(HOME)),
      ].join(""),
    );
  }

  if (path === PRINCIPAL) {
    return responseXml(
      PRINCIPAL,
      [
        prop("displayname", "学习通"),
        prop("resourcetype", `${empty("collection")}${empty("principal")}`),
        propNs("calendar-home-set", CALDAV_NS, hrefXml(HOME)),
      ].join(""),
    );
  }

  if (path === HOME) {
    return responseXml(
      HOME,
      [
        prop("displayname", "学习通日历"),
        prop("resourcetype", empty("collection")),
      ].join(""),
    );
  }

  const collection = findCollection(path);
  if (!collection) {
    return "";
  }

  return responseXml(
    collection.path,
    [
      prop("displayname", collection.displayName),
      prop("resourcetype", `${empty("collection")}<C:calendar/>`),
      propNs("supported-calendar-component-set", CALDAV_NS, `<C:comp name="${collection.component}"/>`),
      propNs("calendar-description", CALDAV_NS, `${collection.displayName}，由学习通通知自动生成。`),
      propNs("calendar-timezone", CALDAV_NS, "Asia/Shanghai"),
    ].join(""),
  );
}

function objectProps(collection: CalendarCollection, data: string): string {
  return [
    prop("getetag", etagFor(data)),
    prop("getcontenttype", "text/calendar; charset=utf-8"),
    prop("getcontentlength", String(new TextEncoder().encode(data).length)),
    propNs("calendar-data", CALDAV_NS, escapeXml(data)),
    propNs("supported-calendar-component-set", CALDAV_NS, `<C:comp name="${collection.component}"/>`),
  ].join("");
}

function findCollection(path: string): CalendarCollection | null {
  return COLLECTIONS.find((collection) => path === collection.path) || null;
}

function objectName(item: SyncItem, component: "VEVENT" | "VTODO"): string {
  return `${component === "VTODO" ? "todo-" : ""}${item.id}.ics`;
}

function normalizePath(path: string): string {
  if (path === ROOT.slice(0, -1) || path === HOME.slice(0, -1)) {
    return `${path}/`;
  }
  if (path === DEADLINES.slice(0, -1) || path === TODOS.slice(0, -1)) {
    return `${path}/`;
  }
  return path;
}

function multistatus(value: string): string {
  return `<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="${DAV_NS}" xmlns:C="${CALDAV_NS}">${value}</D:multistatus>`;
}

function responseXml(href: string, props: string): string {
  return `<D:response><D:href>${escapeXml(href)}</D:href><D:propstat><D:prop>${props}</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>`;
}

function prop(name: string, value: string): string {
  return propNs(name, DAV_NS, value);
}

function propNs(name: string, namespace: string, value: string): string {
  const prefix = namespace === CALDAV_NS ? "C" : "D";
  return `<${prefix}:${name}>${value}</${prefix}:${name}>`;
}

function empty(name: string): string {
  return `<D:${name}/>`;
}

function hrefXml(href: string): string {
  return `<D:href>${escapeXml(href)}</D:href>`;
}

function xmlResponse(value: string): Response {
  return new Response(value, {
    status: 207,
    headers: {
      ...davHeaders(),
      "Content-Type": "application/xml; charset=utf-8",
    },
  });
}

function redirectResponse(location: string): Response {
  return new Response(null, {
    status: 301,
    headers: {
      Location: location,
    },
  });
}

function davHeaders(): Record<string, string> {
  return {
    DAV: "1, 3, calendar-access",
    "MS-Author-Via": "DAV",
  };
}

function etagFor(value: string): string {
  let hash = 5381;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 33) ^ value.charCodeAt(index);
  }
  return `"${(hash >>> 0).toString(36)}"`;
}

function escapeXml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
