<p align="center">
    <a href="https://github.com/ERuban/k5k1prog-mac/releases/latest"><img alt="K5K1 Prog"
         src="Resources/logo.svg" width="160"
    /></a>
</p>

<h1 align="center">K5K1 Prog</h1>

<p align="center">Copias de seguridad, restauración y grabación de firmware para radios Quansheng UV-K5 / UV-K5 V3 / UV-K1 en macOS</p>

<p align="center"><a href="https://eruban.github.io/k5k1prog-mac/">eruban.github.io/k5k1prog-mac</a></p>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README_RU.md">Русский</a> |
  <a href="README_DE.md">Deutsch</a> |
  <a href="README_ZH.md">中文</a>
</p>

*Esta es una traducción. Si algo no coincide, la versión válida es la inglesa: [README.md](README.md).*

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

Adaptación para macOS de **k5prog-win v0.1.26** (OneOfEleven), con mejoras.

Una app nativa de macOS para hacer copias de seguridad, restaurar y grabar el firmware de radios
**Quansheng UV-K5 / UV-K5(8) / UV-K6 / UV-5R Plus** (V1, DP32G030) y **UV-K5 V3 / UV-K1** (PY32F071)
mediante un cable de programación.

Reproduce fielmente el comportamiento de [k5prog-win](https://github.com/OneOfEleven/k5prog-win)
(los mismos botones, el mismo registro, los mismos bytes por el cable) y añade la carga de firmware
en los modelos más recientes UV-K5 V3 y UV-K1, algo que k5prog-win no puede hacer, un editor de
canales y algunas correcciones de seguridad
(consulta [Diferencias con k5prog-win](#diferencias-con-k5prog-win)).

## Funciones

- **Leer / escribir la calibración** (512 bytes en `0x1E00`). Haz una copia de la calibración de
  fábrica de tu radio antes de grabar nada.
- **Leer / escribir la configuración** (canales y ajustes, `0x0000–0x1CFF`).
- **Grabar firmware**, en `.bin` sin procesar o en `.packed.bin` del fabricante. El tipo de radio se
  detecta a partir de la propia imagen y se comprueba con el bootloader antes de escribir nada.
- **Memory Editor** para los 200 canales de la radio, con firmware de fábrica y Karina, en UV-K5 V1 y
  UV-K1 / UV-K5 V3 (consulta [Edición de canales](#edición-de-canales)): edita, copia y arrastra
  canales entre dos radios, importa / exporta CSV de CHIRP y `.img` de CHIRP, y cambia el texto de
  encendido en el firmware de fábrica. Solo escribe los canales modificados, después de hacer una copia
  de seguridad, y los vuelve a leer para verificarlos. Los ajustes y la calibración nunca se tocan.
- **Estado de la radio** en la ventana principal: qué radio está conectada al cable, en qué modo y su
  cadena de firmware, comprobado en segundo plano cada 2 segundos.
- **Ajustes** (**K5K1 Prog → Settings…**): apariencia clara / oscura y la carpeta para las copias de
  seguridad del editor.
- App universal (Apple Silicon e Intel), macOS 12 o posterior. No necesita drivers ni software
  adicional para los cables CH340.
- Los ajustes (puerto, velocidad, nivel de detalle del registro, posición de la ventana, apariencia)
  se guardan como es habitual en macOS, en `~/Library/Preferences/io.github.eruban.k5k1prog.plist`.
  No se escribe nada junto a la app.

## Radios compatibles

| Radio | MCU | Bootloader | Calibración / configuración | Firmware |
|---|---|---|---|---|
| UV-K5, UV-K5(8), UV-K6, UV-5R Plus ("V1") | DP32G030 | 2.x – 4.x | ✅ | ✅ (protocolo de k5prog-win) |
| UV-K5 V3, UV-K1 | PY32F071 | 7.xx (7.00.07 o posterior) | ✅ | ✅ |
| UV-K5 V2, UV-K6 V2 | PY32F030 | 1.xx | ✅ | ❌ se rechaza |

El modelo está impreso debajo de la batería (V2, V3), pero la señal fiable es la versión del
bootloader: pon la radio en modo bootloader y pulsa **Write Firmware**; el registro muestra
`Bootloader version '…'`.
Las radios UV-5R Plus Type-C con bootloader 5.x usan un protocolo de bootloader cifrado y no son compatibles.

Probado en hardware real: una UV-K5 V1 (bootloader 2.00.06) y una UV-K1 (bootloader 7.03.01). Las dos
se grabaron con K5K1 Prog, se leyeron la calibración y la configuración de ambas, y la calibración se
escribió en la UV-K1 y se verificó volviendo a leerla.

> [!WARNING]
> El firmware de las radios V1, V2 y V3/K1 **no es intercambiable**. K5K1 Prog lo comprueba antes de
> enviar nada: se rechazan una imagen V1 en un bootloader 7.xx, una imagen V3/K1 en cualquier otro
> bootloader y cualquier imagen en un bootloader V2 (1.xx).
>
> **No puede distinguir una imagen de UV-K1 de una de UV-K5 V3** (mismo chip, mismo bootloader, y el
> bootloader no informa del modelo). Elige el archivo de tu modelo. Si grabas el que no es, la radio
> puede funcionar mal o no arrancar, pero el bootloader no se sobrescribe: enciende la radio
> manteniendo pulsado **PTT** y graba el archivo correcto.
>
> Grabar firmware es bajo tu propia responsabilidad.

## Instalación

Con [Homebrew](https://brew.sh):

```sh
brew install --cask eruban/tap/k5k1-prog
```

`brew upgrade` instala las versiones nuevas (el cask de [ERuban/homebrew-tap](https://github.com/ERuban/homebrew-tap)
se actualiza solo con cada versión).

O descarga `K5K1-Prog-<version>.dmg` desde [Releases](../../releases), ábrelo y arrastra **K5K1 Prog**
a **Aplicaciones**. La app está firmada con un Developer ID y notarizada por Apple, así que se abre
sin avisos. También se adjunta un `.zip` con la misma app.

A partir de la versión 1.1.0, la app se actualiza sola: busca una versión nueva en GitHub una vez al
día (y al elegir **K5K1 Prog → Check for Updates…**), muestra las novedades y la instala con un clic
([Sparkle](https://sparkle-project.org); las actualizaciones van firmadas con EdDSA). La versión 1.0.0
no tiene actualizador, así que instala la 1.1.0 a mano una vez.

O compílala desde el código fuente (necesitas las Xcode Command Line Tools y Swift 5.9 o posterior):

```sh
git clone <this repository> k5k1prog-mac && cd k5k1prog-mac
./scripts/build_app.sh        # -> "K5K1 Prog.app" in the repository root (ad-hoc signed)
open "K5K1 Prog.app"
```

## Uso

Conecta la radio con un cable de programación (conector Kenwood de 2 pines). El cable aparece como
`/dev/cu.usbserial-…` (o `/dev/cu.wchusbserial…` si tienes instalado el driver de WCH). Selecciónalo en **Serial port** y deja
**38400 - k5/k6**.

### Primero, haz una copia de seguridad

1. Enciende la radio de forma normal.
2. Pulsa **Read Calibration** y guarda el archivo en un lugar seguro. Contiene la calibración de
   potencia de TX y de batería propia de tu radio, y no podrás recuperarla de ningún otro sitio.
3. Pulsa **Read Configuration** y guarda el archivo.

La calibración y la configuración se vuelven a escribir de la misma forma (**Write Calibration**,
**Write Configuration**), con la radio encendida de forma normal.

### Grabar firmware

1. Apaga la radio, mantén pulsado **PTT** y enciéndela. La pantalla se queda en blanco: la radio está
   en modo bootloader.
2. Pulsa **Write Firmware** y elige el `.bin` (o `.packed.bin`) de tu modelo.
3. Revisa el registro: `Bootloader version '…'` empieza por `2`–`4` en las radios V1 y por `7` en las V3/K1.
4. Espera a que aparezca `write FLASH complete`. La radio se reinicia con el firmware nuevo.

Después, sigue las instrucciones de tu firmware (reinicio de la memoria, qué archivos de calibración
cargar, etc.). Algunos paquetes de firmware incluyen un archivo de calibración completo que sustituye
los valores de fábrica de potencia de TX y de batería. Al terminar, haz una nueva lectura con
**Read Calibration** y compárala con tu copia de seguridad.

### Edición de canales

1. Enciende la radio de forma normal, selecciona su puerto y pulsa **Memory Editor…** (⌘E). Los canales
   se leen de la radio; la ventana siempre muestra lo que hay en la radio en ese momento.
2. **Firmware** y **Radio** se eligen a partir de la cadena de firmware de la radio: el firmware de
   fábrica por su número de versión y Karina por su nombre en clave. La cadena de Karina es la misma en
   la UV-K5 V1 y en la UV-K1, así que el editor pregunta una sola vez de qué radio se trata. Un firmware
   que no conoce se abre en modo de solo lectura hasta que elijas. Si eliges algo que contradice la
   cadena de firmware, el editor lo indica en rojo: los valores de los canales (modo, paso, scrambler)
   se leerían y escribirían mal.
3. Haz doble clic en una celda para editarla. Selecciona varios canales para cambiarlos a la vez; usa
   **Set Power** y **Delete**, y ⌘Z para deshacer.
4. **Write to Radio…** muestra la lista de cambios, guarda una copia de seguridad de la configuración de
   la radio (`~/Documents/K5K1 Prog Backups/`, consulta Settings), comprueba que la radio no ha cambiado
   desde que se leyó, escribe solo los bloques modificados, los vuelve a leer y los compara. Para
   restaurar una copia de seguridad, usa **Write Configuration**.

Para copiar canales a otra radio, abre un editor para cada radio (uno por puerto) y arrastra los
canales de uno a otro o usa Copy / Paste, o bien usa **Export Channels…** en uno e **Import Channels…**
en el otro. Los valores que el otro firmware no tiene (USB en el firmware de fábrica, la lista de
scramblers de Karina, los pasos finos) se convierten y se muestran en una lista. Al importar se
conservan los números de canal; los ajustes del archivo se ignoran. Formatos: CSV de CHIRP, `.img` de
CHIRP (de fábrica o Karina, UV-K5 / UV-K1) y un `.bin` de configuración obtenido con Read Configuration
(un `.bin` no indica de qué radio procede: elígela en el diálogo de importación).

El editor comprueba la radio cada 2 segundos mientras su ventana está activa. Si se conecta otra radio,
lee esa (o, si hay cambios sin escribir, lo avisa y no escribe en ella).

Solo se edita la memoria de canales (200 canales, la estructura de fábrica que comparten el firmware de
fábrica, Karina y F4HWN). No se admiten otros firmwares, más de 200 canales (F4HWN en la UV-K1) ni los
ajustes de la radio.

## Diferencias con k5prog-win

Todas van en la dirección de una mayor seguridad:

1. **Carga de firmware en UV-K5 V3 / UV-K1** (PY32F071, bootloader 7.xx); consulta más abajo.
2. Nunca se envía un archivo de firmware V1 (DP32G030) a un bootloader 7.xx, y se rechaza la carga de
   firmware en una UV-K5 V2 / K6 V2 (bootloader 1.xx, PY32F030): el firmware V1 deja esa radio con la
   pantalla en blanco.
3. **Archivo de configuración cuyo tamaño no es múltiplo de 128 bytes.** k5prog-win lee más allá del
   final de su búfer y escribe memoria aleatoria en la radio. Aquí, el resto del último bloque conserva
   los bytes propios de la radio (que se leen antes). Los archivos normales (7424 / 8192 / 512 bytes) no
   se ven afectados.
4. La lista de puertos muestra `/dev/cu.*` (el equivalente en macOS de la lista de puertos COM). La
   barra de estado no tiene el indicador "RX BREAK".
5. La ventana principal no consulta la radio para volcar sus datos en el registro al arrancar ni al
   cambiar de puerto ("Fetching radio details .. radio not detected"). En su lugar, el estado de la
   radio se muestra en la barra de estado, y los botones se adaptan a él: la configuración, la
   calibración y el editor necesitan la radio en modo normal, Write Firmware la necesita en modo de
   actualización de firmware, y sin radio no se activa nada. Las líneas largas del registro se ajustan
   al ancho de la ventana.
6. **Los ajustes** se guardan en las preferencias de macOS (`io.github.eruban.k5k1prog`), no en un
   archivo ini junto a la app: en un Mac esa carpeta es `/Applications`. Las claves son las de
   `k5prog_win.ini` (`MainForm.Top`, `GUI.Verbose`, `SerialPort.Name`, …). Las versiones 1.0 / 1.1
   usaban `K5K1Prog.ini`; se importa una vez y se elimina. Los diálogos de archivo se abren en `~/Documents`.

Todo lo demás coincide con el original: los botones, el orden de las operaciones, los tiempos de espera
(hello 2×1 s, lectura 3 s, escritura 2 s, grabación 3 s), los reintentos, las comprobaciones, cada línea
del registro y cada texto de los cuadros de mensaje, el protocolo (tramas, tablas XOR, CRC, id de sesión
`6A 39 57 64`, bloques de configuración de 128 bytes, bloques de flash de 256 bytes, la corrección de la
versión del bootloader `4.00.07` → `*.00.07`), las claves de configuración y Esc para cancelar una
transferencia.

## Carga de firmware en UV-K5 V3 / UV-K1

**Write Firmware** detecta el tipo de archivo por su tabla de vectores: una imagen PY32F071 tiene el
vector de reset en `0x080xxxxx`, y una imagen DP32G030, en `0x0000xxxx`. En ambos casos se aceptan
archivos `.bin` sin procesar y `.packed.bin` del fabricante. Los archivos V1 siguen el mismo camino
que en k5prog-win, sin cambios.

Protocolo PY32 (como en el serialtool de muzkr):

- el bootloader debe empezar por `7` y ser `7.00.07` o posterior; si no, no se envía nada;
- 5 intervalos válidos seguidos entre balizas `0x0518` (5–1000 ms) y, después, `0x0530` con los 4
  primeros caracteres de la versión del bootloader, una vez por baliza, 3 veces;
- páginas `0x0519`: marca de tiempo LE32, página LE16, número de páginas LE16, 4 × `00`, 256 bytes de
  datos (la última página se rellena con `00`); respuesta `0x051A` marca de tiempo / página / error;
  3 s por página, hasta 3 reenvíos de una página tras un error o si no llega respuesta;
- tamaño máximo de la imagen `0x1D800` (área de aplicación en `0x08002800`, 118 KB);
- sin comando de reinicio al final: el propio bootloader arranca el firmware nuevo.

Las combinaciones incorrectas se rechazan antes de escribir nada: un archivo V1 en un bootloader 7.xx,
un archivo V3/K1 en cualquier otro bootloader, cualquier archivo en un bootloader V2 (1.xx), un
bootloader anterior a 7.00.07, una imagen demasiado grande o una radio que no está en modo bootloader.

## Desarrollo

Las contribuciones son bienvenidas: consulta [CONTRIBUTING.md](CONTRIBUTING.md) (en inglés), y
[AGENTS.md](AGENTS.md) para agentes de programación con IA (en inglés).

```sh
swift test                    # 76 tests: simulator, protocol, reference comparisons, channels
swift run k5emu --mode boot --bl-version 7.03.01 --link /tmp/k5com   # simulated K1 bootloader
```

- `Sources/K5Core`: protocolo, manejo de archivos de firmware y la lógica de k5prog-win; `Channels.swift`
  y `ChannelTransfer.swift` para el Memory Editor (estructura de canales, perfiles, CSV / `.img`).
- `Sources/K5K1Prog`: la app AppKit.
- `docs/`: el sitio web (GitHub Pages, cinco idiomas), generado por `scripts/build_site.py`; edita allí
  los textos y ejecuta el script.
- `scripts/chirp-golden/golden.py`: genera las referencias de prueba de los canales con los drivers
  reales de CHIRP (imágenes sintéticas, sin datos personales). Solo hace falta cuando cambian los perfiles.
- `Sources/K5Sim`, `Sources/k5emu`: un simulador de UV-K5 sobre un pseudoterminal. Modo de usuario,
  bootloader V1 y `--bl-version 7.xx.xx` para el bootloader PY32. Inyección de fallos para páginas
  rechazadas o perdidas en `RadioSim.Options`.
- Las pruebas no necesitan archivos de firmware: las cargas de firmware (V1 y PY32, sin procesar y
  `.packed`) usan imágenes sintéticas con una tabla de vectores válida.
- GitHub Actions (`.github/workflows/tests.yml`) compila, ejecuta las pruebas y genera el bundle de la
  app en cada push y pull request.

Publicación de una versión: incrementa `K5.version` en `Sources/K5Core/Constants.swift`, escribe
`release-notes/<version>.md` y ejecuta `./scripts/release.sh`. El script ejecuta las pruebas, compila
la app universal, la firma junto con el framework Sparkle integrado usando el certificado
"Developer ID Application" (hardened runtime), notariza la app y el `.dmg` y les aplica el staple,
firma el `.zip` de actualización con la clave EdDSA de Sparkle y genera
`dist/` (`.dmg`, `.zip`, `appcast.xml`, `SHA256SUMS.txt`, `RELEASE_NOTES.md`). Adjunta todos esos
archivos a la release de GitHub: las copias instaladas leen `releases/latest/download/appcast.xml`. La
configuración inicial, que solo se hace una vez (perfil de notarytool, clave de Sparkle en
`Resources/SparklePublicKey.txt`), está descrita en la cabecera del script. El script no publica nada.

Hooks de prueba (no hacen falta para el uso normal):

- `K5PROG_EXTRA_PORTS=/tmp/k5com` añade rutas de dispositivo a la lista de puertos (para `k5emu --link /tmp/k5com`).
- `K5PROG_UITEST=readcalib,writecalib,quit` junto con `K5PROG_UITEST_OPEN/SAVE/MEMO` controla la app
  real sin diálogos (también `editor`, `editor-import`, `editor-write`, `editor-export`, `snap` con
  `K5PROG_UITEST_SNAP=<dir>` para capturas de las ventanas, `wait`; la lista completa está en [AGENTS.md](AGENTS.md)).
- `K5PROG_BACKUP_DIR=<dir>` guarda ahí las copias de seguridad del Memory Editor.
- `K5PROG_CHANNEL_DUMPS=<dir>` compara la decodificación de canales de tus propios volcados con la de CHIRP
  (`<name>.<profile>.bin` + la salida de `golden.py --decode` como `.json`).
- `K5PROG_SETTINGS_SUITE=<name>` mantiene los ajustes de una ejecución de desarrollo / prueba separados
  de los reales (y omite la importación de un `K5K1Prog.ini` antiguo).
- `K5PROG_SPARKLE_FEED=<url>` hace que el actualizador use otro appcast (pruebas locales de actualización,
  `open --env K5PROG_SPARKLE_FEED=… "K5K1 Prog.app"`).

## Apoyo

K5K1 Prog es gratuito. Si te ha salvado la radio o te ha ahorrado tiempo, puedes
[**Donar**](https://boosty.to/eruban/donate) (a través de Boosty). Las donaciones pagan la cuenta de
Apple Developer que mantiene la app firmada y notarizada, y las pruebas con radios reales.

## Créditos

- K5K1 Prog, de [Evgeny Ruban](https://github.com/ERuban).
- [k5prog-win](https://github.com/OneOfEleven/k5prog-win), de OneOfEleven, el programa del que esta app
  es una adaptación (GPL v3).
- [k5prog](https://github.com/sq5bpf/k5prog), de Jacek Lipkowski SQ5BPF, cuyas rutinas de comunicación
  con la radio son la base de k5prog-win (GPL v3).
- El protocolo del bootloader de UV-K5 V3 / UV-K1, tal como lo implementa el serialtool de muzkr en
  [armel/uv-k1-k5v3-firmware-custom](https://github.com/armel/uv-k1-k5v3-firmware-custom).
- La estructura de canales y las listas de valores del Memory Editor siguen los drivers de
  [CHIRP](https://github.com/kk7ds/chirp): UV-K5, de Jacek Lipkowski SQ5BPF; UV-K1, de Thibaut Berg; y
  los módulos de CHIRP para Karina, de M2Boo (basados en los drivers de egzumer / JOC2 / F4HWN), GPLv2 o
  posterior. CSV e `.img` son formatos de CHIRP.

## Licencia

GPL v3, igual que k5prog-win y k5prog. Consulta [LICENSE](LICENSE). Copyright © 2026 Evgeny Ruban.

K5K1 Prog es una versión modificada de k5prog-win: el programa para Windows en C++/VCL se reescribió en
Swift para macOS, y se añadieron la carga de firmware en UV-K5 V3 / UV-K1, el Memory Editor y las
correcciones de seguridad indicadas arriba (2026).

Este software no está afiliado a Quansheng. Transmite solo en las frecuencias y con los niveles de
potencia para los que tengas licencia.
