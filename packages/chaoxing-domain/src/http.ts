export type ChaoxingHttpMethod = "GET" | "POST";

export type ChaoxingHttpRequest = {
  method: ChaoxingHttpMethod;
  url: string;
  headers: Record<string, string>;
  form?: Record<string, string>;
};

export type ChaoxingHttpResponse = {
  status: number;
  url: string;
  headers: Record<string, string>;
  body: string;
};

export type ChaoxingHttpClient = {
  send(request: ChaoxingHttpRequest): Promise<ChaoxingHttpResponse>;
};

export const SyncPhase = {
  authentication: "authentication",
  inbox: "inbox",
  noticeDetails: "noticeDetails",
  assignmentDetails: "assignmentDetails",
  courses: "courses",
  finalizing: "finalizing",
} as const;

export type SyncPhase = (typeof SyncPhase)[keyof typeof SyncPhase];

export type SyncProgress = {
  phase: SyncPhase;
  completed: number;
  total: number;
};

export type SyncProgressCallback = (progress: SyncProgress) => void;

export class LocalSyncException extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LocalSyncException";
  }
}

export class AuthenticationExpiredException extends LocalSyncException {
  constructor() {
    super("登录已失效，请重新登录后再同步");
    this.name = "AuthenticationExpiredException";
  }
}

export function headerValue(
  headers: Record<string, string>,
  name: string,
): string | undefined {
  const expected = name.toLowerCase();
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === expected) {
      return value;
    }
  }
  return undefined;
}
