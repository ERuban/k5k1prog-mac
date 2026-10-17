<p align="center">
    <a href="https://github.com/ERuban/k5k1prog-mac/releases/latest"><img alt="K5K1 Prog"
         src="Resources/logo.svg" width="160"
    /></a>
</p>

<h1 align="center">K5K1 Prog</h1>

<p align="center">Quansheng UV-K5 / UV-K5 V3 / UV-K1 unter macOS sichern, wiederherstellen und flashen</p>

<p align="center"><a href="https://eruban.github.io/k5k1prog-mac/">eruban.github.io/k5k1prog-mac</a></p>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README_RU.md">Русский</a> |
  <a href="README_ES.md">Español</a> |
  <a href="README_ZH.md">中文</a>
</p>

*Dies ist eine Übersetzung. Bei Abweichungen gilt die englische Fassung: [README.md](README.md).*

<div align="center">

[![Download](https://img.shields.io/badge/Download-black?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/ERuban/k5k1prog-mac/releases/latest)
[![Donate](https://img.shields.io/badge/Donate-F15F2C?style=for-the-badge&logo=boosty&logoColor=white)](https://boosty.to/eruban/donate)

[![Release](https://img.shields.io/github/v/release/ERuban/k5k1prog-mac?style=flat)](https://github.com/ERuban/k5k1prog-mac/releases/latest)
![macOS 12+](https://img.shields.io/badge/macOS-12%2B-lightgrey?style=flat&logo=apple)
![Signed & Notarized by Apple](https://img.shields.io/badge/Signed%20%26%20Notarized-Apple-success?style=flat)
![No telemetry](https://img.shields.io/badge/telemetry-none-success?style=flat)

[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0-blue?style=flat)](LICENSE)
[![Tests](https://img.shields.io/github/actions/workflow/status/ERuban/k5k1prog-mac/tests.yml?branch=main&style=flat&label=tests)](https://github.com/ERuban/k5k1prog-mac/actions/workflows/tests.yml)
[![Downloads](https://img.shields.io/github/downloads/ERuban/k5k1prog-mac/total?style=flat)](https://github.com/ERuban/k5k1prog-mac/releases)

</div>

<br />

macOS-Portierung von **k5prog-win v0.1.26** (OneOfEleven), mit Verbesserungen.

Eine native macOS-App zum Sichern, Wiederherstellen und Flashen der Funkgeräte **Quansheng UV-K5 / UV-K5(8) / UV-K6 / UV-5R Plus**
(V1, DP32G030) und **UV-K5 V3 / UV-K1** (PY32F071) über ein Programmierkabel.

Sie übernimmt das Verhalten von [k5prog-win](https://github.com/OneOfEleven/k5prog-win) eins zu eins (dieselben
Schaltflächen, dieselbe Log-Ausgabe, dieselben Bytes auf der Leitung) und ergänzt den Firmware-Upload für die neueren
UV-K5 V3 und UV-K1, den k5prog-win nicht beherrscht, einen Kanaleditor sowie einige Sicherheitskorrekturen
(siehe [Unterschiede zu k5prog-win](#unterschiede-zu-k5prog-win)).

## Funktionen

- **Kalibrierung lesen / schreiben** (512 Byte ab `0x1E00`). Sichern Sie die Werkskalibrierung Ihres
  Funkgeräts, bevor Sie irgendetwas flashen.
- **Konfiguration lesen / schreiben** (Kanäle und Einstellungen, `0x0000–0x1CFF`).
- **Firmware flashen**, als rohe `.bin` oder als `.packed.bin` des Herstellers. Der Gerätetyp wird aus dem
  Image selbst erkannt und vor dem Schreiben mit dem Bootloader abgeglichen.
- **Memory Editor** für die 200 Kanäle des Funkgeräts, Original- und Karina-Firmware, UV-K5 V1 und UV-K1 /
  UV-K5 V3 (siehe [Kanäle bearbeiten](#kanäle-bearbeiten)): Kanäle bearbeiten, kopieren und per Drag & Drop
  zwischen zwei Funkgeräten verschieben, CHIRP-CSV und CHIRP-`.img` importieren / exportieren, Einschalttext
  bei Original-Firmware. Schreibt nach einer Sicherung nur die geänderten Kanäle und liest sie zur Kontrolle
  zurück. Einstellungen und Kalibrierung werden nie angetastet.
- **Gerätestatus** im Hauptfenster: welches Funkgerät am Kabel hängt, in welchem Modus und mit welcher
  Firmware-Kennung, unauffällig alle 2 Sekunden geprüft.
- **Einstellungen** (**K5K1 Prog → Settings…**): helles / dunkles Erscheinungsbild, Ordner für die
  Sicherungen des Editors.
- Universal-App (Apple Silicon und Intel), macOS 12 oder neuer. Für CH340-Kabel sind keine Treiber und
  keine zusätzliche Software nötig.
- Einstellungen (Port, Geschwindigkeit, Ausführlichkeit des Logs, Fensterposition, Erscheinungsbild) werden
  wie unter macOS üblich in `~/Library/Preferences/io.github.eruban.k5k1prog.plist` gespeichert. Neben der
  App wird nichts abgelegt.

## Unterstützte Funkgeräte

| Funkgerät | MCU | Bootloader | Kalibrierung / Konfiguration | Firmware |
|---|---|---|---|---|
| UV-K5, UV-K5(8), UV-K6, UV-5R Plus („V1“) | DP32G030 | 2.x – 4.x | ✅ | ✅ (k5prog-win-Protokoll) |
| UV-K5 V3, UV-K1 | PY32F071 | 7.xx (7.00.07 oder neuer) | ✅ | ✅ |
| UV-K5 V2, UV-K6 V2 | PY32F030 | 1.xx | ✅ | ❌ abgelehnt |

Das Modell steht unter dem Akku (V2, V3), das verlässliche Merkmal ist aber die Bootloader-Version: Versetzen Sie das
Funkgerät in den Bootloader-Modus und klicken Sie auf **Write Firmware**, im Log erscheint `Bootloader version '…'`.
UV-5R Plus Type-C mit Bootloader 5.x verwenden ein verschlüsseltes Bootloader-Protokoll und werden nicht unterstützt.

Auf echter Hardware getestet: mit einem UV-K5 V1 (Bootloader 2.00.06) und einem UV-K1 (Bootloader 7.03.01). Beide
wurden mit K5K1 Prog geflasht, Kalibrierung und Konfiguration wurden von beiden ausgelesen, und die Kalibrierung
wurde auf das UV-K1 geschrieben und durch Zurücklesen überprüft.

> [!WARNING]
> Firmware für V1-, V2- und V3/K1-Geräte ist **nicht austauschbar**. K5K1 Prog prüft das, bevor es
> irgendetwas sendet: Ein V1-Image auf einem 7.xx-Bootloader, ein V3/K1-Image auf jedem anderen Bootloader
> und jedes Image auf einem V2-Bootloader (1.xx) werden abgelehnt.
>
> K5K1 Prog **kann ein UV-K1-Image nicht von einem UV-K5-V3-Image unterscheiden** (gleicher Chip, gleicher
> Bootloader, und der Bootloader meldet das Modell nicht). Wählen Sie die Datei für Ihr Modell. Wenn Sie die
> falsche flashen, kann sich das Funkgerät fehlerhaft verhalten oder gar nicht starten, der Bootloader wird aber
> nicht überschrieben: Schalten Sie das Funkgerät mit gedrückter **PTT**-Taste ein und flashen Sie die richtige Datei.
>
> Das Flashen erfolgt auf eigene Gefahr.

## Installation

Mit [Homebrew](https://brew.sh):

```sh
brew install --cask eruban/tap/k5k1-prog
```

`brew upgrade` installiert neue Versionen (der Cask in [ERuban/homebrew-tap](https://github.com/ERuban/homebrew-tap)
wird bei jedem Release automatisch nachgezogen).

Oder laden Sie `K5K1-Prog-<version>.dmg` unter [Releases](../../releases) herunter, öffnen Sie die Datei und ziehen Sie **K5K1 Prog**
in den Ordner **Programme** (**Applications**). Die App ist mit einer Developer ID signiert und von Apple notarisiert und
öffnet sich daher ohne Warnungen. Eine `.zip` mit derselben App liegt ebenfalls bei.

Ab Version 1.1.0 aktualisiert sich die App selbst: Sie sucht einmal täglich auf GitHub nach einem neuen Release (und
über **K5K1 Prog → Check for Updates…**), zeigt die Neuerungen an und installiert sie mit einem Klick
([Sparkle](https://sparkle-project.org), Updates sind mit EdDSA signiert). Version 1.0.0 hat keine Update-Funktion,
installieren Sie 1.1.0 daher einmalig von Hand.

Oder bauen Sie die App aus dem Quellcode (benötigt die Xcode Command Line Tools, Swift 5.9 oder neuer):

```sh
git clone <this repository> k5k1prog-mac && cd k5k1prog-mac
./scripts/build_app.sh        # -> "K5K1 Prog.app" in the repository root (ad-hoc signed)
open "K5K1 Prog.app"
```

## Bedienung

Schließen Sie das Funkgerät mit einem Programmierkabel (2-poliger Kenwood-Stecker) an. Das Kabel erscheint als
`/dev/cu.usbserial-…` (bzw. `/dev/cu.wchusbserial…`, wenn der WCH-Treiber installiert ist). Wählen Sie es unter **Serial port** aus und behalten Sie
**38400 - k5/k6** bei.

### Zuerst sichern

1. Schalten Sie das Funkgerät normal ein.
2. Klicken Sie auf **Read Calibration** und speichern Sie die Datei an einem sicheren Ort. Sie enthält die
   gerätespezifische Kalibrierung von Sendeleistung und Akku, die Sie nirgendwo anders wiederbekommen.
3. Klicken Sie auf **Read Configuration** und speichern Sie die Datei.

Kalibrierung und Konfiguration werden auf dieselbe Weise zurückgeschrieben (**Write Calibration**,
**Write Configuration**), ebenfalls mit normal eingeschaltetem Funkgerät.

### Firmware flashen

1. Schalten Sie das Funkgerät aus, halten Sie **PTT** gedrückt und schalten Sie es ein. Das Display bleibt leer:
   Das Funkgerät ist im Bootloader-Modus.
2. Klicken Sie auf **Write Firmware** und wählen Sie die `.bin` (oder `.packed.bin`) für Ihr Modell.
3. Prüfen Sie das Log: `Bootloader version '…'` beginnt bei V1-Geräten mit `2`–`4` und bei V3/K1 mit `7`.
4. Warten Sie auf `write FLASH complete`. Das Funkgerät startet mit der neuen Firmware neu.

Folgen Sie danach den Anweisungen Ihrer Firmware (Speicher zurücksetzen, welche Kalibrierungsdateien zu laden sind
usw.). Manche Firmware-Pakete enthalten eine vollständige Kalibrierungsdatei, die Ihre werkseitigen Werte für
Sendeleistung und Akku ersetzt. Lesen Sie die Kalibrierung anschließend mit **Read Calibration** neu aus und
vergleichen Sie sie mit Ihrer Sicherung.

### Kanäle bearbeiten

1. Schalten Sie das Funkgerät normal ein, wählen Sie seinen Port und klicken Sie auf **Memory Editor…** (⌘E). Die
   Kanäle werden aus dem Funkgerät gelesen; das Fenster zeigt immer den aktuellen Inhalt des Funkgeräts.
2. **Firmware** und **Radio** werden anhand der Firmware-Kennung des Funkgeräts gewählt: Original-Firmware an
   ihrer Versionsnummer, Karina an ihrem Codenamen. Die Kennung von Karina ist auf dem UV-K5 V1 und dem UV-K1
   gleich, deshalb fragt der Editor einmalig, um welches Gerät es sich handelt. Eine unbekannte Firmware wird
   schreibgeschützt geöffnet, bis Sie eine Auswahl treffen. Wählen Sie etwas, dem die Firmware-Kennung
   widerspricht, weist der Editor in Rot darauf hin: Die Kanalwerte (Modulationsart, Schrittweite, Scrambler)
   würden falsch gelesen und geschrieben.
3. Doppelklicken Sie auf eine Zelle, um sie zu bearbeiten. Markieren Sie mehrere Kanäle, um sie gemeinsam zu
   ändern; dazu **Set Power**, **Delete** und ⌘Z zum Rückgängigmachen.
4. **Write to Radio…** listet die Änderungen auf, sichert die Konfiguration des Funkgeräts
   (`~/Documents/K5K1 Prog Backups/`, siehe Einstellungen), prüft, ob sich das Funkgerät seit dem Auslesen
   verändert hat, schreibt nur die geänderten Blöcke, liest sie zurück und vergleicht sie. Eine Sicherung stellen
   Sie mit **Write Configuration** wieder her.

Kanäle auf ein anderes Funkgerät kopieren: Öffnen Sie für jedes Funkgerät einen Editor (einen pro Port) und ziehen
Sie die Kanäle hinüber oder verwenden Sie Copy / Paste, oder nutzen Sie **Export Channels…** im einen und
**Import Channels…** im anderen Editor. Werte, die die andere Firmware nicht kennt (USB bei Original-Firmware,
Karinas Scrambler-Liste, feine Schrittweiten), werden umgewandelt und aufgelistet. Beim Import bleiben die
Kanalnummern erhalten; Einstellungen in der Datei werden ignoriert. Formate: CHIRP-CSV, CHIRP-`.img` (Original oder
Karina, UV-K5 / UV-K1) und eine Konfigurations-`.bin` aus Read Configuration (eine `.bin` verrät nicht, von welchem
Funkgerät sie stammt: Wählen Sie es im Importdialog aus).

Der Editor prüft das Funkgerät alle 2 Sekunden, solange sein Fenster aktiv ist. Wird ein anderes Funkgerät
angeschlossen, liest er dieses aus (bzw. weist bei noch nicht geschriebenen Änderungen darauf hin und schreibt
nicht darauf).

Bearbeitet wird nur der Kanalspeicher (200 Kanäle im Original-Layout, das Original-Firmware, Karina und F4HWN
gemeinsam nutzen). Andere Firmware, mehr als 200 Kanäle (F4HWN auf dem UV-K1) und die Einstellungen des
Funkgeräts werden nicht unterstützt.

## Unterschiede zu k5prog-win

Alle zugunsten der Sicherheit:

1. **Firmware-Upload für UV-K5 V3 / UV-K1** (PY32F071, Bootloader 7.xx), siehe unten.
2. Eine V1-Firmwaredatei (DP32G030) wird nie an einen 7.xx-Bootloader gesendet, und ein Firmware-Upload auf ein
   UV-K5 V2 / K6 V2 (Bootloader 1.xx, PY32F030) wird abgelehnt: Mit V1-Firmware bleibt das Display eines solchen
   Geräts leer.
3. **Konfigurationsdatei, deren Größe kein Vielfaches von 128 Byte ist.** k5prog-win liest über das Ende seines
   Puffers hinaus und schreibt zufälligen Speicherinhalt ins Funkgerät. Hier behält der Rest des letzten Blocks die
   eigenen Bytes des Funkgeräts (die vorher ausgelesen werden). Normale Dateien (7424 / 8192 / 512 Byte) sind nicht
   betroffen.
4. Die Portliste zeigt `/dev/cu.*` (das macOS-Gegenstück zur Liste der COM-Ports). Die Statusleiste hat keine
   „RX BREAK“-Anzeige.
5. Das Hauptfenster schreibt beim Start und bei einem Portwechsel keine Geräteabfrage ins Log („Fetching
   radio details .. radio not detected“). Stattdessen wird der Gerätestatus in der Statusleiste angezeigt, und
   die Schaltflächen richten sich danach: Konfiguration, Kalibrierung und der Editor brauchen das Funkgerät im
   normalen Modus, Write Firmware braucht es im Firmware-Update-Modus, ohne Funkgerät ist nichts aktiv. Lange
   Log-Zeilen werden umbrochen.
6. **Einstellungen** werden in den macOS-Einstellungen (`io.github.eruban.k5k1prog`) gespeichert, nicht in einer
   ini-Datei neben der App: Auf einem Mac ist dieser Ordner `/Applications`. Die Schlüssel sind die aus
   `k5prog_win.ini` (`MainForm.Top`, `GUI.Verbose`, `SerialPort.Name`, …). Die Versionen 1.0 / 1.1 verwendeten
   `K5K1Prog.ini`; diese Datei wird einmalig importiert und gelöscht. Dateidialoge starten in `~/Documents`.

Alles andere entspricht dem Original: Schaltflächen, Reihenfolge der Abläufe, Timeouts (Hello 2×1 s, Lesen 3 s,
Schreiben 2 s, Flashen 3 s), Wiederholversuche, Prüfungen, jede Log-Zeile und jeder Meldungstext, das Protokoll
(Frames, XOR-Tabellen, CRC, Session-ID `6A 39 57 64`, 128-Byte-Konfigurationsblöcke, 256-Byte-Flash-Blöcke, die
Korrektur der Bootloader-Version `4.00.07` → `*.00.07`), die Einstellungsschlüssel und Esc zum Abbrechen einer
Übertragung.

## Firmware-Upload für UV-K5 V3 / UV-K1

**Write Firmware** erkennt den Dateityp an der Vektortabelle: Bei einem PY32F071-Image liegt der Reset-Vektor
bei `0x080xxxxx`, bei einem DP32G030-Image bei `0x0000xxxx`. Rohe `.bin`- und `.packed.bin`-Dateien des Herstellers
werden für beide akzeptiert. V1-Dateien laufen weiterhin über den unveränderten Weg von k5prog-win.

PY32-Protokoll (wie im serialtool von muzkr):

- der Bootloader muss mit `7` beginnen und `7.00.07` oder neuer sein, sonst wird nichts gesendet;
- 5 gültige `0x0518`-Beacon-Intervalle (5–1000 ms) in Folge, dann `0x0530` mit den ersten 4 Zeichen
  der Bootloader-Version, einmal pro Beacon, dreimal;
- `0x0519`-Seiten: Zeitstempel LE32, Seite LE16, Seitenanzahl LE16, 4 × `00`, 256 Datenbytes (die letzte
  Seite mit `00` aufgefüllt); Antwort `0x051A` Zeitstempel / Seite / Fehler; 3 s pro Seite, bis zu 3 erneute
  Sendungen einer Seite nach einem Fehler oder einer ausbleibenden Antwort;
- maximale Image-Größe `0x1D800` (Anwendungsbereich ab `0x08002800`, 118 KB);
- kein Neustart-Befehl am Ende, der Bootloader startet die neue Firmware selbst.

Falsche Kombinationen werden abgelehnt, bevor irgendetwas geschrieben wird: eine V1-Datei auf einem 7.xx-Bootloader,
eine V3/K1-Datei auf jedem anderen Bootloader, jede Datei auf einem V2-Bootloader (1.xx), ein Bootloader älter als
7.00.07, ein zu großes Image, ein Funkgerät, das nicht im Bootloader-Modus ist.

## Entwicklung

Beiträge sind willkommen: siehe [CONTRIBUTING.md](CONTRIBUTING.md) (und [AGENTS.md](AGENTS.md) für KI-Coding-Agenten;
beide auf Englisch).

```sh
swift test                    # 76 tests: simulator, protocol, reference comparisons, channels
swift run k5emu --mode boot --bl-version 7.03.01 --link /tmp/k5com   # simulated K1 bootloader
```

- `Sources/K5Core`: Protokoll, Verarbeitung der Firmwaredateien, die Logik von k5prog-win; `Channels.swift` und
  `ChannelTransfer.swift` für den Memory Editor (Kanal-Layout, Profile, CSV / `.img`).
- `Sources/K5K1Prog`: die AppKit-App.
- `docs/`: die Website (GitHub Pages, fünf Sprachen), erzeugt von `scripts/build_site.py`; bearbeiten Sie die
  Texte dort und führen Sie das Skript aus.
- `scripts/chirp-golden/golden.py`: erzeugt die Kanal-Testreferenzen mit den echten CHIRP-Treibern
  (synthetische Images, keine persönlichen Daten). Nur nötig, wenn sich die Profile ändern.
- `Sources/K5Sim`, `Sources/k5emu`: ein UV-K5-Simulator auf einem Pseudo-Terminal. Normalmodus, V1-Bootloader
  und `--bl-version 7.xx.xx` für den PY32-Bootloader. Fehlerinjektion für abgelehnte oder verlorene Seiten in
  `RadioSim.Options`.
- Die Tests brauchen keine Firmwaredateien: Firmware-Uploads (V1 und PY32, roh und `.packed`) verwenden synthetische
  Images mit gültiger Vektortabelle.
- GitHub Actions (`.github/workflows/tests.yml`) baut bei jedem Push und Pull Request, führt die Tests aus und
  erstellt das App-Bundle.

Release: Erhöhen Sie `K5.version` in `Sources/K5Core/Constants.swift`, schreiben Sie `release-notes/<version>.md`
und starten Sie dann `./scripts/release.sh`. Das Skript führt die Tests aus, baut die Universal-App, signiert sie und
das eingebettete Sparkle-Framework mit dem Zertifikat „Developer ID Application“ (Hardened Runtime), notarisiert die
App und die `.dmg` und heftet das Notarisierungsticket an (Stapling), signiert die Update-`.zip` mit dem
Sparkle-EdDSA-Schlüssel und schreibt `dist/` (`.dmg`, `.zip`, `appcast.xml`, `SHA256SUMS.txt`, `RELEASE_NOTES.md`).
Hängen Sie alle diese Dateien an das GitHub-Release an: Installierte Kopien lesen `releases/latest/download/appcast.xml`.
Die einmalige Einrichtung (notarytool-Profil, Sparkle-Schlüssel in `Resources/SparklePublicKey.txt`) ist im Kopf des
Skripts beschrieben. Das Skript veröffentlicht nichts.

Test-Hooks (für die normale Nutzung nicht nötig):

- `K5PROG_EXTRA_PORTS=/tmp/k5com` fügt der Portliste Gerätepfade hinzu (für `k5emu --link /tmp/k5com`).
- `K5PROG_UITEST=readcalib,writecalib,quit` steuert zusammen mit `K5PROG_UITEST_OPEN/SAVE/MEMO` die echte App
  ohne Dialoge (außerdem `editor`, `editor-import`, `editor-write`, `editor-export`, `snap` mit
  `K5PROG_UITEST_SNAP=<dir>` für Fenster-Snapshots, `wait`; vollständige Liste in [AGENTS.md](AGENTS.md)).
- `K5PROG_BACKUP_DIR=<dir>` legt die Sicherungen des Memory Editors dort ab.
- `K5PROG_CHANNEL_DUMPS=<dir>` vergleicht die Kanaldekodierung Ihrer eigenen Dumps mit der von CHIRP
  (`<name>.<profile>.bin` + Ausgabe von `golden.py --decode` als `.json`).
- `K5PROG_SETTINGS_SUITE=<name>` hält die Einstellungen eines Entwicklungs- / Testlaufs von den echten getrennt
  (und überspringt den Import einer alten `K5K1Prog.ini`).
- `K5PROG_SPARKLE_FEED=<url>` richtet den Updater auf einen anderen Appcast (lokale Update-Tests,
  `open --env K5PROG_SPARKLE_FEED=… "K5K1 Prog.app"`).

## Unterstützung

K5K1 Prog ist kostenlos. Wenn es Ihr Funkgerät gerettet oder Ihnen Zeit gespart hat, können Sie
[**spenden**](https://boosty.to/eruban/donate) (über Boosty). Spenden finanzieren das Apple-Developer-Konto, mit dem die
App signiert und notarisiert bleibt, sowie Tests an echten Funkgeräten.

## Danksagungen

- K5K1 Prog von [Evgeny Ruban](https://github.com/ERuban).
- [k5prog-win](https://github.com/OneOfEleven/k5prog-win) von OneOfEleven, das Programm, das diese App
  portiert (GPL v3).
- [k5prog](https://github.com/sq5bpf/k5prog) von Jacek Lipkowski SQ5BPF, auf dessen Routinen zur Kommunikation
  mit dem Funkgerät k5prog-win aufbaut (GPL v3).
- Bootloader-Protokoll für UV-K5 V3 / UV-K1 nach der Implementierung im serialtool von muzkr in
  [armel/uv-k1-k5v3-firmware-custom](https://github.com/armel/uv-k1-k5v3-firmware-custom).
- Kanal-Layout und Wertelisten des Memory Editors folgen den [CHIRP](https://github.com/kk7ds/chirp)-Treibern:
  UV-K5 von Jacek Lipkowski SQ5BPF, UV-K1 von Thibaut Berg und Karinas CHIRP-Module von M2Boo (basierend auf
  den Treibern von egzumer / JOC2 / F4HWN), GPLv2 oder später. CSV und `.img` sind Formate von CHIRP.
- Karina-Firmware von autumn1rain; der Memory Editor unterstützt ihr Kanal-Layout.

## Lizenz

GPL v3, wie k5prog-win und k5prog. Siehe [LICENSE](LICENSE). Copyright © 2026 Evgeny Ruban.

K5K1 Prog ist eine modifizierte Version von k5prog-win: Das C++/VCL-Windows-Programm wurde für macOS in Swift neu
geschrieben, und der Firmware-Upload für UV-K5 V3 / UV-K1, der Memory Editor und die oben aufgeführten
Sicherheitskorrekturen wurden ergänzt (2026).

Diese Software steht in keiner Verbindung zu Quansheng. Senden Sie nur auf Frequenzen und mit Sendeleistungen,
für die Sie eine Zulassung besitzen.
