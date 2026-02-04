#!/bin/bash

# Exit on error
set -e

# --- Configuration ---
MICROPYTHON_REPO="https://github.com/micropython/micropython.git"
MQTT_AS_REPO="https://github.com/peterhinch/micropython-mqtt.git"
BUILD_DIR="build"

# --- 1. Fetch repositories ---
echo "Cloning MicroPython repository..."
git clone "$MICROPYTHON_REPO" "$BUILD_DIR/micropython"

echo "Cloning MQTT_AS repository..."
git clone "$MQTT_AS_REPO" "$BUILD_DIR/micropython-mqtt"

# --- 2. Setup build environment (Debian) ---
echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y make unrar-free autoconf automake libtool gcc g++ gperf \
    flex bison texinfo gawk ncurses-dev libexpat-dev python-dev python-pip \
    sed git unzip bash help2man wget bzip2 libtool-bin

# --- 3. Build MicroPython ---
echo "Building MicroPython..."
cd "$BUILD_DIR/micropython/mpy-cross"
make

cd ../ports/esp8266

# --- 4. Install Python dependencies ---
echo "Installing Python dependencies for the build..."
pip install -r requirements.txt

# --- 5. Inject MQTT_AS library ---
echo "Injecting MQTT_AS library..."
mkdir -p modules
cp "../../micropython-mqtt/mqtt_as/mqtt_as.py" modules/
cp "../../micropython-mqtt/mqtt_as/mqtt_local.py" modules/


# --- 6. Build firmware ---
echo "Building the ESP8266 firmware..."
make

# --- 7. Deploy firmware ---
echo "Deploying firmware..."
FIRMWARE_NAME="firmware-$(date +%Y%m%d-%H%M%S).bin"
cd build-GENERIC
mv firmware-combined.bin "$FIRMWARE_NAME"
mkdir -p "../../../..//deploy"
mv "$FIRMWARE_NAME" "../../../../../deploy/"

echo "Build complete! Firmware is in the 'deploy' directory."
