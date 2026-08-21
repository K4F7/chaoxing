package com.chaoxinghelper.alarms

import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ChaoxingAndroidAlarmsModule : Module() {
  private val scheduler: ChaoxingAlarmScheduler by lazy {
    val context = appContext.reactContext?.applicationContext
      ?: throw CodedException("E_REACT_CONTEXT", "React context 已丢失", null)
    ChaoxingAlarmScheduler(context)
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
  }

  private fun toCoded(error: Throwable): CodedException {
    return when (error) {
      is ExactAlarmDeniedException ->
        CodedException("E_EXACT_ALARM_DENIED", error.message, error)
      is CodedException -> error
      else -> CodedException("E_ALARM_SCHEDULE", error.message, error)
    }
  }
}
