package com.chaoxinghelper.alarms

import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record

class ChaoxingAlarmRecord : Record {
  @Field
  var key: String = ""

  @Field
  var requestCode: Int = 0

  @Field
  var triggerAtMs: Long = 0

  @Field
  var windowEndMs: Long = 0

  @Field
  var tier: String = ""

  @Field
  var intensity: String = ""

  @Field
  var channelId: String = ""

  @Field
  var itemId: String = ""

  @Field
  var itemKind: String = ""

  @Field
  var ruleId: String = ""

  @Field
  var title: String = ""

  @Field
  var body: String = ""

  @Field
  var showDetails: Boolean = false

  @Field
  var alarmManagerApi: String = "setExactAndAllowWhileIdle"

  fun toMap(): Map<String, Any> {
    return mapOf(
      "key" to key,
      "requestCode" to requestCode,
      "triggerAtMs" to triggerAtMs,
      "windowEndMs" to windowEndMs,
      "tier" to tier,
      "intensity" to intensity,
      "channelId" to channelId,
      "itemId" to itemId,
      "itemKind" to itemKind,
      "ruleId" to ruleId,
      "title" to title,
      "body" to body,
      "showDetails" to showDetails,
      "alarmManagerApi" to alarmManagerApi,
    )
  }

  companion object {
    fun fromMap(values: Map<String, Any?>): ChaoxingAlarmRecord {
      val record = ChaoxingAlarmRecord()
      record.key = values.string("key")
      record.requestCode = values.int("requestCode")
      record.triggerAtMs = values.long("triggerAtMs")
      record.windowEndMs = values.long("windowEndMs")
      record.tier = values.string("tier")
      record.intensity = values.string("intensity")
      record.channelId = values.string("channelId")
      record.itemId = values.string("itemId")
      record.itemKind = values.string("itemKind")
      record.ruleId = values.string("ruleId")
      record.title = values.string("title")
      record.body = values.string("body")
      record.showDetails = values["showDetails"] as? Boolean ?: false
      record.alarmManagerApi =
        values.string("alarmManagerApi", "setExactAndAllowWhileIdle")
      return record
    }
  }
}

private fun Map<String, Any?>.string(name: String, fallback: String = ""): String {
  return this[name]?.toString() ?: fallback
}

private fun Map<String, Any?>.int(name: String): Int {
  return when (val value = this[name]) {
    is Int -> value
    is Number -> value.toInt()
    is String -> value.toInt()
    else -> 0
  }
}

private fun Map<String, Any?>.long(name: String): Long {
  return when (val value = this[name]) {
    is Long -> value
    is Number -> value.toLong()
    is String -> value.toLong()
    else -> 0L
  }
}
