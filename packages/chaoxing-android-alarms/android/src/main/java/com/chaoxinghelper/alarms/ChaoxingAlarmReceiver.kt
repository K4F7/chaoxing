package com.chaoxinghelper.alarms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ChaoxingAlarmReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != ChaoxingAlarmScheduler.ACTION_FIRE) {
      return
    }
    val record = ChaoxingAlarmRecord().apply {
      key = intent.getStringExtra(ChaoxingAlarmScheduler.EXTRA_KEY).orEmpty()
      itemId = intent.getStringExtra(ChaoxingAlarmScheduler.EXTRA_ITEM_ID).orEmpty()
      title = intent.getStringExtra(ChaoxingAlarmScheduler.EXTRA_TITLE).orEmpty()
      body = intent.getStringExtra(ChaoxingAlarmScheduler.EXTRA_BODY).orEmpty()
      channelId =
        intent.getStringExtra(ChaoxingAlarmScheduler.EXTRA_CHANNEL_ID).orEmpty()
      intensity =
        intent.getStringExtra(ChaoxingAlarmScheduler.EXTRA_INTENSITY).orEmpty()
      requestCode = intent.getIntExtra(ChaoxingAlarmScheduler.EXTRA_REQUEST_CODE, 0)
    }
    if (record.key.isEmpty()) {
      return
    }
    ChaoxingAlarmNotifier(context.applicationContext).notify(record)
    ChaoxingAlarmStore(context.applicationContext).remove(record.key)
  }
}
