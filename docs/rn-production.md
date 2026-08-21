# 生产路径：RN Android + Windows 本机宿主

Flutter（`legacy/chaoxing_app`）不再是任何平台的出货路径。

| 平台 | 生产应用 | 提醒消费 | 登录 | 常驻 |
|---|---|---|---|---|
| Android | `apps/chaoxing_rn` | 预排 AlarmManager | WebView + Keystore | 不用后台抓取 |
| Windows | `apps/chaoxing_windows` | 「此刻该触发的」系统通知 | WebView2 | 托盘 + 可选自启 |

两端都复用 `packages/chaoxing-domain`，本机直连学习通，Cookie 不进明文设置。
