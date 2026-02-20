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
    echo "Building pfalcon/esp-open-sdk toolchain from source..."
    
    if [ ! -d "$BUILD_DIR/esp-open-sdk" ]; then
        git clone --recursive https://github.com/pfalcon/esp-open-sdk.git "$BUILD_DIR/esp-open-sdk" || { echo "Failed to clone esp-open-sdk."; exit 1; }
    fi
    
    # Export path for the built cross-compiler
    if [ -d "$BUILD_DIR/esp-open-sdk/xtensa-lx106-elf/bin" ]; then
        export PATH="$BUILD_DIR/esp-open-sdk/xtensa-lx106-elf/bin:$PATH"
    fi
    
    if ! command -v xtensa-lx106-elf-gcc &> /dev/null; then
        echo "Compiling esp-open-sdk (this will take a while)..."
        
        # crosstool-NG's bash version check fails on modern versions (like 5.x)
        # We patch it directly before compiling.
        python3 -c "
import os
for file_name in ['configure.ac', 'configure']:
    file_path = f'$BUILD_DIR/esp-open-sdk/crosstool-NG/{file_name}'
    if os.path.exists(file_path):
        with open(file_path, 'r') as f:
            content = f.read()
        content = content.replace('3\\\\.[1-9]|4', '3\\\\.[1-9]|4|5')
        content = content.replace('bash >= 3.1', 'bash >= 3.1 or later')
        with open(file_path, 'w') as f:
            f.write(content)
"

        # crosstool-NG's GNU mirror URLs for older packages like isl consistently 404 now.
        # We must prepopulate its tarball cache.
        TARBALLS_DIR="$BUILD_DIR/esp-open-sdk/crosstool-NG/.build/tarballs"
        rm -rf "$TARBALLS_DIR"
        mkdir -p "$TARBALLS_DIR"
        echo "Pre-fetching crosstool-NG dependencies..."
        # Always exit on failure to prevent 404 HTML pages being treated as tarballs
        wget -nv -c -O "$TARBALLS_DIR/isl-0.14.tar.bz2" "https://gcc.gnu.org/pub/gcc/infrastructure/isl-0.14.tar.bz2" || exit 1
        wget -nv -c -O "$TARBALLS_DIR/gmp-6.0.0a.tar.bz2" "https://ftp.gnu.org/gnu/gmp/gmp-6.0.0a.tar.bz2" || exit 1
        wget -nv -c -O "$TARBALLS_DIR/mpfr-3.1.2.tar.bz2" "https://ftp.gnu.org/gnu/mpfr/mpfr-3.1.2.tar.bz2" || exit 1
        wget -nv -c -O "$TARBALLS_DIR/mpc-1.0.2.tar.gz" "https://ftp.gnu.org/gnu/mpc/mpc-1.0.2.tar.gz" || exit 1
        wget -nv -c -O "$TARBALLS_DIR/cloog-0.18.1.tar.gz" "https://gcc.gnu.org/pub/gcc/infrastructure/cloog-0.18.1.tar.gz" || exit 1
        wget -nv -c -O "$TARBALLS_DIR/binutils-2.25.1.tar.bz2" "https://ftp.gnu.org/gnu/binutils/binutils-2.25.1.tar.bz2" || exit 1
        wget -nv -c -O "$TARBALLS_DIR/gcc-4.8.5.tar.bz2" "https://ftp.gnu.org/gnu/gcc/gcc-4.8.5/gcc-4.8.5.tar.bz2" || exit 1
        wget -nv -c -O "$TARBALLS_DIR/expat-2.1.0.tar.gz" "https://github.com/libexpat/libexpat/releases/download/R_2_1_0/expat-2.1.0.tar.gz" || exit 1

        # Fix GCC 4.8.5 C++17 compilation error (operator++ on bool)
        # The default host compiler (GCC 12) uses C++17, which dropped this operator.
        PATCH_DIR="$BUILD_DIR/esp-open-sdk/crosstool-NG/local-patches/gcc/4.8.5"
        mkdir -p "$PATCH_DIR"
        cat << 'EOF' > "$PATCH_DIR/0001-fix-bool-increment.patch"
--- a/gcc/reload1.c
+++ b/gcc/reload1.c
@@ -86,7 +86,7 @@
 rtx reload_sp_rtx;
 
 /* Nonzero means we couldn't get enough spill registers.  */
-bool spill_indirect_levels;
+char spill_indirect_levels;
 
 /* Nonzero if caller-saves has been set up.  */
 static int caller_saves_initialized;
EOF

        # Explicitly compile esp-open-sdk with older C++ standard to fix GCC 4.8.5 `bool` increment errors.
        SHELL=/bin/bash CXXFLAGS="-std=gnu++11" CT_ALLOW_BUILD_AS_ROOT=yes CT_ALLOW_BUILD_AS_ROOT_SURE=yes make -C "$BUILD_DIR/esp-open-sdk" STANDALONE=y || { echo "Failed to compile esp-open-sdk."; exit 1; }
        
        export PATH="$BUILD_DIR/esp-open-sdk/xtensa-lx106-elf/bin:$PATH"
    fi
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