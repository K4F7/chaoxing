import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

import {
  expectedAutostartCommand,
  installerLifecycleInvariants,
  silentInstallArgs,
} from "../src/installer/lifecycle";

const here = dirname(fileURLToPath(import.meta.url));
const iss = readFileSync(
  join(here, "..", "installer", "chaoxing_windows.iss"),
  "utf8",
);

describe("Windows installer lifecycle", () => {
  test("ports terminate-on-uninstall, autostart cleanup, and per-user install", () => {
    const invariants = installerLifecycleInvariants(iss);
    assert.equal(invariants.terminateOnUninstall, true);
    assert.equal(invariants.terminateOnUpgrade, true);
    assert.equal(invariants.autostartCleanup, true);
    assert.equal(invariants.perUserInstall, true);
    assert.equal(invariants.startMenuShortcut, true);
    assert.equal(invariants.webView2Hint, true);
  });

  test("silent args and hidden autostart command match Flutter behavior", () => {
    assert.deepEqual(silentInstallArgs(), [
      "/VERYSILENT",
      "/SUPPRESSMSGBOXES",
      "/NORESTART",
    ]);
    assert.equal(
      expectedAutostartCommand("C:\\\\Apps\\\\chaoxing_windows.exe"),
      '"C:\\\\Apps\\\\chaoxing_windows.exe" --hidden',
    );
  });
});
