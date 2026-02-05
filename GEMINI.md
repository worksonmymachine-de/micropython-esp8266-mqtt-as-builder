# Projekt: Custom MicroPython Build-Pipeline (ESP8266)

## Zielsetzung

Entwicklung einer automatisierten Toolchain zur Erstellung maßgeschneiderter MicroPython-Firmware für den **D1 mini (ESP8266)**. Die Pipeline soll manuell getriggert werden und externe Abhängigkeiten (z. B. asynchrone MQTT-Libraries) direkt in das Build-Artefakt integrieren.

---

## Technische Eckpunkte

* **Infrastruktur:** Virtualisierte Umgebung auf **Proxmox** (z. B. Debian-VM oder Docker-Container).
* **Source:** Automatischer Checkout des aktuellsten MicroPython-Stamms von **GitHub**.
* **Customization:** Integration spezifischer Zusatzmodule (z. B. `micropython-lib` oder dedizierte Repos für **Async-MQTT**) vor dem Kompiliervorgang.
* **Build-Target:** ESP8266 Architektur (D1 mini Profil).
* **Output-Management:** * Automatisierte Benennung der Binaries nach Version/Zeitstempel.
  * Export auf eine lokale Netzwerkfreigabe (SMB/NFS) oder Upload in ein GitHub-Repository (Releases).

---

## Workflow-Schema

1. **Trigger:** Manueller Start des Build-Prozesses.
2. **Fetch:** `git clone` des offiziellen MicroPython Repos.
3. **Fetch:** `git clone` des MicroPython MQTT_AS Repos.
4. **Inject:** Kopieren der MQTT_AS-Sourcen in das Filesystem-Modul des Builds.
5. **Compile:** Build-Vorgang mittels Cross-Compiler (`xtensa-lx106-elf`).
6. **Deploy:** Verschieben der fertigen `.bin`-Datei an das Ziel-Laufwerk/Repo.

## Resources

### MicroPython

git repo URL: <https://github.com/micropython/micropython.git>

### MQTT_AS

git repo URL: <https://github.com/peterhinch/micropython-mqtt.git>
howto install on ESP8266: <https://github.com/peterhinch/micropython-mqtt/blob/master/README.md#22-installation-on-esp8266>
