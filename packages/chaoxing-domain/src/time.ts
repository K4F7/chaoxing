/** Match Dart `DateTime.toIso8601String()` for a local wall-clock value. */
export function toLocalIso8601(date: Date): string {
  const pad = (value: number, width = 2): string =>
    String(value).padStart(width, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}.${pad(date.getMilliseconds(), 3)}`;
}

export function addHours(date: Date, hours: number): Date {
  return new Date(date.getTime() + hours * 60 * 60 * 1000);
}

export function addDays(date: Date, days: number): Date {
  return addHours(date, days * 24);
}
