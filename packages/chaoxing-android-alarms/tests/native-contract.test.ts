import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

function read(relativePath: string): string {
  return readFileSync(join(root, relativePath), "utf8");
}

describe("native ADR-0001 contract", () => {
  test("declares install-granted exact alarms and boot reschedule, not the user-toggle permission", () => {
    const manifest = read("android/src/main/AndroidManifest.xml");
    assert.match(manifest, /android.permission.USE_EXACT_ALARM/);
    assert.match(manifest, /android.permission.RECEIVE_BOOT_COMPLETED/);
    assert.match(manifest, /ChaoxingAlarmReceiver/);
    assert.match(manifest, /ChaoxingBootReceiver/);
    assert.doesNotMatch(manifest, /SCHEDULE_EXACT_ALARM/);
  });

  test("schedules with setExactAndAllowWhileIdle and never uses inexact windows or periodic work", () => {
    const scheduler = read(
      "android/src/main/java/com/chaoxinghelper/alarms/ChaoxingAlarmScheduler.kt",
    );
    const module = read(
      "android/src/main/java/com/chaoxinghelper/alarms/ChaoxingAndroidAlarmsModule.kt",
    );
    const sources = `${scheduler}\n${module}`;
    assert.match(sources, /setExactAndAllowWhileIdle/);
    assert.doesNotMatch(sources, /setWindow\(/);
    assert.doesNotMatch(sources, /setAndAllowWhileIdle\(/);
    assert.doesNotMatch(sources, /WorkManager/);
    assert.doesNotMatch(sources, /setExact\(/);
    assert.doesNotMatch(sources, /setTimeout/);
    assert.match(module, /Function\("schedule"\)/);
    assert.match(module, /AsyncFunction\("cancel"\)/);
    assert.match(module, /AsyncFunction\("list"\)/);
    assert.match(module, /AsyncFunction\("rescheduleAll"\)/);
    assert.match(module, /AsyncFunction\("listDelivered"\)/);
    assert.match(module, /Function\("requestPostNotifications"\)/);
    assert.match(module, /Function\("getLaunchTarget"\)/);
    assert.match(module, /notifyAuthenticationExpired/);
  });

  test("alarm fire persists 提醒历史 keys and notification tap carries 待办 id", () => {
    const receiver = read(
      "android/src/main/java/com/chaoxinghelper/alarms/ChaoxingAlarmReceiver.kt",
    );
    const notifier = read(
      "android/src/main/java/com/chaoxinghelper/alarms/ChaoxingAlarmNotifier.kt",
    );
    const store = read(
      "android/src/main/java/com/chaoxinghelper/alarms/ChaoxingAlarmStore.kt",
    );
    assert.match(receiver, /recordDelivered/);
    assert.match(store, /KEY_DELIVERED/);
    assert.match(notifier, /EXTRA_ITEM_ID/);
    assert.match(notifier, /putExtra\(EXTRA_ITEM_ID/);
  });

  test("config plugin keeps USE_EXACT_ALARM and blocks SCHEDULE_EXACT_ALARM", () => {
    const plugin = read("plugin/withChaoxingAndroidAlarms.cjs");
    assert.match(plugin, /USE_EXACT_ALARM/);
    assert.match(plugin, /RECEIVE_BOOT_COMPLETED/);
    assert.match(plugin, /SCHEDULE_EXACT_ALARM/);
    assert.match(plugin, /withBlockedPermissions/);
  });
});
