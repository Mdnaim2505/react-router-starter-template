#!/usr/bin/env bash
# =============================================================================
# Filter VPN - one-shot build script for Ubuntu / Debian (x86_64).
#
#   git clone <repo> && cd <repo> && ./build.sh
#
# What it does:
#   1. Installs JDK 17 + basic tools (apt), the Android command-line tools,
#      SDK platform, build-tools, NDK and CMake (sdkmanager, licences accepted).
#   2. Exports ANDROID_HOME and writes local.properties (git-ignored).
#   3. Generates a release keystore on first run (git-ignored) so the release
#      APK is signed and installable.
#   4. Runs ./gradlew assembleRelease (or assembleDebug) and prints the APK path.
#
# Options:
#   --debug         build the debug APK instead of release
#   --test          also run JVM unit tests (./gradlew test)
#   --abi LIST      comma-separated ABIs (default: arm64-v8a),
#                   e.g. --abi arm64-v8a,armeabi-v7a,x86_64
#   --skip-deps     do not run apt / sdkmanager (assume everything is installed)
#   -h | --help     show this help
#
# Environment overrides:
#   ANDROID_HOME    SDK location (default: $HOME/android-sdk)
#   JAVA_HOME       JDK to use (must be 17..24)
# =============================================================================
set -euo pipefail

# ---- pinned versions (keep in sync with app/build.gradle) -------------------
CMDLINE_TOOLS_BUILDS=("13114758" "11076708")   # tried in order
PLATFORM="platforms;android-36"
BUILD_TOOLS="build-tools;36.0.0"
NDK="ndk;27.2.12479018"
CMAKE="cmake;3.22.1"

# ---- args ---------------------------------------------------------------------
BUILD_TYPE="release"
RUN_TESTS=0
SKIP_DEPS=0
ABIS="arm64-v8a"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) BUILD_TYPE="debug" ;;
    --release) BUILD_TYPE="release" ;;
    --test) RUN_TESTS=1 ;;
    --skip-deps) SKIP_DEPS=1 ;;
    --abi) ABIS="${2:?--abi needs a value}"; shift ;;
    -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

SUDO=""
if [[ $(id -u) -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; fi
fi

[[ "$(uname -m)" == "x86_64" ]] || warn "Host is $(uname -m). Google ships Android build-tools for x86_64 Linux only; the build may fail."

# ---- 1a. system packages + JDK 17 ------------------------------------------------
java_major() {  # prints the major version of the given java binary, or 0
  local v
  v="$("$1" -version 2>&1 | awk -F'"' '/version/ {print $2; exit}')" || true
  v="${v#1.}"; echo "${v%%.*}" | grep -E '^[0-9]+$' || echo 0
}

pick_java_home() {
  # Prefer an explicit, compatible JAVA_HOME; then any installed JDK 17.
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/javac" ]]; then
    local m; m="$(java_major "$JAVA_HOME/bin/java")"
    if (( m >= 17 && m <= 24 )); then echo "$JAVA_HOME"; return; fi
  fi
  local d
  for d in /usr/lib/jvm/java-17-openjdk-* /usr/lib/jvm/temurin-17-* /usr/lib/jvm/java-21-openjdk-*; do
    [[ -x "$d/bin/javac" ]] && { echo "$d"; return; }
  done
  if command -v javac >/dev/null 2>&1; then
    local jh; jh="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
    local m; m="$(java_major "$jh/bin/java")"
    if (( m >= 17 && m <= 24 )); then echo "$jh"; return; fi
  fi
  echo ""
}

if [[ $SKIP_DEPS -eq 0 ]]; then
  NEED_APT=()
  for c in curl unzip git; do command -v "$c" >/dev/null 2>&1 || NEED_APT+=("$c"); done
  [[ -n "$(pick_java_home)" ]] || NEED_APT+=("openjdk-17-jdk-headless")
  if [[ ${#NEED_APT[@]} -gt 0 ]]; then
    command -v apt-get >/dev/null 2>&1 || die "apt-get not found. Install manually: ${NEED_APT[*]}"
    log "Installing system packages: ${NEED_APT[*]}"
    $SUDO apt-get update -y
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y --no-install-recommends ca-certificates "${NEED_APT[@]}"
  fi
fi

JAVA_HOME="$(pick_java_home)"
[[ -n "$JAVA_HOME" ]] || die "No JDK 17..24 found. Install openjdk-17-jdk-headless or set JAVA_HOME."
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
log "Using JDK: $JAVA_HOME ($(java_major "$JAVA_HOME/bin/java"))"

# ---- 1b/2. Android SDK -------------------------------------------------------------
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/android-sdk}}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
mkdir -p "$ANDROID_HOME"

find_sdkmanager() {
  local p
  for p in "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" \
           "$ANDROID_HOME"/cmdline-tools/*/bin/sdkmanager \
           "$ANDROID_HOME/tools/bin/sdkmanager"; do
    [[ -x "$p" ]] && { echo "$p"; return; }
  done
  echo ""
}

if [[ $SKIP_DEPS -eq 0 ]]; then
  SDKMANAGER="$(find_sdkmanager)"
  if [[ -z "$SDKMANAGER" ]]; then
    log "Downloading Android command-line tools into $ANDROID_HOME"
    tmp="$(mktemp -d)"
    ok=0
    for b in "${CMDLINE_TOOLS_BUILDS[@]}"; do
      url="https://dl.google.com/android/repository/commandlinetools-linux-${b}_latest.zip"
      if curl -fL --retry 3 -o "$tmp/clt.zip" "$url"; then ok=1; break; fi
      warn "Download failed: $url"
    done
    [[ $ok -eq 1 ]] || die "Could not download the Android command-line tools."
    unzip -q "$tmp/clt.zip" -d "$tmp"
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    rm -rf "$ANDROID_HOME/cmdline-tools/latest"
    mv "$tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
    rm -rf "$tmp"
    SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
  fi

  log "Accepting SDK licences"
  # `yes` dies of SIGPIPE when sdkmanager exits; `|| true` keeps pipefail happy.
  { yes || true; } | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1 || true

  log "Installing SDK packages: $PLATFORM $BUILD_TOOLS $NDK $CMAKE platform-tools"
  { yes || true; } | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --install \
      "platform-tools" "$PLATFORM" "$BUILD_TOOLS" "$NDK" "$CMAKE" \
    || die "sdkmanager failed. Re-run with network access to dl.google.com."
fi

# local.properties is git-ignored; it only tells Gradle where the SDK is.
printf 'sdk.dir=%s\n' "$ANDROID_HOME" > local.properties

# ---- 3. release keystore (auto-generated, git-ignored) ------------------------------
if [[ "$BUILD_TYPE" == "release" && ! -f keystore.properties ]]; then
  log "Generating release keystore (filtervpn-release.jks)"
  PASS="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 24)"
  keytool -genkeypair -noprompt -v \
    -keystore filtervpn-release.jks -storetype PKCS12 \
    -alias filtervpn -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$PASS" -keypass "$PASS" \
    -dname "CN=Filter VPN, OU=Build, O=Filter VPN, C=US" >/dev/null 2>&1
  cat > keystore.properties <<EOF
# Auto-generated by build.sh. Keep this file and filtervpn-release.jks safe:
# you need the same key to install future updates over this build.
storeFile=filtervpn-release.jks
storePassword=$PASS
keyAlias=filtervpn
keyPassword=$PASS
EOF
  chmod 600 keystore.properties filtervpn-release.jks
fi

[[ -f proxy.properties ]] || log "Tip: cp proxy.properties.example proxy.properties to pre-fill proxy defaults in the app."

# ---- 4. build ---------------------------------------------------------------------------
GRADLE_ARGS=(--no-daemon --stacktrace)
GRADLE_ARGS+=("-PabiFilters=$ABIS")

# Small VPS: lower the Gradle heap so the build does not get OOM-killed.
MEM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
if (( MEM_KB > 0 && MEM_KB < 4000000 )); then
  warn "Less than 4 GB RAM detected; using a smaller Gradle heap. Add swap if the build is killed."
  GRADLE_ARGS+=("-Dorg.gradle.jvmargs=-Xmx1536m -Dfile.encoding=UTF-8" "-Dorg.gradle.parallel=false")
fi

chmod +x ./gradlew
TASK="assemble${BUILD_TYPE^}"
TASKS=("$TASK")
[[ $RUN_TESTS -eq 1 ]] && TASKS=("test" "$TASK")

log "Running ./gradlew ${TASKS[*]}"
./gradlew "${GRADLE_ARGS[@]}" "${TASKS[@]}"

APK_DIR="app/build/outputs/apk/$BUILD_TYPE"
mapfile -t APKS < <(find "$APK_DIR" -name '*.apk' 2>/dev/null | sort)
[[ ${#APKS[@]} -gt 0 ]] || die "Build finished but no APK found in $APK_DIR"

mkdir -p dist
VERSION="$(sed -n "s/.*versionName '\(.*\)'.*/\1/p" app/build.gradle | head -1)"
OUT="dist/FilterVPN-${VERSION:-dev}-${BUILD_TYPE}.apk"
cp "${APKS[0]}" "$OUT"

echo
log "Build successful"
echo "  APK : $ROOT/$OUT"
echo "  (Gradle output: $ROOT/${APKS[0]})"
echo "  Install with: adb install -r \"$ROOT/$OUT\""
