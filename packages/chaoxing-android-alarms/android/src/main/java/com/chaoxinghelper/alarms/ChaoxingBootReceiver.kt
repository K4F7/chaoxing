package com.chaoxinghelper.alarms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ChaoxingBootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != Intent.ACTION_BOOT_COMPLETED) {
      return
    }
    val pending = goAsync()
    try {
      ChaoxingAlarmScheduler(context.applicationContext).reschedulePersisted()
    } finally {
      pending.finish()
    }
  }
}
