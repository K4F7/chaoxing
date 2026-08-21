package com.chaoxinghelper.alarms

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class ChaoxingAlarmNotifier(private val context: Context) {
  fun ensureChannels() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return
    }
    val manager = context.getSystemService(NotificationManager::class.java)
    val low = NotificationChannel(
      CHANNEL_LOW,
      "截止前提醒（静默）",
      NotificationManager.IMPORTANCE_LOW,
    )
    low.setSound(null, null)
    low.enableVibration(false)
    val high = NotificationChannel(
      CHANNEL_HIGH,
      "截止前提醒（响铃）",
      NotificationManager.IMPORTANCE_HIGH,
    )
    high.enableVibration(true)
    manager.createNotificationChannel(low)
    manager.createNotificationChannel(high)
  }

  fun notify(record: ChaoxingAlarmRecord) {
    ensureChannels()
    val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
      ?: Intent()
    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    launch.putExtra(EXTRA_ITEM_ID, record.itemId)
    launch.putExtra(EXTRA_REMINDER_KEY, record.key)
    val contentIntent = PendingIntent.getActivity(
      context,
      record.requestCode,
      launch,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
    val notification = NotificationCompat.Builder(context, record.channelId)
      .setSmallIcon(android.R.drawable.ic_dialog_info)
      .setContentTitle(record.title)
      .setContentText(record.body)
      .setStyle(NotificationCompat.BigTextStyle().bigText(record.body))
      .setContentIntent(contentIntent)
      .setAutoCancel(true)
      .setPriority(
        if (record.intensity == "high") NotificationCompat.PRIORITY_HIGH
        else NotificationCompat.PRIORITY_LOW,
      )
      .build()
    NotificationManagerCompat.from(context).notify(record.requestCode, notification)
  }

  fun notifyAuthenticationExpired() {
    ensureChannels()
    val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
      ?: Intent()
    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    val contentIntent = PendingIntent.getActivity(
      context,
      REQUEST_AUTH_EXPIRED,
      launch,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
    val notification = NotificationCompat.Builder(context, CHANNEL_HIGH)
      .setSmallIcon(android.R.drawable.ic_dialog_info)
      .setContentTitle("学习通登录已失效")
      .setContentText("请打开应用重新登录，自动同步已停止。")
      .setContentIntent(contentIntent)
      .setAutoCancel(true)
      .setPriority(NotificationCompat.PRIORITY_HIGH)
      .build()
    NotificationManagerCompat.from(context).notify(REQUEST_AUTH_EXPIRED, notification)
  }

  companion object {
    const val CHANNEL_LOW = "chaoxing-reminder-low"
    const val CHANNEL_HIGH = "chaoxing-reminder-high"
    const val EXTRA_ITEM_ID = "chaoxing.itemId"
    const val EXTRA_REMINDER_KEY = "chaoxing.reminderKey"
    const val REQUEST_AUTH_EXPIRED = 190019
  }
}
