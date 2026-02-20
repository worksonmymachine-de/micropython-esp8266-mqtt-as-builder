#!/bin/bash

# Exit on error
set -e

# --- Configuration ---
MICROPYTHON_REPO="https://github.com/micropython/micropython.git"
MQTT_AS_REPO="https://github.com/peterhinch/micropython-mqtt.git"
BUILD_DIR="${PWD}/build"
DEPLOY_DIR="${PWD}/deploy"

echo "Custom MicroPython Build Pipeline"

# Checking for root
if [ "$EUID" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

# --- 1. Setup build environment (Debian) ---
echo "Installing system dependencies..."
$SUDO apt update
$SUDO apt install -y python3-venv python3-full make unrar-free autoconf automake libtool gcc g++ gperf \
    flex bison texinfo gawk ncurses-dev libexpat-dev python3-pip git sed unzip bash help2man wget bzip2 libtool-bin

# Setup Python virtual environment
echo "Setting up Python virtual environment..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi
source venv/bin/activate

# Keep pip micropython-embed available as noted in README
# pip3 install micropython-embed

# Prepare directories
mkdir -p "$BUILD_DIR"
mkdir -p "$DEPLOY_DIR"

# --- 2. Toolchain check (xtensa-lx106-elf) ---
# MicroPython ESP8266 port requires the xtensa-lx106-elf compiler to build.
if ! command -v xtensa-lx106-elf-gcc &> /dev/null; then
    echo "Cross-compiler xtensa-lx106-elf-gcc not found."
    echo "Downloading pre-built xtensa toolchain..."
    wget -qO- https://github.com/jepler/esp-open-sdk/releases/download/2018-06-10/xtensa-lx106-elf-standalone.tar.gz | tar -xz -C "$BUILD_DIR/"
    export PATH="$BUILD_DIR/xtensa-lx106-elf/bin:$PATH"
else
    echo "Cross-compiler xtensa-lx106-elf-gcc found."
fi

# --- 3. Fetch repositories ---
echo "Cloning MicroPython repository..."
if [ ! -d "$BUILD_DIR/micropython" ]; then
    git clone "$MICROPYTHON_REPO" "$BUILD_DIR/micropython" || { echo "Failed to clone MicroPython repository."; exit 1; }
fi

echo "Cloning MQTT_AS repository..."
if [ ! -d "$BUILD_DIR/micropython-mqtt" ]; then
    git clone "$MQTT_AS_REPO" "$BUILD_DIR/micropython-mqtt" || { echo "Failed to clone MQTT_AS repository."; exit 1; }
fi

# --- 4. Build MicroPython mpy-cross ---
echo "Building MicroPython cross-compiler (mpy-cross)..."
make -C "$BUILD_DIR/micropython/mpy-cross" || { echo "Failed to build mpy-cross."; exit 1; }

# --- 5. Inject MQTT_AS library ---
echo "Injecting MQTT_AS library..."
ESP8266_DIR="$BUILD_DIR/micropython/ports/esp8266"
ESP8266_MODULES="$ESP8266_DIR/modules"
mkdir -p "$ESP8266_MODULES"

MQTT_AS_SRC="$BUILD_DIR/micropython-mqtt/mqtt_as"

# Inject micropython-mqtt modules according to setup
if [ -f "$MQTT_AS_SRC/__init__.py" ]; then
    mkdir -p "$ESP8266_MODULES/mqtt_as"
    cp "$MQTT_AS_SRC/__init__.py" "$ESP8266_MODULES/mqtt_as/"
    echo "Copied mqtt_as/__init__.py to frozen modules."
else
    echo "Error: $MQTT_AS_SRC/__init__.py not found."
    exit 1
fi

# Put mqtt_local.py in deploy directory instead of freezing it
if [ -f "$MQTT_AS_SRC/mqtt_local.py" ]; then
    cp "$MQTT_AS_SRC/mqtt_local.py" "$DEPLOY_DIR/"
    echo "Copied mqtt_local.py to deploy directory for ease of making changes."
fi

# --- 6. Build firmware ---
echo "Building the ESP8266 firmware..."
cd "$ESP8266_DIR"
make submodules || true
make

# --- 7. Deploy firmware ---
echo "Deploying firmware..."
FIRMWARE_NAME="firmware-$(date +%Y%m%d-%H%M%S).bin"

if [ -f "build-GENERIC/firmware-combined.bin" ]; then
    cp "build-GENERIC/firmware-combined.bin" "$DEPLOY_DIR/$FIRMWARE_NAME"
    echo "Firmware successfully deployed to:"
    echo "$DEPLOY_DIR/$FIRMWARE_NAME"
else
    echo "Error: Firmware binary not found."
    exit 1
fi

echo "Pipeline completed successfully."