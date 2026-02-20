# Custom MicroPython Build Pipeline (ESP8266)

## Objective

An automated toolchain for building custom MicroPython firmware for the **D1 Mini (ESP8266)**. The pipeline is triggered manually and bundles external dependencies (e.g. async MQTT libraries) directly into the firmware image.

---

## Technical Overview

* **Infrastructure:** Virtualized environment on **Proxmox** (e.g. Debian VM or Docker container).
* **Source:** Automatic checkout of the latest MicroPython upstream from **GitHub**.
* **Customization:** Integration of additional modules (e.g. `micropython-lib` or dedicated **Async-MQTT** repos) prior to compilation.
* **Build Target:** ESP8266 architecture (D1 Mini profile).
* **Output Management:**
  * Automated binary naming by version/timestamp.
  * Export to a local network share (SMB/NFS) or upload to a GitHub repository (Releases).

---

## Workflow

1. **Trigger:** Manually start the build process.
2. **Fetch:** `git clone` the official MicroPython repository.
3. **Fetch:** `git clone` the MicroPython MQTT_AS repository.
4. **Inject:** Copy the MQTT_AS sources into the build's frozen module directory.
5. **Compile:** Build firmware using the cross-compiler (`xtensa-lx106-elf`).
6. **Deploy:** Move the resulting `.bin` file to the target drive/repository.

---

## Resources

### MicroPython

* Repository: <https://github.com/micropython/micropython.git>

### MQTT_AS

* Repository: <https://github.com/peterhinch/micropython-mqtt.git>
* Installation guide (ESP8266): <https://github.com/peterhinch/micropython-mqtt/blob/master/README.md#22-installation-on-esp8266>
  * copy `__init__.py` to `esp8266/modules` in the source tree, build and deploy.
  * copy `mqtt_local.py` to the filesystem for ease of making changes.

### Cross compiler

* Install cross compiler in venv
* Verify if micropython-embed is the one to use

```bash
pip3 install micropython-embed
```

### Deployment

* For now move the firmware file to the directory `deploy` in the project dir.
