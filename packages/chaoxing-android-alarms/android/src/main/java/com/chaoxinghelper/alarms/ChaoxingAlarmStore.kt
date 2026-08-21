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

  fun recordDelivered(key: String, itemId: String, firedAtMs: Long) {
    if (key.isEmpty()) {
      return
    }
    val next = listDeliveredInternal().filterNot { it.key == key } +
      DeliveredReminder(key, itemId, firedAtMs)
    saveDelivered(next)
  }

  fun listDelivered(): List<Map<String, Any>> {
    return listDeliveredInternal().map {
      mapOf(
        "key" to it.key,
        "itemId" to it.itemId,
        "firedAtMs" to it.firedAtMs,
      )
    }
  }

  fun consumeDelivered(keys: List<String>) {
    val drop = keys.toSet()
    saveDelivered(listDeliveredInternal().filterNot { drop.contains(it.key) })
  }

  private fun listDeliveredInternal(): List<DeliveredReminder> {
    val raw = prefs.getString(KEY_DELIVERED, "[]") ?: "[]"
    val array = JSONArray(raw)
    return buildList(array.length()) {
      for (index in 0 until array.length()) {
        val json = array.getJSONObject(index)
        add(
          DeliveredReminder(
            key = json.optString("key"),
            itemId = json.optString("itemId"),
            firedAtMs = json.optLong("firedAtMs"),
          ),
        )
      }
    }.filter { it.key.isNotEmpty() }
  }

  private fun saveDelivered(rows: List<DeliveredReminder>) {
    val array = JSONArray()
    rows.forEach { row ->
      array.put(
        JSONObject().apply {
          put("key", row.key)
          put("itemId", row.itemId)
          put("firedAtMs", row.firedAtMs)
        },
      )
    }
    prefs.edit().putString(KEY_DELIVERED, array.toString()).apply()
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
    private const val KEY_DELIVERED = "delivered"
  }
}

private data class DeliveredReminder(
  val key: String,
  val itemId: String,
  val firedAtMs: Long,
)
