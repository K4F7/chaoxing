import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { AutostartService, MemoryAutostartStore } from "../src/autostart";
import { hiddenLaunchCommand } from "../src/launch";

describe("Windows autostart", () => {
  test("defaults to off and writes a hidden launch command", async () => {
    const store = new MemoryAutostartStore();
    const service = new AutostartService(store, "C:\\\\Apps\\\\chaoxing_windows.exe");
    assert.equal(await service.isEnabled(), false);
    await service.setEnabled(true);
    assert.equal(store.command, hiddenLaunchCommand("C:\\\\Apps\\\\chaoxing_windows.exe"));
    assert.match(store.command ?? "", /--hidden/);
    assert.equal(await service.isEnabled(), true);
    await service.setEnabled(false);
    assert.equal(store.command, null);
  });
});
