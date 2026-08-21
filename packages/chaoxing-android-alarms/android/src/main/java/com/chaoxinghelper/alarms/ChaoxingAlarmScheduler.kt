package com.chaoxinghelper.alarms

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build

class ChaoxingAlarmScheduler(private val context: Context) {
  private val alarmManager =
    context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
  private val store = ChaoxingAlarmStore(context)

  fun canScheduleExactAlarms(): Boolean {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      alarmManager.canScheduleExactAlarms()
    } else {
      true
    }
  }

  fun schedule(record: ChaoxingAlarmRecord) {
    if (!canScheduleExactAlarms()) {
      throw ExactAlarmDeniedException()
    }
    if (record.alarmManagerApi != "setExactAndAllowWhileIdle") {
      throw IllegalArgumentException(
        "只接受 setExactAndAllowWhileIdle，拒绝 ${record.alarmManagerApi}",
      )
    }
    alarmManager.setExactAndAllowWhileIdle(
      AlarmManager.RTC_WAKEUP,
      record.triggerAtMs,
      pendingIntent(record),
    )
    store.upsert(record)
  }

  fun cancel(key: String) {
    val existing = store.load().firstOrNull { it.key == key }
    if (existing != null) {
      alarmManager.cancel(pendingIntent(existing))
    }
    store.remove(key)
  }

  fun cancelAll() {
    store.load().forEach { alarmManager.cancel(pendingIntent(it)) }
    store.clear()
  }

  fun list(): List<ChaoxingAlarmRecord> = store.load()

  fun rescheduleAll(records: List<ChaoxingAlarmRecord>) {
    if (!canScheduleExactAlarms()) {
      throw ExactAlarmDeniedException()
    }
    cancelAll()
    records.forEach { schedule(it) }
  }

  fun reschedulePersisted() {
    if (!canScheduleExactAlarms()) {
      return
    }
    store.load().forEach { record ->
      alarmManager.setExactAndAllowWhileIdle(
        AlarmManager.RTC_WAKEUP,
        record.triggerAtMs,
        pendingIntent(record),
      )
    }
  }

  private fun pendingIntent(record: ChaoxingAlarmRecord): PendingIntent {
    val intent = Intent(context, ChaoxingAlarmReceiver::class.java).apply {
      action = ACTION_FIRE
      data = Uri.parse("chaoxing-alarm://${Uri.encode(record.key)}")
      putExtra(EXTRA_KEY, record.key)
      putExtra(EXTRA_ITEM_ID, record.itemId)
      putExtra(EXTRA_TITLE, record.title)
      putExtra(EXTRA_BODY, record.body)
      putExtra(EXTRA_CHANNEL_ID, record.channelId)
      putExtra(EXTRA_INTENSITY, record.intensity)
      putExtra(EXTRA_REQUEST_CODE, record.requestCode)
    }
    return PendingIntent.getBroadcast(
      context,
      record.requestCode,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }

  companion object {
    const val ACTION_FIRE = "com.chaoxinghelper.alarms.FIRE"
    const val EXTRA_KEY = "key"
    const val EXTRA_ITEM_ID = "itemId"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_CHANNEL_ID = "channelId"
    const val EXTRA_INTENSITY = "intensity"
    const val EXTRA_REQUEST_CODE = "requestCode"
  }
}

class ExactAlarmDeniedException :
  IllegalStateException("无法安排精确闹钟：系统未授予 USE_EXACT_ALARM。")
