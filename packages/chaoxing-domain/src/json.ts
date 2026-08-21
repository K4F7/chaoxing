export function readString(
  json: Record<string, unknown>,
  key: string,
): string {
  const value = json[key];
  return typeof value === "string" ? value : "";
}

export function readNullableString(
  json: Record<string, unknown>,
  key: string,
): string | null {
  const value = json[key];
  return typeof value === "string" && value.length > 0 ? value : null;
}

export function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

export function stringOrEmpty(value: unknown): string {
  return value == null ? "" : String(value);
}

export function nullableString(value: unknown): string | null {
  const text = stringOrEmpty(value);
  return text.length === 0 ? null : text;
}

export function mapValue(map: Record<string, unknown>, key: string): unknown {
  const expected = key.toLowerCase();
  for (const [entryKey, entryValue] of Object.entries(map)) {
    if (entryKey.toLowerCase() === expected) {
      return entryValue;
    }
  }
  return undefined;
}

export function firstMapText(
  map: Record<string, unknown>,
  keys: readonly string[],
): string | null {
  for (const key of keys) {
    const text = nullableString(mapValue(map, key));
    if (text !== null) {
      return text;
    }
  }
  return null;
}

export function isTruthy(value: unknown): boolean {
  if (value === true || value === 1) {
    return true;
  }
  const text = stringOrEmpty(value).trim().toLowerCase();
  return text === "true" || text === "1" || text === "ok" || text === "success";
}

export function hasSuccessfulApiStatus(response: Record<string, unknown>): boolean {
  if (Object.prototype.hasOwnProperty.call(response, "status")) {
    return isTruthy(response.status);
  }
  if (Object.prototype.hasOwnProperty.call(response, "success")) {
    return isTruthy(response.success);
  }
  return false;
}

export function collectStringValues(value: unknown, depth = 0): string[] {
  if (depth > 8) {
    return [];
  }
  if (typeof value === "string") {
    return [value];
  }
  if (Array.isArray(value)) {
    return value.flatMap((child) => collectStringValues(child, depth + 1));
  }
  const record = asRecord(value);
  if (record === null) {
    return [];
  }
  return Object.values(record).flatMap((child) =>
    collectStringValues(child, depth + 1),
  );
}

export function normalizeLimit(
  value: number,
  fallback: number,
  maximum: number,
): number {
  if (value < 1) {
    return fallback;
  }
  return value > maximum ? maximum : value;
}
