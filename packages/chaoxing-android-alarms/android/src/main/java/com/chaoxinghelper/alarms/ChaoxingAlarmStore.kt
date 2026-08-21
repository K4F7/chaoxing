package com.chaoxinghelper.alarms

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

class ChaoxingAlarmStore(context: Context) {
  private val prefs =
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

  fun load(): List<ChaoxingAlarmRecord> {
    val raw = prefs.getString(KEY_PLANS, "[]") ?: "[]"
    val array = JSONArray(raw)
    return buildList(array.length()) {
      for (index in 0 until array.length()) {
        add(fromJson(array.getJSONObject(index)))
      }
    }
  }

  fun save(records: List<ChaoxingAlarmRecord>) {
    val array = JSONArray()
    records.forEach { array.put(toJson(it)) }
    prefs.edit().putString(KEY_PLANS, array.toString()).apply()
  }

  fun upsert(record: ChaoxingAlarmRecord) {
    val next = load().filterNot { it.key == record.key } + record
    save(next)
  }

  fun remove(key: String) {
    save(load().filterNot { it.key == key })
  }

  fun clear() {
    prefs.edit().remove(KEY_PLANS).apply()
  }

  private fun toJson(record: ChaoxingAlarmRecord): JSONObject {
    return JSONObject().apply {
      put("key", record.key)
      put("requestCode", record.requestCode)
      put("triggerAtMs", record.triggerAtMs)
      put("windowEndMs", record.windowEndMs)
      put("tier", record.tier)
      put("intensity", record.intensity)
      put("channelId", record.channelId)
      put("itemId", record.itemId)
      put("itemKind", record.itemKind)
      put("ruleId", record.ruleId)
      put("title", record.title)
      put("body", record.body)
      put("showDetails", record.showDetails)
      put("alarmManagerApi", record.alarmManagerApi)
    }
  }

  private fun fromJson(json: JSONObject): ChaoxingAlarmRecord {
    return ChaoxingAlarmRecord.fromMap(
      mapOf(
        "key" to json.optString("key"),
        "requestCode" to json.optInt("requestCode"),
        "triggerAtMs" to json.optLong("triggerAtMs"),
        "windowEndMs" to json.optLong("windowEndMs"),
        "tier" to json.optString("tier"),
        "intensity" to json.optString("intensity"),
        "channelId" to json.optString("channelId"),
        "itemId" to json.optString("itemId"),
        "itemKind" to json.optString("itemKind"),
        "ruleId" to json.optString("ruleId"),
        "title" to json.optString("title"),
        "body" to json.optString("body"),
        "showDetails" to json.optBoolean("showDetails"),
        "alarmManagerApi" to json.optString(
          "alarmManagerApi",
          "setExactAndAllowWhileIdle",
        ),
      ),
    )
  }

  companion object {
    private const val PREFS_NAME = "chaoxing_android_alarms"
    private const val KEY_PLANS = "plans"
  }
}
