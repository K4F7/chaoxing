import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  addHours,
  collectDueReminders,
  emptyReminderHistory,
  markReminderSent,
  planReminders,
  pruneReminderHistory,
  ReminderIntensity,
} from "../src/index";
import { assignmentItem } from "./helpers";

describe("planReminders", () => {
  test("plans 24 hour low and 2 hour high reminder rules", () => {
    const now = new Date(2026, 6, 27, 9);
    const plans = planReminders({
      items: [assignmentItem({ dueAt: addHours(now, 25), id: "day" })],
      history: emptyReminderHistory(),
      now,
    });

    assert.deepEqual(
      plans.map((plan) => plan.ruleId),
      ["due-24h", "due-2h"],
    );
    assert.deepEqual(
      plans.map((plan) => plan.intensity),
      [ReminderIntensity.low, ReminderIntensity.high],
    );
    assert.deepEqual(
      plans.map((plan) => plan.triggerAt.getTime()),
      [addHours(now, 1).getTime(), addHours(now, 23).getTime()],
    );
    assert.match(plans[0].key, /\|due-24h\|/);
    assert.match(plans[1].key, /\|due-2h\|/);
  });

  test("does not miss tiers after a refresh gap", () => {
    const now = new Date(2026, 6, 27, 9);

    const low = collectDueReminders({
      items: [assignmentItem({ dueAt: addHours(now, 20) })],
      history: emptyReminderHistory(),
      now,
    });
    const high = collectDueReminders({
      items: [assignmentItem({ dueAt: addHours(now, 1) })],
      history: emptyReminderHistory(),
      now,
    });

    assert.equal(low.length, 1);
    assert.equal(low[0].intensity, ReminderIntensity.low);
    assert.equal(high.length, 1);
    assert.equal(high[0].intensity, ReminderIntensity.high);
  });

  test("keeps both rules from suppressing each other", () => {
    const dueAt = new Date(2026, 6, 28, 10);
    const item = assignmentItem({ dueAt });
    const afterLow = collectDueReminders({
      items: [item],
      history: emptyReminderHistory(),
      now: addHours(dueAt, -24),
    });
    const afterHigh = collectDueReminders({
      items: [item],
      history: markReminderSent(
        emptyReminderHistory(),
        afterLow[0].key,
        addHours(dueAt, -24),
      ),
      now: addHours(dueAt, -2),
    });

    assert.equal(afterLow[0].intensity, ReminderIntensity.low);
    assert.equal(afterHigh[0].intensity, ReminderIntensity.high);
    assert.match(afterLow[0].key, /\|due-24h\|/);
    assert.match(afterHigh[0].key, /\|due-2h\|/);
  });

  test("replans a rule after the due time snapshot changes", () => {
    const now = new Date(2026, 6, 27, 9);
    const original = assignmentItem({ dueAt: addHours(now, 20) });
    const first = collectDueReminders({
      items: [original],
      history: emptyReminderHistory(),
      now,
    });
    const postponed = collectDueReminders({
      items: [assignmentItem({ dueAt: addHours(now, 26) })],
      history: markReminderSent(emptyReminderHistory(), first[0].key, now),
      now,
    });

    assert.equal(first.length, 1);
    assert.equal(postponed.length, 1);
    assert.notEqual(postponed[0].key, first[0].key);
  });

  test("skips items without a future due time", () => {
    const now = new Date(2026, 6, 27, 9);
    const plans = planReminders({
      items: [
        assignmentItem({ dueAt: null, id: "none" }),
        assignmentItem({ dueAt: now, id: "now" }),
        assignmentItem({ dueAt: addHours(now, -1), id: "past" }),
      ],
      history: emptyReminderHistory(),
      now,
    });

    assert.deepEqual(plans, []);
  });

  test("collects a due reminder once per item and due time", () => {
    const now = new Date(2026, 6, 5, 9);
    const item = assignmentItem({ dueAt: addHours(now, 2) });
    const pending = collectDueReminders({
      items: [item],
      history: emptyReminderHistory(),
      now,
    });
    const duplicate = collectDueReminders({
      items: [item],
      history: markReminderSent(emptyReminderHistory(), pending[0].key, now),
      now,
    });

    assert.equal(pending.length, 1);
    assert.equal(pending[0].item.id, "assignment-1");
    assert.deepEqual(duplicate, []);
  });
});

describe("pruneReminderHistory", () => {
  test("prunes stale, future, and excess reminder history entries", () => {
    const now = new Date(2026, 6, 16, 12);
    const pruned = pruneReminderHistory(
      {
        sent: {
          stale: addHours(now, -91 * 24),
          future: addHours(now, 48),
          "recent-a": addHours(now, -1),
          "recent-b": addHours(now, -2),
          "recent-c": addHours(now, -3),
        },
      },
      now,
      { maximumEntries: 2 },
    );

    assert.deepEqual(Object.keys(pruned.sent), ["recent-a", "recent-b"]);
    assert.equal(pruned.sent.stale, undefined);
    assert.equal(pruned.sent.future, undefined);
  });
});
