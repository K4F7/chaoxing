/** Match `java.lang.String#hashCode` so JS and Kotlin agree on request codes. */
export function javaStringHashCode(value: string): number {
  let hash = 0;
  for (let i = 0; i < value.length; i += 1) {
    hash = (Math.imul(31, hash) + value.charCodeAt(i)) | 0;
  }
  return hash;
}

export function stableRequestCode(key: string): number {
  const hash = javaStringHashCode(key);
  return hash === 0 ? 1 : hash;
}

export class RequestCodeCollisionError extends Error {
  readonly collisions: ReadonlyArray<readonly [string, string]>;

  constructor(collisions: ReadonlyArray<readonly [string, string]>) {
    const detail = collisions
      .map(([left, right]) => `${left} ↔ ${right}`)
      .join("; ");
    super(
      `提醒去重键映射到相同的 Android requestCode，取消将互相覆盖：${detail}`,
    );
    this.name = "RequestCodeCollisionError";
    this.collisions = collisions;
  }
}

export function assertUniqueRequestCodes(
  plans: ReadonlyArray<{ key: string; requestCode: number }>,
): void {
  const byCode = new Map<number, string>();
  const collisions: Array<readonly [string, string]> = [];
  for (const plan of plans) {
    const existing = byCode.get(plan.requestCode);
    if (existing !== undefined && existing !== plan.key) {
      collisions.push([existing, plan.key]);
    } else {
      byCode.set(plan.requestCode, plan.key);
    }
  }
  if (collisions.length > 0) {
    throw new RequestCodeCollisionError(collisions);
  }
}
