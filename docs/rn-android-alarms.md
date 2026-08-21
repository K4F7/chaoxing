# RN Android 预排闹钟（ADR-0001 移植）

[ADR-0001](./adr/0001-android-prescheduled-alarms.md) 的约束不变：Android 提醒走预排本地闹钟，不走后台定期抓取；精确闹钟用安装即授予的 `USE_EXACT_ALARM`；每次同步后全量取消并重排；开机后从持久化集合再排一遍；超出系统并发上限必须可见失败，不能悄悄丢掉末尾的提醒。

本文件只记录 React Native 这一侧怎么落实，不改 ADR 本身。Flutter 生产闹钟代码本轮只读、不改。

## 落点

- `packages/chaoxing-android-alarms`：两档映射、调度器、Expo native module、config plugin。
- `apps/chaoxing_rn`：真同步后的待办集合走 `planReminders` + `rescheduleAll`。fixture 助手只留在单元测试里。

## 两档怎么落到 AlarmManager

领域规划器产出「未来该排的」计划（`planReminders`）。本包把它们映射成：

- **windowed**：`due-24h` / 低强度。有效投递窗口是 `[截止-24h, 截止-2h)`，与 Flutter `collectDueReminders` 的 24h 补发窗口一致。若打开 App 时已经落在窗口内，就按「现在」排一条精确闹钟补上。
- **exact**：`due-2h` / 高强度。在截止前 2 小时整点响。

两档都调用 `AlarmManager.setExactAndAllowWhileIdle(RTC_WAKEUP, …)`。这里的 windowed **不是** `setWindow`：规格写明不使用非精确投递，避免 2 小时档在 Doze 里被拖过截止。

打扰强度走通知渠道，不是闹钟精度：`chaoxing-reminder-low` 静默，`chaoxing-reminder-high` 响铃震动。

## 标识与重排

提醒去重键仍由领域层计算（待办 + 规则 + 截止时间快照）。Android `requestCode` 是该键的 `String.hashCode`（JS 与 Kotlin 同一算法）。全量重排前后键和 requestCode 不变，取消才能命中上一轮。

## 可见失败

- 没有 AlarmManager（Expo Go / Web / 测试进程）：`UnsupportedAlarmBackendError`，文案写明不能用 `setTimeout` 假装闹钟。
- 未授予精确闹钟：`ExactAlarmPermissionError`，不降级。
- 接受的计划超过 500 条：`AlarmLimitExceededError`，整批拒绝。
- requestCode 碰撞：`RequestCodeCollisionError`。

## 尚未接上的部分

登录后的 `POST_NOTIFICATIONS`、真同步后的全量重排、已投递键写入提醒历史、通知 extras 打开待办详情，由 `apps/chaoxing_rn` 的生产胶水接线。Doze / 开机重排仍需真机验收。
