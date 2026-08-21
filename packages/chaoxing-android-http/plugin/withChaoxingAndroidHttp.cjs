const { createRunOncePlugin } = require("@expo/config-plugins");

function withChaoxingAndroidHttp(config) {
  return config;
}

module.exports = createRunOncePlugin(
  withChaoxingAndroidHttp,
  "@chaoxinghelper/android-http",
  "0.1.0",
);
