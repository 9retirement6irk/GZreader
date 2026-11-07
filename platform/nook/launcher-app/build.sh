#!/usr/bin/env bash
# GZreader-launcher.apk: GZreader's icon for the Nook 1st Edition's app list
# (Android 1.5, API 3). Needs the Android SDK (ANDROID_HOME: a platform,
# build-tools) and a JDK; GitHub's ubuntu runners have both
# (gzreader-nook.yml). Signed with a key made for each build (the app is
# installed with adb; to replace it, uninstall it first).
#   platform/nook/launcher-app/build.sh <out.apk>
set -euo pipefail
OUT=$(cd "$(dirname "${1:?out.apk}")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:?ANDROID_HOME}}
BT=$SDK/build-tools/$(ls "$SDK/build-tools" | sort -V | tail -1)
JAR=$SDK/platforms/$(ls "$SDK/platforms" | grep '^android-[0-9]*$' | sort -t- -k2 -n | tail -1)/android.jar
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
echo "build-tools $BT, $JAR"

# resources and manifest (aapt 1: Android 1.5 reads its resource table)
"$BT/aapt" package -f -M "$HERE/AndroidManifest.xml" -S "$HERE/res" -I "$JAR" \
    --min-sdk-version 3 --target-sdk-version 3 -F "$W/base.apk"
# code: Java 8 class files, then Dalvik bytecode for API 3 (dex 035)
mkdir -p "$W/classes" "$W/dex"
javac -source 8 -target 8 -bootclasspath "$JAR" -encoding UTF-8 -nowarn -d "$W/classes" \
    $(find "$HERE/src" -name '*.java')
"$BT/d8" --min-api 3 --release --lib "$JAR" --output "$W/dex" $(find "$W/classes" -name '*.class')
(cd "$W/dex" && zip -q "$W/base.apk" classes.dex)
"$BT/zipalign" -f 4 "$W/base.apk" "$W/aligned.apk"
# v1 (JAR) signature only, SHA-1: what Android 1.5 checks
keytool -genkeypair -keystore "$W/key.jks" -storepass gzreader -keypass gzreader -alias gzreader \
    -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=GZreader Nook launcher" >/dev/null 2>&1
"$BT/apksigner" sign --ks "$W/key.jks" --ks-pass pass:gzreader --key-pass pass:gzreader --ks-key-alias gzreader \
    --min-sdk-version 3 --v1-signing-enabled true --v2-signing-enabled false --v3-signing-enabled false \
    --out "$OUT" "$W/aligned.apk"
"$BT/apksigner" verify --min-sdk-version 3 "$OUT"
"$BT/aapt" dump badging "$OUT" | head -5
echo "$OUT"
