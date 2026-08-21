package com.chaoxinghelper.http

import android.webkit.CookieManager
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl

/**
 * OkHttp jar backed by WebView CookieManager so login cookies and
 * later sync responses share one native store. JS fetch cannot see
 * Set-Cookie; this jar can.
 */
class ChaoxingCookieJar : CookieJar {
  private val manager: CookieManager = CookieManager.getInstance()

  override fun loadForRequest(url: HttpUrl): List<Cookie> {
    val header = manager.getCookie(url.toString()) ?: return emptyList()
    return header.split(";").mapNotNull { part ->
      Cookie.parse(url, part.trim())
    }
  }

  override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
    for (cookie in cookies) {
      manager.setCookie(url.toString(), cookie.toString())
    }
    manager.flush()
  }

  fun snapshot(url: String): String {
    return manager.getCookie(url).orEmpty()
  }
}
