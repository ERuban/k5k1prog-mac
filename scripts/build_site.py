#!/usr/bin/env python3
# K5K1 Prog - builds the GitHub Pages site in docs/ (one page per language) from the template
# and the texts below. Run after changing a text: python3 scripts/build_site.py
#
# Copyright (C) 2026 Evgeny Ruban. GPL v3 (see LICENSE).

import html
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
SITE = "https://eruban.github.io/k5k1prog-mac/"
REPO = "https://github.com/ERuban/k5k1prog-mac"
LATEST = REPO + "/releases/latest"
DONATE = "https://boosty.to/eruban/donate"
BREW = "brew install --cask eruban/tap/k5k1-prog"

# language code -> (folder, name in the switcher, html lang)
LANGS = [
    ("en", "", "English", "en"),
    ("ru", "ru/", "Русский", "ru"),
    ("es", "es/", "Español", "es"),
    ("de", "de/", "Deutsch", "de"),
    ("zh", "zh/", "中文", "zh-Hans"),
]

T = {
    "en": {
        "title": "K5K1 Prog – Quansheng UV-K5 & UV-K1 software for Mac",
        "description": "Free Mac app for Quansheng UV-K5, UV-K5 V3 and UV-K1: back up calibration and configuration, flash firmware, edit channels (CHIRP CSV, .img). Open source.",
        "tagline": "Back up, restore and flash Quansheng UV-K5 / UV-K5 V3 / UV-K1 radios on your Mac.",
        "download": "Download for macOS",
        "github": "Source on GitHub",
        "donate": "Donate",
        "brew": "or with Homebrew:",
        "facts": ["Free and open source (GPL v3)", "Signed and notarized by Apple", "No telemetry",
                  "macOS 12 or newer, Apple Silicon and Intel"],
        "shot_main": "Main window: the radio on the cable, in normal mode",
        "shot_editor": "Memory Editor: the radio's channels",
        "features_h": "What it does",
        "features": [
            ("💾", "Back up and restore", "Read and write the radio's calibration and configuration. Keep your factory calibration safe before you flash anything."),
            ("⚡", "Flash firmware", "UV-K5 V1 and the newer UV-K5 V3 / UV-K1. The firmware file and the bootloader are checked before a single byte is sent; wrong combinations are refused."),
            ("📋", "Edit channels", "200 channels, stock and Karina firmware. Copy channels between radios, import and export CHIRP CSV and .img. Only the changed channels are written, after a backup, and read back to verify."),
            ("📡", "Knows your radio", "The status bar shows which radio is on the cable, in which mode and with which firmware. The buttons follow it, so the wrong operation can't be started."),
            ("🔁", "One to one with k5prog-win", "The same buttons, log and bytes on the wire as the Windows tool k5prog-win, plus a few safety fixes."),
            ("🔄", "Stays up to date", "Updates itself from GitHub releases. With Homebrew, brew upgrade installs new versions."),
        ],
        "radios_h": "Supported radios",
        "th": ["Radio", "Chip", "Bootloader", "Backup and restore", "Firmware"],
        "yes": "Yes", "refused": "Refused",
        "v2_note": "V1 firmware leaves a V2 with a blank screen, so the app refuses it.",
        "radios_note": "The bootloader version tells the models apart: switch the radio on with PTT held and press Write Firmware, the log shows it.",
        "safety_h": "Before you start",
        "safety": [
            "Press Read Calibration first and keep the file: it holds your radio's own TX power and battery calibration, and you can't get it anywhere else.",
            "The app can't tell a UV-K1 firmware file from a UV-K5 V3 one: pick the file for your model.",
            "Flashing is at your own risk.",
        ],
        "install_h": "Install",
        "install": [
            "Download the .dmg, open it and drag K5K1 Prog to Applications.",
            "Or with Homebrew: <code>" + BREW + "</code>",
            "Connect the radio with a programming cable (2-pin Kenwood plug). It shows up as <code>/dev/cu.usbserial-…</code>",
        ],
        "guide": "Full guide on GitHub →",
        "nav": ["GitHub", "Releases", "Guide", "Contributing", "Donate"],
        "footer1": "Free and open source (GPL v3). macOS port of k5prog-win by OneOfEleven, based on k5prog by Jacek Lipkowski SQ5BPF. Channel layout from the CHIRP drivers. Karina firmware by autumn1rain.",
        "footer2": "Not affiliated with Quansheng.",
    },
    "ru": {
        "title": "K5K1 Prog – прошивка и программирование Quansheng UV-K5 / UV-K1 на Mac",
        "description": "Бесплатная программа для Mac: бэкап калибровки и конфигурации, прошивка и редактор каналов (CSV и .img CHIRP) для Quansheng UV-K5, UV-K5 V3 и UV-K1.",
        "tagline": "Резервная копия, восстановление и прошивка раций Quansheng UV-K5 / UV-K5 V3 / UV-K1 на Mac.",
        "download": "Скачать для macOS",
        "github": "Исходники на GitHub",
        "donate": "Поддержать",
        "brew": "или через Homebrew:",
        "facts": ["Бесплатно, открытый код (GPL v3)", "Подписано и нотаризовано Apple", "Без телеметрии",
                  "macOS 12 и новее, Apple Silicon и Intel"],
        "shot_main": "Главное окно: рация на кабеле, обычный режим",
        "shot_editor": "Редактор памяти: каналы рации",
        "features_h": "Что умеет",
        "features": [
            ("💾", "Резервная копия и восстановление", "Чтение и запись калибровки и конфигурации рации. Сохраните заводскую калибровку до любой прошивки."),
            ("⚡", "Прошивка", "UV-K5 V1 и новые UV-K5 V3 / UV-K1. Файл прошивки и загрузчик проверяются до первого отправленного байта, неподходящие сочетания отклоняются."),
            ("📋", "Редактор каналов", "200 каналов, стоковая прошивка и Карина. Копирование каналов между рациями, импорт и экспорт CHIRP CSV и .img. Пишутся только изменённые каналы, после бэкапа, с проверкой чтением."),
            ("📡", "Видит вашу рацию", "В строке статуса видно, какая рация на кабеле, в каком режиме и с какой прошивкой. Кнопки следуют за ней, так что не та операция не запустится."),
            ("🔁", "Один в один с k5prog-win", "Те же кнопки, лог и байты в линии, что у виндовой k5prog-win, плюс несколько исправлений безопасности."),
            ("🔄", "Обновляется сама", "Обновления из релизов на GitHub. С Homebrew новые версии ставит brew upgrade."),
        ],
        "radios_h": "Поддерживаемые рации",
        "th": ["Рация", "Чип", "Загрузчик", "Бэкап и восстановление", "Прошивка"],
        "yes": "Да", "refused": "Отказ",
        "v2_note": "Прошивка от V1 оставляет V2 с пустым экраном, поэтому приложение отказывается её шить.",
        "radios_note": "Модель надёжно определяется по версии загрузчика: включите рацию с зажатой PTT и нажмите Write Firmware, версия появится в логе.",
        "safety_h": "Перед началом",
        "safety": [
            "Сначала нажмите Read Calibration и сохраните файл: в нём калибровка мощности передатчика и батареи именно вашей рации, взять её больше негде.",
            "Приложение не может отличить прошивку UV-K1 от прошивки UV-K5 V3: выбирайте файл для своей модели.",
            "Прошивка на ваш страх и риск.",
        ],
        "install_h": "Установка",
        "install": [
            "Скачайте .dmg, откройте и перетащите K5K1 Prog в «Программы».",
            "Или через Homebrew: <code>" + BREW + "</code>",
            "Подключите рацию кабелем для программирования (двухштырьковый разъём Kenwood). Порт будет называться <code>/dev/cu.usbserial-…</code>",
        ],
        "guide": "Полное руководство на GitHub →",
        "nav": ["GitHub", "Релизы", "Руководство", "Участие", "Поддержать"],
        "footer1": "Бесплатно, открытый код (GPL v3). Порт k5prog-win (OneOfEleven) на macOS, основан на k5prog (Jacek Lipkowski SQ5BPF). Раскладка каналов из драйверов CHIRP. Прошивка Karina — автор autumn1rain.",
        "footer2": "Не связано с Quansheng.",
    },
    "es": {
        "title": "K5K1 Prog – programa para Quansheng UV-K5 y UV-K1 en Mac",
        "description": "App gratuita para Mac: copia de calibración y configuración, firmware y editor de canales (CSV e .img de CHIRP) para Quansheng UV-K5, UV-K5 V3 y UV-K1.",
        "tagline": "Copia de seguridad, restauración y firmware para radios Quansheng UV-K5 / UV-K5 V3 / UV-K1 en tu Mac.",
        "download": "Descargar para macOS",
        "github": "Código en GitHub",
        "donate": "Donar",
        "brew": "o con Homebrew:",
        "facts": ["Gratis y de código abierto (GPL v3)", "Firmada y notarizada por Apple", "Sin telemetría",
                  "macOS 12 o posterior, Apple Silicon e Intel"],
        "shot_main": "Ventana principal: la radio conectada, en modo normal",
        "shot_editor": "Editor de memoria: los canales de la radio",
        "features_h": "Qué hace",
        "features": [
            ("💾", "Copia y restauración", "Lee y escribe la calibración y la configuración de la radio. Guarda la calibración de fábrica antes de instalar cualquier firmware."),
            ("⚡", "Instalar firmware", "UV-K5 V1 y los nuevos UV-K5 V3 / UV-K1. El archivo y el bootloader se comprueban antes de enviar un solo byte; las combinaciones incorrectas se rechazan."),
            ("📋", "Editar canales", "200 canales, firmware original y Karina. Copia canales entre radios, importa y exporta CSV e .img de CHIRP. Solo se escriben los canales modificados, tras una copia de seguridad, y se verifican leyéndolos."),
            ("📡", "Reconoce tu radio", "La barra de estado muestra qué radio está conectada, en qué modo y con qué firmware. Los botones la siguen, así no se puede iniciar la operación equivocada."),
            ("🔁", "Igual que k5prog-win", "Los mismos botones, registro y bytes en el cable que la herramienta de Windows k5prog-win, más algunas mejoras de seguridad."),
            ("🔄", "Siempre al día", "Se actualiza sola desde las versiones de GitHub. Con Homebrew, brew upgrade instala las nuevas versiones."),
        ],
        "radios_h": "Radios compatibles",
        "th": ["Radio", "Chip", "Bootloader", "Copia y restauración", "Firmware"],
        "yes": "Sí", "refused": "Rechazado",
        "v2_note": "El firmware de V1 deja una V2 con la pantalla en blanco, por eso la app lo rechaza.",
        "radios_note": "La versión del bootloader distingue los modelos: enciende la radio con PTT pulsado y pulsa Write Firmware; el registro la muestra.",
        "safety_h": "Antes de empezar",
        "safety": [
            "Pulsa primero Read Calibration y guarda el archivo: contiene la calibración de potencia y batería de tu radio, y no podrás conseguirla en otro sitio.",
            "La app no distingue un firmware de UV-K1 de uno de UV-K5 V3: elige el archivo de tu modelo.",
            "Instalar firmware es bajo tu propia responsabilidad.",
        ],
        "install_h": "Instalación",
        "install": [
            "Descarga el .dmg, ábrelo y arrastra K5K1 Prog a Aplicaciones.",
            "O con Homebrew: <code>" + BREW + "</code>",
            "Conecta la radio con un cable de programación (conector Kenwood de 2 pines). Aparece como <code>/dev/cu.usbserial-…</code>",
        ],
        "guide": "Guía completa en GitHub →",
        "nav": ["GitHub", "Versiones", "Guía", "Contribuir", "Donar"],
        "footer1": "Gratis y de código abierto (GPL v3). Versión para macOS de k5prog-win de OneOfEleven, basada en k5prog de Jacek Lipkowski SQ5BPF. Estructura de canales según los drivers de CHIRP. Firmware Karina de autumn1rain.",
        "footer2": "Sin relación con Quansheng.",
    },
    "de": {
        "title": "K5K1 Prog – Software für Quansheng UV-K5 und UV-K1 auf dem Mac",
        "description": "Kostenlose Mac-App: Kalibrierung und Konfiguration sichern, Firmware flashen, Kanäle bearbeiten (CHIRP-CSV, .img) für Quansheng UV-K5, UV-K5 V3 und UV-K1.",
        "tagline": "Quansheng UV-K5 / UV-K5 V3 / UV-K1 auf dem Mac sichern, wiederherstellen und flashen.",
        "download": "Für macOS laden",
        "github": "Quellcode auf GitHub",
        "donate": "Spenden",
        "brew": "oder mit Homebrew:",
        "facts": ["Kostenlos und Open Source (GPL v3)", "Von Apple signiert und notarisiert", "Keine Telemetrie",
                  "macOS 12 oder neuer, Apple Silicon und Intel"],
        "shot_main": "Hauptfenster: Funkgerät am Kabel, normaler Modus",
        "shot_editor": "Speichereditor: die Kanäle des Funkgeräts",
        "features_h": "Funktionen",
        "features": [
            ("💾", "Sichern und wiederherstellen", "Kalibrierung und Konfiguration des Funkgeräts lesen und schreiben. Sichern Sie die Werkskalibrierung, bevor Sie etwas flashen."),
            ("⚡", "Firmware flashen", "UV-K5 V1 und die neueren UV-K5 V3 / UV-K1. Firmware-Datei und Bootloader werden geprüft, bevor ein einziges Byte gesendet wird; falsche Kombinationen werden abgelehnt."),
            ("📋", "Kanäle bearbeiten", "200 Kanäle, Original- und Karina-Firmware. Kanäle zwischen Funkgeräten kopieren, CHIRP-CSV und .img importieren und exportieren. Nur geänderte Kanäle werden geschrieben, nach einer Sicherung, und zur Kontrolle zurückgelesen."),
            ("📡", "Erkennt Ihr Funkgerät", "Die Statusleiste zeigt, welches Funkgerät am Kabel hängt, in welchem Modus und mit welcher Firmware. Die Tasten richten sich danach, eine falsche Aktion lässt sich nicht starten."),
            ("🔁", "Eins zu eins wie k5prog-win", "Dieselben Tasten, dasselbe Protokoll und dieselben Bytes auf der Leitung wie das Windows-Tool k5prog-win, plus einige Sicherheitskorrekturen."),
            ("🔄", "Immer aktuell", "Aktualisiert sich selbst aus den GitHub-Releases. Mit Homebrew installiert brew upgrade neue Versionen."),
        ],
        "radios_h": "Unterstützte Funkgeräte",
        "th": ["Funkgerät", "Chip", "Bootloader", "Sichern und wiederherstellen", "Firmware"],
        "yes": "Ja", "refused": "Abgelehnt",
        "v2_note": "V1-Firmware hinterlässt ein V2 mit leerem Display, deshalb lehnt die App sie ab.",
        "radios_note": "Die Bootloader-Version unterscheidet die Modelle: Funkgerät mit gedrückter PTT einschalten und Write Firmware drücken, das Protokoll zeigt sie an.",
        "safety_h": "Bevor Sie anfangen",
        "safety": [
            "Zuerst Read Calibration drücken und die Datei aufheben: Sie enthält die Sendeleistungs- und Akkukalibrierung genau Ihres Geräts, die Sie sonst nirgends bekommen.",
            "Die App kann eine UV-K1-Firmware nicht von einer UV-K5-V3-Firmware unterscheiden: Wählen Sie die Datei für Ihr Modell.",
            "Flashen auf eigene Gefahr.",
        ],
        "install_h": "Installation",
        "install": [
            ".dmg laden, öffnen und K5K1 Prog in den Ordner Programme ziehen.",
            "Oder mit Homebrew: <code>" + BREW + "</code>",
            "Funkgerät mit einem Programmierkabel verbinden (2-poliger Kenwood-Stecker). Es erscheint als <code>/dev/cu.usbserial-…</code>",
        ],
        "guide": "Vollständige Anleitung auf GitHub →",
        "nav": ["GitHub", "Releases", "Anleitung", "Mitmachen", "Spenden"],
        "footer1": "Kostenlos und Open Source (GPL v3). macOS-Portierung von k5prog-win von OneOfEleven, basierend auf k5prog von Jacek Lipkowski SQ5BPF. Kanalaufbau nach den CHIRP-Treibern. Karina-Firmware von autumn1rain.",
        "footer2": "Keine Verbindung zu Quansheng.",
    },
    "zh": {
        "title": "K5K1 Prog – Mac 版泉盛 UV-K5 / UV-K1 写频与刷机软件",
        "description": "免费的 macOS 应用，可备份、恢复和刷写泉盛 UV-K5、UV-K5 V3 和 UV-K1 对讲机，并带有信道编辑器。已签名、已公证、开源。",
        "tagline": "在 Mac 上备份、恢复和刷写泉盛 UV-K5 / UV-K5 V3 / UV-K1 对讲机。",
        "download": "下载 macOS 版",
        "github": "GitHub 源代码",
        "donate": "捐助",
        "brew": "或使用 Homebrew：",
        "facts": ["免费开源（GPL v3）", "经 Apple 签名和公证", "无遥测", "macOS 12 或更高版本，支持 Apple 芯片和 Intel"],
        "shot_main": "主窗口：已连接对讲机，正常模式",
        "shot_editor": "存储编辑器：对讲机的信道",
        "features_h": "功能",
        "features": [
            ("💾", "备份与恢复", "读取和写入对讲机的校准数据和配置。刷机之前，先保存好出厂校准。"),
            ("⚡", "刷写固件", "支持 UV-K5 V1 以及较新的 UV-K5 V3 / UV-K1。发送任何数据之前都会检查固件文件和 bootloader，错误的组合会被拒绝。"),
            ("📋", "编辑信道", "200 个信道，支持原厂固件和 Karina 固件。可在对讲机之间复制信道，导入和导出 CHIRP CSV 及 .img。只写入改动过的信道，写入前先备份，写入后回读校验。"),
            ("📡", "识别你的对讲机", "状态栏显示数据线上连接的是哪台对讲机、处于什么模式、运行什么固件。按钮随之启用或禁用，不会误操作。"),
            ("🔁", "与 k5prog-win 完全一致", "按钮、日志和线路上的数据与 Windows 工具 k5prog-win 相同，另外加入了一些安全改进。"),
            ("🔄", "自动更新", "从 GitHub 发布版自动更新。使用 Homebrew 时，brew upgrade 会安装新版本。"),
        ],
        "radios_h": "支持的对讲机",
        "th": ["对讲机", "芯片", "Bootloader", "备份与恢复", "固件"],
        "yes": "支持", "refused": "拒绝",
        "v2_note": "V1 固件会让 V2 黑屏，所以本应用拒绝刷写。",
        "radios_note": "用 bootloader 版本区分型号：按住 PTT 开机，然后点 Write Firmware，日志中会显示版本。",
        "safety_h": "开始之前",
        "safety": [
            "先点 Read Calibration 并保存文件：里面是你这台对讲机自己的发射功率和电池校准，别处无法获得。",
            "本应用无法区分 UV-K1 固件和 UV-K5 V3 固件：请选择对应你型号的文件。",
            "刷机风险自负。",
        ],
        "install_h": "安装",
        "install": [
            "下载 .dmg，打开后把 K5K1 Prog 拖到“应用程序”文件夹。",
            "或使用 Homebrew：<code>" + BREW + "</code>",
            "用写频线（两针 Kenwood 接头）连接对讲机，端口显示为 <code>/dev/cu.usbserial-…</code>",
        ],
        "guide": "GitHub 上的完整指南 →",
        "nav": ["GitHub", "发布版", "指南", "参与贡献", "捐助"],
        "footer1": "免费开源（GPL v3）。k5prog-win（OneOfEleven）的 macOS 移植版，基于 Jacek Lipkowski SQ5BPF 的 k5prog。信道结构参考 CHIRP 驱动。Karina 固件作者为 autumn1rain。",
        "footer2": "与泉盛公司无关。",
    },
}

# per language: Open Graph locale, the README of that language
LOCALE = {"en": "en_US", "ru": "ru_RU", "es": "es_ES", "de": "de_DE", "zh": "zh_CN"}
README = {"en": "README.md", "ru": "README_RU.md", "es": "README_ES.md", "de": "README_DE.md", "zh": "README_ZH.md"}

# questions people search for; shown on the page and as FAQPage structured data
FAQ = {
    "en": ("Questions and answers", [
        ("Can I program a Quansheng UV-K5 on a Mac?",
         "Yes. K5K1 Prog runs natively on macOS 12 or newer, on Apple Silicon and Intel, without Windows or a virtual machine. It backs up and restores calibration and configuration, flashes firmware and edits channels."),
        ("Which radios are supported?",
         "UV-K5, UV-K5(8), UV-K6 and UV-5R Plus with the DP32G030 chip (V1), and the newer UV-K5 V3 and UV-K1 (PY32F071). On the UV-K5 V2 / UV-K6 V2 backup and restore work; firmware upload is refused."),
        ("Do I need a driver for the programming cable?",
         "Usually not: the common CH340 cables work on current macOS without extra software. The cable shows up as /dev/cu.usbserial-…"),
        ("Is it an alternative to CHIRP?",
         "For channels, yes: the Memory Editor edits the 200 channels of stock and Karina firmware and imports and exports CHIRP CSV and .img files. The radio's menu settings are not edited."),
        ("Which firmware can I flash?",
         "Any firmware file for your model, .bin or .packed.bin: stock Quansheng, Karina, F4HWN and others. Before sending anything the app checks that the file fits the radio's bootloader."),
        ("Is it free and safe?",
         "Free and open source under GPL v3. The app is signed and notarized by Apple, has no telemetry and only contacts GitHub to check for updates."),
    ]),
    "ru": ("Вопросы и ответы", [
        ("Можно ли программировать Quansheng UV-K5 на Mac?",
         "Да. K5K1 Prog работает на macOS 12 и новее, на Apple Silicon и Intel, без Windows и виртуальных машин. Программа делает резервную копию и восстанавливает калибровку и конфигурацию, прошивает рацию и редактирует каналы."),
        ("Какие рации поддерживаются?",
         "UV-K5, UV-K5(8), UV-K6 и UV-5R Plus на чипе DP32G030 (V1), а также новые UV-K5 V3 и UV-K1 (PY32F071). На UV-K5 V2 / UV-K6 V2 работают бэкап и восстановление, прошивка отклоняется."),
        ("Нужен ли драйвер для кабеля?",
         "Обычно нет: распространённые кабели на CH340 работают в современной macOS без дополнительных программ. Кабель появляется как /dev/cu.usbserial-…"),
        ("Это замена CHIRP?",
         "Для каналов да: редактор памяти правит 200 каналов стоковой прошивки и Карины, импортирует и экспортирует CSV и .img от CHIRP. Настройки меню рации не редактируются."),
        ("Какую прошивку можно залить?",
         "Любой файл прошивки для вашей модели, .bin или .packed.bin: стоковую Quansheng, Карину, F4HWN и другие. Перед отправкой программа проверяет, подходит ли файл к загрузчику рации."),
        ("Это бесплатно и безопасно?",
         "Бесплатно, открытый код под GPL v3. Приложение подписано и нотаризовано Apple, без телеметрии, в сеть ходит только на GitHub за обновлениями."),
    ]),
    "es": ("Preguntas frecuentes", [
        ("¿Se puede programar una Quansheng UV-K5 en un Mac?",
         "Sí. K5K1 Prog funciona de forma nativa en macOS 12 o posterior, en Apple Silicon e Intel, sin Windows ni máquinas virtuales. Hace copia de seguridad y restaura la calibración y la configuración, instala firmware y edita canales."),
        ("¿Qué radios son compatibles?",
         "UV-K5, UV-K5(8), UV-K6 y UV-5R Plus con chip DP32G030 (V1), y las nuevas UV-K5 V3 y UV-K1 (PY32F071). En la UV-K5 V2 / UV-K6 V2 funcionan la copia y la restauración; la instalación de firmware se rechaza."),
        ("¿Necesito un driver para el cable de programación?",
         "Normalmente no: los cables CH340 habituales funcionan en macOS actual sin software adicional. El cable aparece como /dev/cu.usbserial-…"),
        ("¿Es una alternativa a CHIRP?",
         "Para los canales, sí: el editor de memoria edita los 200 canales del firmware original y de Karina, e importa y exporta archivos CSV e .img de CHIRP. Los ajustes del menú de la radio no se editan."),
        ("¿Qué firmware puedo instalar?",
         "Cualquier archivo de firmware para tu modelo, .bin o .packed.bin: el original de Quansheng, Karina, F4HWN y otros. Antes de enviar nada, la app comprueba que el archivo corresponde al bootloader de la radio."),
        ("¿Es gratis y seguro?",
         "Gratis y de código abierto con licencia GPL v3. La app está firmada y notarizada por Apple, no tiene telemetría y solo se conecta a GitHub para buscar actualizaciones."),
    ]),
    "de": ("Häufige Fragen", [
        ("Kann ich ein Quansheng UV-K5 am Mac programmieren?",
         "Ja. K5K1 Prog läuft nativ unter macOS 12 oder neuer, auf Apple Silicon und Intel, ohne Windows und ohne virtuelle Maschine. Es sichert und schreibt Kalibrierung und Konfiguration, flasht Firmware und bearbeitet Kanäle."),
        ("Welche Funkgeräte werden unterstützt?",
         "UV-K5, UV-K5(8), UV-K6 und UV-5R Plus mit dem Chip DP32G030 (V1) sowie die neueren UV-K5 V3 und UV-K1 (PY32F071). Beim UV-K5 V2 / UV-K6 V2 funktionieren Sichern und Wiederherstellen; Firmware-Uploads werden abgelehnt."),
        ("Brauche ich einen Treiber für das Programmierkabel?",
         "Meist nicht: Die üblichen CH340-Kabel funktionieren unter aktuellem macOS ohne Zusatzsoftware. Das Kabel erscheint als /dev/cu.usbserial-…"),
        ("Ist es eine Alternative zu CHIRP?",
         "Für Kanäle ja: Der Speichereditor bearbeitet die 200 Kanäle der Original- und der Karina-Firmware und importiert und exportiert CSV- und .img-Dateien von CHIRP. Die Menüeinstellungen des Funkgeräts werden nicht bearbeitet."),
        ("Welche Firmware kann ich flashen?",
         "Jede Firmware-Datei für Ihr Modell, .bin oder .packed.bin: Original-Quansheng, Karina, F4HWN und andere. Vor dem Senden prüft die App, ob die Datei zum Bootloader des Funkgeräts passt."),
        ("Ist es kostenlos und sicher?",
         "Kostenlos und Open Source unter GPL v3. Die App ist von Apple signiert und notarisiert, hat keine Telemetrie und verbindet sich nur mit GitHub, um nach Updates zu suchen."),
    ]),
    "zh": ("常见问题", [
        ("能在 Mac 上给泉盛 UV-K5 写频吗？",
         "可以。K5K1 Prog 原生运行在 macOS 12 或更高版本上，支持 Apple 芯片和 Intel，无需 Windows 或虚拟机。它可以备份和恢复校准与配置、刷写固件和编辑信道。"),
        ("支持哪些对讲机？",
         "使用 DP32G030 芯片的 UV-K5、UV-K5(8)、UV-K6 和 UV-5R Plus（V1），以及较新的 UV-K5 V3 和 UV-K1（PY32F071）。UV-K5 V2 / UV-K6 V2 可以备份和恢复，但会拒绝刷写固件。"),
        ("写频线需要装驱动吗？",
         "通常不需要：常见的 CH340 写频线在新版 macOS 上无需额外软件即可使用，端口显示为 /dev/cu.usbserial-…"),
        ("可以代替 CHIRP 吗？",
         "编辑信道可以：存储编辑器能编辑原厂固件和 Karina 固件的 200 个信道，并导入导出 CHIRP 的 CSV 和 .img 文件。对讲机的菜单设置不在编辑范围内。"),
        ("可以刷哪些固件？",
         "适用于你型号的任何固件文件，.bin 或 .packed.bin 均可：泉盛原厂、Karina、F4HWN 等。发送前，应用会先检查文件是否与对讲机的 bootloader 匹配。"),
        ("免费吗？安全吗？",
         "免费开源，采用 GPL v3 许可。应用经 Apple 签名和公证，没有遥测，只会连接 GitHub 检查更新。"),
    ]),
}


def app_version():
    import re
    s = (ROOT / "Sources" / "K5Core" / "Constants.swift").read_text()
    return re.search(r'static let version = "([^"]+)"', s).group(1)


def json_ld(code, folder, t):
    import json
    app = {
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": "K5K1 Prog",
        "url": SITE + folder,
        "description": t["description"],
        "applicationCategory": "UtilitiesApplication",
        "operatingSystem": "macOS 12 or later",
        "softwareVersion": app_version(),
        "downloadUrl": LATEST,
        "installUrl": LATEST,
        "screenshot": [SITE + "assets/main-window.png", SITE + "assets/memory-editor.png"],
        "image": SITE + "assets/og-card.png",
        "license": "https://www.gnu.org/licenses/gpl-3.0.html",
        "isAccessibleForFree": True,
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
        "author": {"@type": "Person", "name": "Evgeny Ruban", "url": "https://github.com/ERuban"},
        "codeRepository": REPO,
        "inLanguage": dict((c, hl) for c, _, _, hl in LANGS)[code],
    }
    faq = {
        "@context": "https://schema.org",
        "@type": "FAQPage",
        "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}}
                       for q, a in FAQ[code][1]],
    }
    dump = lambda o: json.dumps(o, ensure_ascii=False, indent=2).replace("</", "<\\/")
    return (f'  <script type="application/ld+json">\n{dump(app)}\n  </script>\n'
            f'  <script type="application/ld+json">\n{dump(faq)}\n  </script>')


APPLE = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16.37 12.6c-.02-2.14 1.75-3.17 1.83-3.22-1-1.45-2.55-1.65-3.1-1.68-1.32-.13-2.58.78-3.25.78-.67 0-1.7-.76-2.8-.74-1.44.02-2.77.84-3.51 2.13-1.5 2.6-.38 6.44 1.08 8.55.71 1.03 1.56 2.19 2.67 2.15 1.07-.04 1.48-.69 2.77-.69 1.3 0 1.66.69 2.8.67 1.16-.02 1.89-1.05 2.6-2.09.82-1.2 1.15-2.36 1.17-2.42-.03-.01-2.24-.86-2.26-3.42zM14.25 6.3c.59-.72.99-1.71.88-2.7-.85.03-1.88.57-2.49 1.28-.55.63-1.03 1.64-.9 2.61.95.07 1.92-.48 2.51-1.19z"/></svg>'
GH = '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>'


def e(s):
    return html.escape(s, quote=True)


def page(code, folder, t):
    up = "../" if folder else ""
    a = up + "assets/"
    langs = []
    for c, f, name, _ in LANGS:
        if c == code:
            langs.append(f'<span aria-current="page">{name}</span>')
        else:
            langs.append(f'<a href="{up}{f}" hreflang="{c}" lang="{c}">{name}</a>')
    alternates = "\n".join(f'  <link rel="alternate" hreflang="{hl}" href="{SITE}{f}">' for c, f, _, hl in LANGS)
    features = "\n".join(
        f'      <div class="card"><span class="ico">{ico}</span><h3>{e(h)}</h3><p>{e(p)}</p></div>'
        for ico, h, p in t["features"])
    th = "".join(f"<th>{e(x)}</th>" for x in t["th"])
    yes, no = e(t["yes"]), e(t["refused"])
    rows = [
        ("UV-K5, UV-K5(8), UV-K6, UV-5R&nbsp;Plus (V1)", "DP32G030", "2.x – 4.x", f'<td class="yes">{yes}</td>', f'<td class="yes">{yes}</td>'),
        ("UV-K5 V3, UV-K1", "PY32F071", "7.xx", f'<td class="yes">{yes}</td>', f'<td class="yes">{yes}</td>'),
        ("UV-K5 V2, UV-K6 V2", "PY32F030", "1.xx", f'<td class="yes">{yes}</td>', f'<td class="no">{no}*</td>'),
    ]
    trs = "\n".join(f"          <tr><td>{r.replace('-', '&#8209;')}</td><td>{c}</td><td>{b}</td>{x}{y}</tr>" for r, c, b, x, y in rows)
    safety = "\n".join(f"        <li>{e(s)}</li>" for s in t["safety"])
    install = "\n".join(f"      <li>{s}</li>" for s in t["install"])   # may hold <code>
    facts = "\n".join(f"      <li>{e(f)}</li>" for f in t["facts"])
    readme = REPO + "/blob/main/" + README[code]
    nav_links = [REPO, REPO + "/releases", readme, REPO + "/blob/main/CONTRIBUTING.md", DONATE]
    faq_h, faq_items = FAQ[code]
    faq = "\n".join(f'      <div class="qa"><h3>{e(q)}</h3><p>{e(ans)}</p></div>' for q, ans in faq_items)
    og_alt = "\n".join(f'  <meta property="og:locale:alternate" content="{LOCALE[c]}">' for c, _, _, _ in LANGS if c != code)
    nav = " ".join(f'<a href="{u}">{e(n)}</a>' for u, n in zip(nav_links, t["nav"]))
    return f"""<!doctype html>
<html lang="{dict((c, hl) for c, _, _, hl in LANGS)[code]}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{e(t["title"])}</title>
  <meta name="description" content="{e(t["description"])}">
  <link rel="canonical" href="{SITE}{folder}">
{alternates}
  <link rel="alternate" hreflang="x-default" href="{SITE}">
  <meta name="robots" content="index, follow, max-image-preview:large">
  <meta name="author" content="Evgeny Ruban">
  <meta name="theme-color" content="#1e2850">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="K5K1 Prog">
  <meta property="og:locale" content="{LOCALE[code]}">
{og_alt}
  <meta property="og:title" content="{e(t["title"])}">
  <meta property="og:description" content="{e(t["description"])}">
  <meta property="og:url" content="{SITE}{folder}">
  <meta property="og:image" content="{SITE}assets/og-card.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="{e(t["tagline"])}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="{e(t["title"])}">
  <meta name="twitter:description" content="{e(t["description"])}">
  <meta name="twitter:image" content="{SITE}assets/og-card.png">
  <link rel="icon" href="{a}logo.svg" type="image/svg+xml">
  <link rel="icon" href="{a}favicon-32.png" type="image/png" sizes="32x32">
  <link rel="apple-touch-icon" href="{a}apple-touch-icon.png">
  <link rel="stylesheet" href="{a}style.css">
{json_ld(code, folder, t)}
</head>
<body>
  <div class="wrap">
    <header class="top">
      <a class="brand" href="{up}{folder}"><img src="{a}logo.svg" alt="">K5K1 Prog</a>
      <nav class="langs" aria-label="Language">{" ".join(langs)}</nav>
    </header>

    <div class="hero">
      <img class="logo" src="{a}logo.svg" alt="K5K1 Prog">
      <h1>K5K1 Prog</h1>
      <p class="tagline">{e(t["tagline"])}</p>
      <div class="actions">
        <a class="btn primary" href="{LATEST}">{APPLE}{e(t["download"])}</a>
        <a class="btn" href="{REPO}">{GH}{e(t["github"])}</a>
        <a class="btn" href="{DONATE}">♥ {e(t["donate"])}</a>
      </div>
      <p class="brew">{e(t["brew"])} <code>{BREW}</code></p>
      <ul class="facts">
{facts}
      </ul>
    </div>

    <div class="shots">
      <figure><img src="{a}main-window.png" width="1228" height="842" alt="{e(t["shot_main"])}"><figcaption>{e(t["shot_main"])}</figcaption></figure>
      <figure><img src="{a}memory-editor.png" width="1278" height="797" alt="{e(t["shot_editor"])}" loading="lazy"><figcaption>{e(t["shot_editor"])}</figcaption></figure>
    </div>

    <section id="features">
      <h2>{e(t["features_h"])}</h2>
      <div class="features">
{features}
      </div>
    </section>

    <section id="radios">
      <h2>{e(t["radios_h"])}</h2>
      <div class="table-wrap">
        <table>
          <thead><tr>{th}</tr></thead>
          <tbody>
{trs}
          </tbody>
        </table>
      </div>
      <p class="note">* {e(t["v2_note"])} {e(t["radios_note"])}</p>
    </section>

    <section id="safety">
      <h2>{e(t["safety_h"])}</h2>
      <div class="warn">
        <ul>
{safety}
        </ul>
      </div>
    </section>

    <section id="install">
      <h2>{e(t["install_h"])}</h2>
      <ol class="steps">
{install}
      </ol>
      <p class="more"><a href="{readme}">{e(t["guide"])}</a></p>
    </section>

    <section id="faq">
      <h2>{e(faq_h)}</h2>
      <div class="faq">
{faq}
      </div>
    </section>

    <footer>
      <nav>{nav}</nav>
      <p>{e(t["footer1"])}</p>
      <p>{e(t["footer2"])} © 2026 Evgeny Ruban.</p>
    </footer>
  </div>
</body>
</html>
"""


def sitemap():
    import datetime
    today = datetime.date.today().isoformat()
    alts = "\n".join(f'    <xhtml:link rel="alternate" hreflang="{hl}" href="{SITE}{f}"/>' for _, f, _, hl in LANGS)
    alts += f'\n    <xhtml:link rel="alternate" hreflang="x-default" href="{SITE}"/>'
    urls = "\n".join(f"  <url>\n    <loc>{SITE}{f}</loc>\n    <lastmod>{today}</lastmod>\n{alts}\n  </url>"
                     for _, f, _, _ in LANGS)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" '
            'xmlns:xhtml="http://www.w3.org/1999/xhtml">\n' + urls + "\n</urlset>\n")


def not_found():
    # served for any missing path, so all links are absolute
    base = "/k5k1prog-mac/"
    links = " · ".join(f'<a href="{base}{f}">{name}</a>' for _, f, name, _ in LANGS)
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Page not found – K5K1 Prog</title>
  <meta name="robots" content="noindex">
  <link rel="icon" href="{base}assets/logo.svg" type="image/svg+xml">
  <link rel="stylesheet" href="{base}assets/style.css">
</head>
<body>
  <div class="wrap">
    <div class="hero">
      <a href="{base}"><img class="logo" src="{base}assets/logo.svg" alt="K5K1 Prog"></a>
      <h1>Page not found</h1>
      <p class="tagline">{links}</p>
      <div class="actions"><a class="btn primary" href="{LATEST}">Download K5K1 Prog</a></div>
    </div>
  </div>
</body>
</html>
"""


def main():
    for code, folder, _, _ in LANGS:
        out = DOCS / folder / "index.html"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(page(code, folder, T[code]), encoding="utf-8")
        print("wrote", out.relative_to(ROOT))
    (DOCS / "sitemap.xml").write_text(sitemap(), encoding="utf-8")
    (DOCS / "404.html").write_text(not_found(), encoding="utf-8")
    print("wrote docs/sitemap.xml, docs/404.html")
    # every language must have every text
    keys = set(T["en"])
    for code in T:
        missing = keys - set(T[code])
        assert not missing, f"{code}: missing {missing}"
        assert len(T[code]["features"]) == len(T["en"]["features"]), code
        assert len(FAQ[code][1]) == len(FAQ["en"][1]), code


if __name__ == "__main__":
    main()
