<p align="center">
    <a href="https://github.com/ERuban/k5k1prog-mac/releases/latest"><img alt="K5K1 Prog"
         src="Resources/logo.svg" width="160"
    /></a>
</p>

<h1 align="center">K5K1 Prog</h1>

<p align="center">在 macOS 上备份、恢复和刷写泉盛（Quansheng）UV-K5 / UV-K5 V3 / UV-K1 对讲机</p>

<p align="center"><a href="https://eruban.github.io/k5k1prog-mac/">eruban.github.io/k5k1prog-mac</a></p>

<p align="center">
  <a href="README.md">English</a> |
  <a href="README_RU.md">Русский</a> |
  <a href="README_ES.md">Español</a> |
  <a href="README_DE.md">Deutsch</a>
</p>

*本文为译文，如有出入，以英文版 [README.md](README.md) 为准。*

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

**k5prog-win v0.1.26**（OneOfEleven）的 macOS 移植版，并做了若干改进。

一款原生 macOS 应用，通过写频线对泉盛 **UV-K5 / UV-K5(8) / UV-K6 / UV-5R Plus**（V1，DP32G030）和 **UV-K5 V3 / UV-K1**（PY32F071）对讲机进行备份、恢复和刷机。

它与 [k5prog-win](https://github.com/OneOfEleven/k5prog-win) 的行为完全一致（相同的按钮、相同的日志、线路上传输的字节也完全相同），并增加了 k5prog-win 所不支持的新款 UV-K5 V3 和 UV-K1 固件写入功能、信道编辑器以及若干安全修复（参见[与 k5prog-win 的区别](#与-k5prog-win-的区别)）。

## 功能

- **读取 / 写入校准数据**（`0x1E00` 处的 512 字节）。刷写任何固件之前，请先备份对讲机的出厂校准数据。
- **读取 / 写入配置**（信道和设置，`0x0000–0x1CFF`）。
- **写入固件**，支持原始 `.bin` 或厂家的 `.packed.bin`。程序直接从固件镜像本身识别对讲机类型，并在写入任何数据之前与 bootloader 进行核对。
- **Memory Editor**（信道编辑器）：编辑对讲机的 200 个信道，支持原厂固件和 Karina 固件，适用于 UV-K5 V1 以及 UV-K1 / UV-K5 V3（参见[编辑信道](#编辑信道)）。可以编辑、复制信道，或在两台对讲机之间拖放信道；导入 / 导出 CHIRP CSV 和 CHIRP `.img`；原厂固件下还可编辑开机文字。只写入有改动的信道，写入前先备份，写入后回读校验。设置和校准数据始终不会被改动。
- 主窗口显示**对讲机状态**：写频线上连接的是哪台对讲机、处于何种模式以及它的固件字符串，每 2 秒在后台静默检测一次。
- **Settings**（设置，**K5K1 Prog → Settings…**）：浅色 / 深色外观，以及编辑器备份文件的存放文件夹。
- 通用应用（Apple Silicon 和 Intel），需要 macOS 12 或更高版本。使用 CH340 写频线时无需安装驱动或其他软件。
- 设置（端口、速率、日志详细程度、窗口位置、外观）按 macOS 的惯例保存在 `~/Library/Preferences/io.github.eruban.k5k1prog.plist` 中，不会在应用旁边写入任何文件。

## 支持的机型

| 机型 | MCU | Bootloader | 校准 / 配置 | 固件 |
|---|---|---|---|---|
| UV-K5, UV-K5(8), UV-K6, UV-5R Plus ("V1") | DP32G030 | 2.x – 4.x | ✅ | ✅（k5prog-win 协议） |
| UV-K5 V3, UV-K1 | PY32F071 | 7.xx（7.00.07 或更高） | ✅ | ✅ |
| UV-K5 V2, UV-K6 V2 | PY32F030 | 1.xx | ✅ | ❌ 拒绝写入 |

型号印在电池下方的机身上（V2、V3），但 bootloader 版本才是可靠的判断依据：让对讲机进入 bootloader 模式并按 **Write Firmware**，日志中会显示 `Bootloader version '…'`。bootloader 为 5.x 的 UV-5R Plus Type-C 对讲机使用加密的 bootloader 协议，不受支持。

已在真机上测试：一台 UV-K5 V1（bootloader 2.00.06）和一台 UV-K1（bootloader 7.03.01）。两台都用 K5K1 Prog 刷写过固件，都读取过校准和配置数据；另外还向 UV-K1 写入了校准数据，并通过回读进行了校验。

> [!WARNING]
> V1、V2 与 V3/K1 对讲机的固件**不能互换**。K5K1 Prog 在发送任何数据之前都会检查：V1 固件遇到 7.xx bootloader、V3/K1 固件遇到其他任何 bootloader，以及任何固件遇到 V2 bootloader（1.xx），都会被拒绝。
>
> 它**无法区分 UV-K1 固件和 UV-K5 V3 固件**（芯片相同、bootloader 相同，而且 bootloader 不会报告机型）。请选择与你的机型对应的文件。如果刷错了，对讲机可能工作异常或无法开机，但 bootloader 不会被覆盖：按住 **PTT** 开机，再刷入正确的文件即可。
>
> 刷机风险自负。

## 安装

使用 [Homebrew](https://brew.sh)：

```sh
brew install --cask eruban/tap/k5k1-prog
```

`brew upgrade` 即可安装新版本（[ERuban/homebrew-tap](https://github.com/ERuban/homebrew-tap) 中的 cask 会自动跟进每一次发布）。

或者从 [Releases](../../releases) 下载 `K5K1-Prog-<version>.dmg`，打开后将 **K5K1 Prog** 拖到 **Applications**（应用程序）文件夹。应用使用 Developer ID 签名并经过 Apple 公证，打开时不会出现警告。发布页还附有包含同一应用的 `.zip`。

从 1.1.0 版起，应用可以自动更新：每天检查一次 GitHub 上是否有新版本（也可通过 **K5K1 Prog → Check for Updates…** 手动检查），显示更新内容，一键安装（[Sparkle](https://sparkle-project.org)，更新包使用 EdDSA 签名）。1.0.0 版没有更新功能，因此需要手动安装一次 1.1.0。

或者从源码构建（需要 Xcode Command Line Tools 以及 Swift 5.9 或更高版本）：

```sh
git clone <this repository> k5k1prog-mac && cd k5k1prog-mac
./scripts/build_app.sh        # -> "K5K1 Prog.app" in the repository root (ad-hoc signed)
open "K5K1 Prog.app"
```

## 使用方法

用写频线（2 针 Kenwood 插头）连接对讲机。写频线会显示为 `/dev/cu.usbserial-…`（如果安装了 WCH 驱动，则显示为 `/dev/cu.wchusbserial…`）。在 **Serial port** 中选择它，速率保持 **38400 - k5/k6** 不变。

### 先备份

1. 正常开机。
2. 点击 **Read Calibration**，把文件保存到安全的地方。其中包含这台对讲机自己的发射功率和电池校准数据，一旦丢失，无处可以找回。
3. 点击 **Read Configuration** 并保存。

校准和配置数据以同样的方式写回（**Write Calibration**、**Write Configuration**），同样需要对讲机处于正常开机状态。

### 刷写固件

1. 关闭对讲机，按住 **PTT** 再开机。屏幕保持无显示：对讲机已进入 bootloader 模式。
2. 点击 **Write Firmware**，选择适用于你机型的 `.bin`（或 `.packed.bin`）文件。
3. 查看日志：V1 对讲机的 `Bootloader version '…'` 以 `2`–`4` 开头，V3/K1 以 `7` 开头。
4. 等待出现 `write FLASH complete`。对讲机会以新固件重新启动。

之后请按照所刷固件的说明操作（重置存储、需要加载哪些校准文件等）。有些固件包附带完整的校准文件，会替换掉你的出厂发射功率和电池校准值。完成后请重新 **Read Calibration**，并与之前的备份进行比较。

### 编辑信道

1. 正常开机，选择对应端口，然后点击 **Memory Editor…**（⌘E）。程序会从对讲机读取信道；窗口中显示的始终是对讲机当前的内容。
2. **Firmware** 和 **Radio** 根据对讲机的固件字符串自动选择：原厂固件按版本号识别，Karina 按其代号识别。Karina 在 UV-K5 V1 和 UV-K1 上的固件字符串相同，因此编辑器会询问一次是哪种对讲机。无法识别的固件会以只读方式打开，直到你手动选择。如果你的选择与固件字符串相矛盾，编辑器会用红字提示：此时信道参数（模式、步进、加扰）会被错误地读取和写入。
3. 双击单元格即可编辑。选中多个信道可以一起修改，可使用 **Set Power**、**Delete**，按 ⌘Z 撤销。
4. **Write to Radio…** 会列出所有改动，保存一份对讲机配置的备份（`~/Documents/K5K1 Prog Backups/`，见 Settings），检查对讲机自读取以来是否发生过变化，只写入有改动的数据块，然后回读并比较。可以用 **Write Configuration** 恢复备份。

把信道复制到另一台对讲机：为每台对讲机各打开一个编辑器（每个端口一个），把信道拖过去或使用 Copy / Paste（复制 / 粘贴）；也可以在一台上 **Export Channels…**，在另一台上 **Import Channels…**。目标固件不支持的参数（如原厂固件上的 USB 模式、Karina 的加扰列表、更细的步进）会被转换并列出。导入时保留信道编号；文件中的设置会被忽略。支持的格式：CHIRP CSV、CHIRP `.img`（原厂或 Karina，UV-K5 / UV-K1），以及通过 Read Configuration 得到的配置 `.bin`（`.bin` 文件中没有记录来自哪台对讲机：请在导入对话框中选择）。

编辑器窗口处于活动状态时，每 2 秒检测一次对讲机。如果换接了另一台对讲机，编辑器会读取新的这台（如果有尚未写入的修改，则会给出提示，且不会向它写入）。

只编辑信道存储（200 个信道，即原厂固件、Karina 和 F4HWN 共用的原厂布局）。不支持其他固件、超过 200 个信道的情况（UV-K1 上的 F4HWN）以及对讲机的设置。

## 与 k5prog-win 的区别

所有改动都偏向安全：

1. **UV-K5 V3 / UV-K1 固件写入**（PY32F071，bootloader 7.xx），详见下文。
2. V1（DP32G030）固件文件绝不会发送给 7.xx bootloader；向 UV-K5 V2 / K6 V2（bootloader 1.xx，PY32F030）写入固件会被拒绝：V1 固件会让这类对讲机黑屏。
3. **大小不是 128 字节整数倍的配置文件。** k5prog-win 会越过缓冲区末尾读取，把随机的内存数据写入对讲机。本程序中，最后一个块的剩余部分保留对讲机自身的字节（先回读）。正常文件（7424 / 8192 / 512 字节）不受影响。
4. 端口列表显示 `/dev/cu.*`（相当于 Windows 下的 COM 端口列表）。状态栏没有“RX BREAK”指示。
5. 主窗口在启动和切换端口时不会查询对讲机并写入日志（“Fetching radio details .. radio not detected”）。对讲机状态改为显示在状态栏中，按钮也随之启用或禁用：配置、校准和编辑器需要对讲机处于正常模式，Write Firmware 需要对讲机处于固件升级模式，未连接对讲机时所有按钮均不可用。过长的日志行会自动换行。
6. **Settings** 保存在 macOS 偏好设置中（`io.github.eruban.k5k1prog`），而不是应用旁边的 ini 文件：在 Mac 上那个文件夹是 `/Applications`。键名与 `k5prog_win.ini` 相同（`MainForm.Top`、`GUI.Verbose`、`SerialPort.Name` 等）。1.0 / 1.1 版使用 `K5K1Prog.ini`；该文件会被导入一次，然后删除。文件对话框默认打开 `~/Documents`。

其余一切与原版一致：按钮、操作顺序、超时（hello 2×1 秒、读取 3 秒、写入 2 秒、刷写 3 秒）、重试、校验、每一行日志和每个消息框的文字、协议（帧、XOR 表、CRC、会话 ID `6A 39 57 64`、128 字节配置块、256 字节闪存块、bootloader 版本修正 `4.00.07` → `*.00.07`）、设置键名，以及按 Esc 中止传输。

## UV-K5 V3 / UV-K1 固件写入

**Write Firmware** 通过向量表识别文件类型：PY32F071 镜像的复位向量位于 `0x080xxxxx`，DP32G030 镜像位于 `0x0000xxxx`。两种类型都接受原始 `.bin` 和厂家 `.packed.bin` 文件。V1 文件仍走未经改动的 k5prog-win 流程。

PY32 协议（与 muzkr 的 serialtool 相同）：

- bootloader 版本必须以 `7` 开头且不低于 `7.00.07`，否则不发送任何数据；
- 连续收到 5 个间隔有效（5–1000 ms）的 `0x0518` 信标后，发送 `0x0530`，内容为 bootloader 版本的前 4 个字符，每个信标发送一次，共 3 次；
- `0x0519` 页：时间戳 LE32、页号 LE16、页数 LE16、4 × `00`、256 个数据字节（最后一页用 `00` 填充）；应答为 `0x051A`：时间戳 / 页号 / 错误码；每页 3 秒，出错或无应答时同一页最多重发 3 次；
- 镜像最大 `0x1D800`（应用区起始于 `0x08002800`，118 KB）；
- 结束时不发送重启命令，bootloader 会自行启动新固件。

错误的组合会在写入任何数据之前被拒绝：7.xx bootloader 上的 V1 文件、其他任何 bootloader 上的 V3/K1 文件、V2 bootloader（1.xx）上的任何文件、低于 7.00.07 的 bootloader、过大的镜像、未处于 bootloader 模式的对讲机。

## 开发

欢迎参与贡献：请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)（英文）；AI 编程代理另请参阅 [AGENTS.md](AGENTS.md)（英文）。

```sh
swift test                    # 76 tests: simulator, protocol, reference comparisons, channels
swift run k5emu --mode boot --bl-version 7.03.01 --link /tmp/k5com   # simulated K1 bootloader
```

- `Sources/K5Core`：协议、固件文件处理、k5prog-win 的逻辑；`Channels.swift` 和 `ChannelTransfer.swift` 用于 Memory Editor（信道布局、profile、CSV / `.img`）。
- `Sources/K5K1Prog`：AppKit 应用。
- `docs/`：项目网站（GitHub Pages，五种语言），由 `scripts/build_site.py` 生成；请在该脚本中修改文字，然后运行它。
- `scripts/chirp-golden/golden.py`：使用真实的 CHIRP 驱动生成信道测试参考数据（合成镜像，不含个人数据）。仅在 profile 变更时需要。
- `Sources/K5Sim`、`Sources/k5emu`：运行在伪终端上的 UV-K5 模拟器。支持用户模式、V1 bootloader，以及用于 PY32 bootloader 的 `--bl-version 7.xx.xx`。可在 `RadioSim.Options` 中注入页被拒绝或丢失的故障。
- 测试不需要任何固件文件：固件写入测试（V1 和 PY32，原始格式和 `.packed`）使用带有效向量表的合成镜像。
- GitHub Actions（`.github/workflows/tests.yml`）在每次 push 和 pull request 时构建、运行测试并构建应用包。

发布：在 `Sources/K5Core/Constants.swift` 中提升 `K5.version`，编写 `release-notes/<version>.md`，然后运行 `./scripts/release.sh`。该脚本会运行测试，构建通用应用，用“Developer ID Application”证书（hardened runtime）为应用及内嵌的 Sparkle 框架签名，对应用和 `.dmg` 进行公证并装订（staple），用 Sparkle EdDSA 密钥为更新用的 `.zip` 签名，并生成 `dist/`（`.dmg`、`.zip`、`appcast.xml`、`SHA256SUMS.txt`、`RELEASE_NOTES.md`）。请把这些文件全部附加到 GitHub release 中：已安装的应用会读取 `releases/latest/download/appcast.xml`。一次性设置（notarytool profile、`Resources/SparklePublicKey.txt` 中的 Sparkle 密钥）写在脚本开头。该脚本不会发布任何内容。

测试钩子（正常使用时不需要）：

- `K5PROG_EXTRA_PORTS=/tmp/k5com` 向端口列表添加设备路径（配合 `k5emu --link /tmp/k5com` 使用）。
- `K5PROG_UITEST=readcalib,writecalib,quit` 配合 `K5PROG_UITEST_OPEN/SAVE/MEMO`，可在不弹出对话框的情况下驱动真实应用（另有 `editor`、`editor-import`、`editor-write`、`editor-export`，配合 `K5PROG_UITEST_SNAP=<dir>` 生成窗口截图的 `snap`，以及 `wait`；完整列表见 [AGENTS.md](AGENTS.md)）。
- `K5PROG_BACKUP_DIR=<dir>` 指定 Memory Editor 备份文件的存放位置。
- `K5PROG_CHANNEL_DUMPS=<dir>` 将你自己的转储文件的信道解码结果与 CHIRP 的结果进行比较（`<name>.<profile>.bin` 加上保存为 `.json` 的 `golden.py --decode` 输出）。
- `K5PROG_SETTINGS_SUITE=<name>` 将开发 / 测试运行时的设置与正式设置分开（并跳过旧 `K5K1Prog.ini` 的导入）。
- `K5PROG_SPARKLE_FEED=<url>` 让更新程序使用另一个 appcast（用于本地更新测试，`open --env K5PROG_SPARKLE_FEED=… "K5K1 Prog.app"`）。

## 赞助支持

K5K1 Prog 是免费软件。如果它挽救了你的对讲机或为你节省了时间，欢迎[**捐赠**](https://boosty.to/eruban/donate)（通过 Boosty）。捐款用于支付 Apple 开发者账户的费用（应用的签名和公证依赖该账户），以及在真机上进行测试。

## 致谢

- K5K1 Prog 作者：[Evgeny Ruban](https://github.com/ERuban)。
- OneOfEleven 的 [k5prog-win](https://github.com/OneOfEleven/k5prog-win)，本应用即移植自该程序（GPL v3）。
- Jacek Lipkowski SQ5BPF 的 [k5prog](https://github.com/sq5bpf/k5prog)，k5prog-win 的对讲机通信例程以它为基础（GPL v3）。
- UV-K5 V3 / UV-K1 bootloader 协议参照 muzkr 的 serialtool 实现，见 [armel/uv-k1-k5v3-firmware-custom](https://github.com/armel/uv-k1-k5v3-firmware-custom)。
- Memory Editor 的信道布局和参数列表遵循 [CHIRP](https://github.com/kk7ds/chirp) 驱动：UV-K5 驱动由 Jacek Lipkowski SQ5BPF 编写，UV-K1 驱动由 Thibaut Berg 编写，Karina 的 CHIRP 模块由 M2Boo 编写（基于 egzumer / JOC2 / F4HWN 驱动），采用 GPLv2 或更高版本许可。CSV 和 `.img` 是 CHIRP 的文件格式。

## 许可证

GPL v3，与 k5prog-win 和 k5prog 相同。参见 [LICENSE](LICENSE)。Copyright © 2026 Evgeny Ruban.

K5K1 Prog 是 k5prog-win 的修改版本：原先用 C++/VCL 编写的 Windows 程序已用 Swift 重写为 macOS 应用，并新增了 UV-K5 V3 / UV-K1 固件写入、Memory Editor 以及上文所列的安全修复（2026 年）。

本软件与泉盛（Quansheng）无任何关联。请仅在你获得许可的频率和功率范围内发射。
