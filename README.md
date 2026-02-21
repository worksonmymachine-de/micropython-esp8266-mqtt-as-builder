# Custom MicroPython Build Pipeline (ESP8266)

## Objective

An automated toolchain for building custom MicroPython firmware for the **D1 Mini (ESP8266)**. The pipeline is triggered manually and bundles external dependencies (specifically the async MQTT library) directly into the firmware image as "frozen bytecode" to save RAM.

---

## Technical Overview

* **Infrastructure:** Designed for a virtualized environment (e.g., **Proxmox** LXC/VM running Debian/Ubuntu). It leverages **Docker** (`larsks/esp-open-sdk`) to completely bypass the need for native legacy C compilers.
* **Source:** Automatic shallow-clone of the *latest stable release* of MicroPython from **GitHub**.
* **Customization:** Integration of the `peterhinch/micropython-mqtt` asynchronous MQTT library directly into the compilation process.
* **Build Target:** ESP8266 architecture (D1 Mini profile).
* **Output Management:**
  * Automated binary naming format: `ESP8266-micropython-[version]-mqtt-as-[date]-[time].bin`
  * Exported to a local `export/` directory, which can be easily bind-mounted to a network share (SMB/NFS) in Proxmox.

---

## Workflow

1. **Environment Setup:** The script silently verifies/installs `git` and `docker.io`, and ensures the Docker daemon is running.
2. **Fetch:** Remotely detects the latest stable MicroPython tag and performs a fast, shallow `git clone` of both MicroPython and the MQTT_AS repository.
3. **Build `mpy-cross`:** Compiles the MicroPython cross-compiler inside the Docker container using all available CPU cores.
4. **Inject:** * Copies the `mqtt_as/__init__.py` source into the build's frozen module directory (`ports/esp8266/modules/mqtt_as/`).
   * Copies `mqtt_local.py` to the `export/` folder so it can be easily edited and uploaded to the filesystem later.
5. **Compile:** Fetches required ESP8266 submodules and builds the firmware inside the Docker container silently.
6. **Export:** Copies the resulting `.bin` file to the `export/` directory with the dynamically generated version/timestamp filename.

---

## Resources

### MicroPython

* Repository: <https://github.com/micropython/micropython.git>

### MQTT_AS

* Repository: <https://github.com/peterhinch/micropython-mqtt.git>
* Installation guide (ESP8266): <https://github.com/peterhinch/micropython-mqtt/blob/master/README.md#22-installation-on-esp8266>
  * The script automatically handles copying `__init__.py` to the `modules` tree for freezing.
  * The script extracts `mqtt_local.py` to the `export` directory for easy configuration.

### Cross Compiler (Docker)

This pipeline no longer relies on native host toolchains, Python virtual environments, or `micropython-embed`. 

Instead, it uses the official community-supported Docker container for ESP8266 builds:
* Docker Image: `larsks/esp-open-sdk`
* The script automatically downloads this image and mounts the local working directory into it to compile `mpy-cross` and the final firmware. 
* *Note:* If running inside a Proxmox LXC container, ensure **Nesting** is enabled in the container features so Docker can run properly.

### Deployment

* The finished firmware binary and the `mqtt_local.py` configuration file are automatically moved to the `export/` directory within the project root. 
* To make this accessible over your network, you can mount a Samba/NFS share directly to this `export/` folder.
