package com.chaoxinghelper.alarms

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ChaoxingAndroidAlarmsModule : Module() {
  private val scheduler: ChaoxingAlarmScheduler by lazy {
    ChaoxingAlarmScheduler(requireAppContext())
  }

  private val store: ChaoxingAlarmStore by lazy {
    ChaoxingAlarmStore(requireAppContext())
  }

  override fun definition() = ModuleDefinition {
    Name("ChaoxingAndroidAlarms")

    OnCreate {
      val context = appContext.reactContext?.applicationContext
      if (context != null) {
        ChaoxingAlarmNotifier(context).ensureChannels()
      }
    }

    Function("canScheduleExactAlarms") {
      scheduler.canScheduleExactAlarms()
    }

    AsyncFunction("schedule") { plan: Map<String, Any?> ->
      runCatching { scheduler.schedule(ChaoxingAlarmRecord.fromMap(plan)) }
        .getOrElse { throw toCoded(it) }
    }

    AsyncFunction("cancel") { key: String ->
      scheduler.cancel(key)
    }

    AsyncFunction("cancelAll") {
      scheduler.cancelAll()
    }

    AsyncFunction("list") {
      scheduler.list().map { it.toMap() }
    }

    AsyncFunction("rescheduleAll") { plans: List<Map<String, Any?>> ->
      runCatching {
        scheduler.rescheduleAll(plans.map { ChaoxingAlarmRecord.fromMap(it) })
        scheduler.list().map { it.toMap() }
      }.getOrElse { throw toCoded(it) }
    }

    AsyncFunction("listDelivered") {
      store.listDelivered()
    }

    AsyncFunction("consumeDelivered") { keys: List<String> ->
      store.consumeDelivered(keys)
    }

    Function("getLaunchTarget") {
      val intent = appContext.currentActivity?.intent ?: return@Function null
      val itemId = intent.getStringExtra(ChaoxingAlarmNotifier.EXTRA_ITEM_ID).orEmpty()
      if (itemId.isEmpty()) {
        return@Function null
      }
      mapOf(
        "itemId" to itemId,
        "reminderKey" to intent.getStringExtra(ChaoxingAlarmNotifier.EXTRA_REMINDER_KEY).orEmpty(),
      )
    }

    Function("requestPostNotifications") {
      requestPostNotifications()
    }

    AsyncFunction("notifyAuthenticationExpired") {
      ChaoxingAlarmNotifier(requireAppContext()).notifyAuthenticationExpired()
    }
  }

  private fun requestPostNotifications(): Boolean {
    if (Build.VERSION.SDK_INT < 33) {
      return true
    }
    val activity = appContext.currentActivity ?: return false
    val granted =
      ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) ==
        PackageManager.PERMISSION_GRANTED
    if (!granted) {
      ActivityCompat.requestPermissions(
        activity,
        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
        REQUEST_POST_NOTIFICATIONS,
      )
    }
    return ContextCompat.checkSelfPermission(
      activity,
      Manifest.permission.POST_NOTIFICATIONS,
    ) == PackageManager.PERMISSION_GRANTED
  }

  private fun requireAppContext() =
    appContext.reactContext?.applicationContext
      ?: throw CodedException("E_REACT_CONTEXT", "React context 已丢失", null)

  private fun toCoded(error: Throwable): CodedException {
    return when (error) {
      is ExactAlarmDeniedException ->
        CodedException("E_EXACT_ALARM_DENIED", error.message, error)
      is CodedException -> error
      else -> CodedException("E_ALARM_SCHEDULE", error.message, error)
    }
  }

  companion object {
    private const val REQUEST_POST_NOTIFICATIONS = 19013
  }
}
