#!/usr/bin/env bash
# CI assemble for the RN Android production app.
# Debug-signed (unsigned store release) unless ANDROID_KEYSTORE_BASE64 and
# ANDROID_KEY_PROPERTIES_BASE64 are both set. Never prints those values.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

export CI=1
export EXPO_NO_TELEMETRY=1
export ORG_GRADLE_PROJECT_reactNativeArchitectures="${ORG_GRADLE_PROJECT_reactNativeArchitectures:-arm64-v8a}"

mkdir -p build/ci
rm -f build/ci/app-debug.apk build/ci/app-release.apk build/ci/SIGNING.txt

npx expo prebuild --platform android --non-interactive --no-install

if [[ ! -d android ]]; then
  echo "expo prebuild did not create apps/chaoxing_rn/android" >&2
  exit 1
fi

if [[ -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME}" ]]; then
  printf 'sdk.dir=%s\n' "${ANDROID_HOME}" > android/local.properties
fi

signed=0
if [[ -n "${ANDROID_KEYSTORE_BASE64:-}" && -n "${ANDROID_KEY_PROPERTIES_BASE64:-}" ]]; then
  printf '%s' "${ANDROID_KEYSTORE_BASE64}" | base64 --decode > android/app/upload-keystore.jks
  test -s android/app/upload-keystore.jks
  printf '%s' "${ANDROID_KEY_PROPERTIES_BASE64}" | base64 --decode > android/keystore.properties
  test -s android/keystore.properties
  node tool/inject-android-release-signing.mjs
  signed=1
else
  echo "ANDROID_KEYSTORE_BASE64 / ANDROID_KEY_PROPERTIES_BASE64 are unset; assembling debug APK (debug-signed, not a store release)."
fi

(
  cd android
  chmod +x gradlew
  if [[ "${signed}" -eq 1 ]]; then
    ./gradlew assembleRelease --no-daemon
  else
    ./gradlew assembleDebug --no-daemon
  fi
)

if [[ "${signed}" -eq 1 ]]; then
  apk="$(find android/app/build/outputs/apk/release -name '*.apk' -type f | head -n 1)"
  test -n "${apk}" && test -s "${apk}"
  cp -f "${apk}" build/ci/app-release.apk
  printf 'mode=signed-release\nsecrets=ANDROID_KEYSTORE_BASE64,ANDROID_KEY_PROPERTIES_BASE64\n' > build/ci/SIGNING.txt
else
  apk="$(find android/app/build/outputs/apk/debug -name '*.apk' -type f | head -n 1)"
  test -n "${apk}" && test -s "${apk}"
  cp -f "${apk}" build/ci/app-debug.apk
  printf 'mode=debug-signed-dry-run\nmissing_secrets=ANDROID_KEYSTORE_BASE64,ANDROID_KEY_PROPERTIES_BASE64\n' > build/ci/SIGNING.txt
fi

echo "Assembled ${apk}"
