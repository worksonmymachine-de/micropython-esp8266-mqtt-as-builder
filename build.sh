#!/bin/bash

# Exit on error
set -e

# --- Configuration ---
MICROPYTHON_REPO="https://github.com/micropython/micropython.git"
MQTT_AS_REPO="https://github.com/peterhinch/micropython-mqtt.git"
BASE_DIR="${PWD}"
BUILD_DIR="${BASE_DIR}/build"
EXPORT_DIR="${BASE_DIR}/export" 

echo "🚀 Starting Custom MicroPython Docker Build Pipeline..."

# Checking for root
if [ "$EUID" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

# --- 0. Clean old build artifacts ---
echo "🧹 Cleaning up previous builds..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$EXPORT_DIR"

# --- 1. Setup host dependencies ---
echo "📦 Verifying system dependencies (Docker & Git)..."
$SUDO apt update -qq > /dev/null 2>&1
$SUDO apt install -y -qq git docker.io > /dev/null 2>&1

if ! systemctl is-active --quiet docker; then
    echo "⚙️  Starting Docker service..."
    $SUDO systemctl start docker > /dev/null 2>&1
fi

run_in_docker() {
    $SUDO docker run --rm -v "$BASE_DIR:$BASE_DIR" -u "$(id -u):$(id -g)" -w "$PWD" larsks/esp-open-sdk "$@"
}

# --- 2. Fetch Repositories & Checkout Stable ---
echo "📥 Fetching source code..."

# Find the latest stable tag remotely to avoid downloading the entire repository history
LATEST_TAG=$(git ls-remote --tags --refs "$MICROPYTHON_REPO" | grep -o 'refs/tags/v[0-9]*\.[0-9]*\.[0-9]*$' | cut -d/ -f3 | sort -V | tail -n1)
echo "🔖 Latest MicroPython stable release found: $LATEST_TAG"

# Total silence for Git clones (redirecting both stdout and stderr) hides the detached HEAD warnings
git clone --depth 1 --branch "$LATEST_TAG" "$MICROPYTHON_REPO" "$BUILD_DIR/micropython" > /dev/null 2>&1 || { echo "❌ Failed to clone MicroPython."; exit 1; }

git clone --depth 1 "$MQTT_AS_REPO" "$BUILD_DIR/micropython-mqtt" > /dev/null 2>&1 || { echo "❌ Failed to clone MQTT_AS."; exit 1; }

# --- 3. Build mpy-cross ---
echo "🛠️  Building mpy-cross compiler..."
cd "$BUILD_DIR/micropython/mpy-cross"
run_in_docker make -j"$(nproc)" > /dev/null 2>&1 || { echo "❌ Failed to build mpy-cross."; exit 1; }

# --- 4. Inject MQTT_AS library ---
echo "💉 Injecting mqtt_as module..."
ESP8266_DIR="$BUILD_DIR/micropython/ports/esp8266"
ESP8266_MODULES="$ESP8266_DIR/modules"
mkdir -p "$ESP8266_MODULES"

MQTT_AS_SRC="$BUILD_DIR/micropython-mqtt/mqtt_as"

if [ -f "$MQTT_AS_SRC/__init__.py" ]; then
    mkdir -p "$ESP8266_MODULES/mqtt_as"
    cp "$MQTT_AS_SRC/__init__.py" "$ESP8266_MODULES/mqtt_as/"
else
    echo "❌ Error: $MQTT_AS_SRC/__init__.py not found."
    exit 1
fi

if [ -f "$MQTT_AS_SRC/mqtt_local.py" ]; then
    cp "$MQTT_AS_SRC/mqtt_local.py" "$EXPORT_DIR/"
fi

# --- 5. Fetch submodules for ESP8266 ---
echo "🔗 Fetching ESP8266-specific submodules..."
cd "$ESP8266_DIR"
# Redirecting stderr hides the git clone spam from fetching the submodules
run_in_docker make submodules > /dev/null 2>&1 || { echo "❌ Failed to fetch submodules."; exit 1; }

# --- 6. Build firmware ---
echo "🏗️  Compiling ESP8266 firmware..."
run_in_docker make -j"$(nproc)" BOARD=ESP8266_GENERIC > /dev/null 2>&1 || { echo "❌ Failed to build firmware."; exit 1; }

# --- 7. Export firmware ---
echo "🚚 Exporting compiled firmware..."
cd "$BASE_DIR"

# Formatted timestamp to match the requested [date]-[time] format (e.g., 2026-02-21-092314)
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
FIRMWARE_NAME="ESP8266-micropython-${LATEST_TAG}-mqtt-as-${TIMESTAMP}.bin"

if [ -f "$ESP8266_DIR/build-ESP8266_GENERIC/firmware.bin" ]; then
    cp "$ESP8266_DIR/build-ESP8266_GENERIC/firmware.bin" "$EXPORT_DIR/$FIRMWARE_NAME"
    echo "✅ Success! Firmware exported to: $EXPORT_DIR/$FIRMWARE_NAME"
elif [ -f "$ESP8266_DIR/build-ESP8266_GENERIC/firmware-combined.bin" ]; then
    cp "$ESP8266_DIR/build-ESP8266_GENERIC/firmware-combined.bin" "$EXPORT_DIR/$FIRMWARE_NAME"
    echo "✅ Success! Firmware exported to: $EXPORT_DIR/$FIRMWARE_NAME"
else
    echo "❌ Error: Firmware binary not found."
    exit 1
fi
