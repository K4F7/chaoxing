package com.chaoxinghelper.http

import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

class ChaoxingHttpModule : Module() {
  private val cookieJar = ChaoxingCookieJar()
  private val client: OkHttpClient by lazy {
    OkHttpClient.Builder()
      .cookieJar(cookieJar)
      .followRedirects(false)
      .followSslRedirects(false)
      .connectTimeout(30, TimeUnit.SECONDS)
      .readTimeout(30, TimeUnit.SECONDS)
      .build()
  }

  override fun definition() = ModuleDefinition {
    Name("ChaoxingAndroidHttp")

    AsyncFunction("send") { request: Map<String, Any?> ->
      runCatching { send(request) }.getOrElse { throw toCoded(it) }
    }

    AsyncFunction("snapshotCookies") { url: String ->
      cookieJar.snapshot(url)
    }
  }

  private fun send(request: Map<String, Any?>): Map<String, Any?> {
    val method = (request["method"] as? String)?.uppercase() ?: "GET"
    val url = request["url"] as? String ?: throw CodedException("missing_url", "url required", null)
    val headers = request["headers"] as? Map<*, *> ?: emptyMap<String, Any?>()
    val form = request["form"] as? Map<*, *>
    val builder = Request.Builder().url(url)
    for ((key, value) in headers) {
      if (key is String && value is String) {
        builder.header(key, value)
      }
    }
    if (method == "POST") {
      val body = FormBody.Builder()
      if (form != null) {
        for ((key, value) in form) {
          if (key is String && value is String) {
            body.add(key, value)
          }
        }
      }
      builder.post(body.build())
    } else {
      builder.get()
    }
    client.newCall(builder.build()).execute().use { response ->
      val headerMap = linkedMapOf<String, String>()
      val setCookies = mutableListOf<String>()
      for (name in response.headers.names()) {
        val values = response.headers.values(name)
        if (name.equals("set-cookie", ignoreCase = true)) {
          setCookies.addAll(values)
        } else if (values.isNotEmpty()) {
          headerMap[name] = values.joinToString(", ")
        }
      }
      if (setCookies.isNotEmpty()) {
        headerMap["set-cookie"] = setCookies.joinToString(", ")
      }
      return mapOf(
        "status" to response.code,
        "url" to (response.request.url.toString()),
        "headers" to headerMap,
        "body" to (response.body?.string() ?: ""),
      )
    }
  }

  private fun toCoded(error: Throwable): CodedException {
    return CodedException("http_failed", error.message ?: "request failed", error)
  }
}
