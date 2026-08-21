import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  courseCatalogFromJson,
  courseSpaceKey,
  emptyCourseCatalog,
  mergeDiscoveredCourses,
  monitoredCourses,
  setCourseMonitored,
  shouldDiscoverCourses,
  type CourseSpace,
} from "../src/index";

const linear: CourseSpace = {
  courseId: "101",
  classId: "201",
  cpi: "1",
  title: "线性代数",
};

const physics: CourseSpace = {
  courseId: "102",
  classId: "202",
  cpi: "2",
  title: "大学物理",
};

describe("受监控课程", () => {
  test("new discovered courses default to monitored", () => {
    const catalog = mergeDiscoveredCourses(
      emptyCourseCatalog,
      [linear, physics],
      new Date("2026-07-27T01:00:00+08:00"),
    );

    assert.deepEqual(
      monitoredCourses(catalog).map((course) => course.title),
      ["线性代数", "大学物理"],
    );
    assert.equal(shouldDiscoverCourses({
      catalog,
      now: new Date("2026-07-27T10:00:00+08:00"),
      forceDiscovery: false,
    }), false);
    assert.equal(shouldDiscoverCourses({
      catalog,
      now: new Date("2026-07-28T01:00:00+08:00"),
      forceDiscovery: false,
    }), true);
  });

  test("opt-out is preserved when the same course is discovered again", () => {
    const first = mergeDiscoveredCourses(
      emptyCourseCatalog,
      [linear, physics],
      new Date("2026-07-27T01:00:00+08:00"),
    );
    const optedOut = setCourseMonitored(first, courseSpaceKey(physics), false);
    const merged = mergeDiscoveredCourses(
      optedOut,
      [linear, { ...physics, title: "大学物理（新学期）" }],
      new Date("2026-07-28T01:00:00+08:00"),
    );

    assert.equal(
      merged.courses.find((value) => value.course.courseId === "102")?.monitored,
      false,
    );
    assert.equal(merged.courses.find((value) => value.course.courseId === "102")?.course.title, "大学物理（新学期）");
    assert.deepEqual(
      monitoredCourses(merged).map((course) => course.courseId),
      ["101"],
    );
  });

  test("round-trips catalog JSON and skips incomplete course rows", () => {
    const catalog = mergeDiscoveredCourses(
      emptyCourseCatalog,
      [linear, { courseId: "", classId: "9", cpi: "1", title: "无效" }],
      new Date("2026-07-27T01:00:00Z"),
    );
    const restored = courseCatalogFromJson({
      courses: catalog.courses.map((value) => ({
        course: value.course,
        monitored: value.monitored,
      })),
      lastDiscoveredAt: catalog.lastDiscoveredAt?.toISOString(),
    });

    assert.equal(restored.courses.length, 1);
    assert.equal(restored.courses[0].course.title, "线性代数");
  });
});
