# Contributing to K5K1 Prog

Thanks for helping. Bug reports, tests on radios we don't have, and small focused pull requests are
all welcome.

## Before anything else: radios can be bricked

This app writes firmware, calibration and memory into radios. A wrong byte can leave a radio that
won't start or that transmits with wrong power. So:

- Test with the simulator (`k5emu`, below), not with your radio.
- On a real radio, **Read Calibration** and **Read Configuration** first and keep the files.
- Never send a write you have not run against the simulator first.

## Reporting a bug

Open an issue ([templates](../../issues/new/choose)). The most useful details:

- app version (**K5K1 Prog → About**) and macOS version;
- radio model, the firmware string from the status bar (`hello: …`) or the bootloader version
  (`Bootloader version '…'` in the log);
- what you did, what you expected, what happened;
- the log with **Verbose 2** (copy it from the window).

Don't attach firmware files of other authors. Your own calibration / configuration dumps are personal
data: attach them only if you are fine with them being public.

## Development setup

macOS 12 or newer, Xcode Command Line Tools (Swift 5.9 or newer).

```sh
swift build
swift test                                   # all tests, no radio and no firmware files needed
./scripts/build_app.sh                       # "K5K1 Prog.app" in the repository root (ad-hoc signed)
swift run k5emu --mode user --link /tmp/k5com            # simulated radio in normal mode
swift run k5emu --mode boot --bl-version 7.03.01 --link /tmp/k5com   # simulated UV-K1 bootloader
K5PROG_EXTRA_PORTS=/tmp/k5com K5PROG_SETTINGS_SUITE=dev open "K5K1 Prog.app"   # the app sees /tmp/k5com
```

`K5PROG_SETTINGS_SUITE=<name>` keeps your test settings apart from your real ones. More test hooks
(driving the real app without dialogs, window snapshots) are listed in the README, "Development".

Where things are:

| Path | What |
|---|---|
| `Sources/K5Core` | protocol, firmware files, the k5prog-win logic (`K5Programmer.swift`), the channel editor model (`Channels.swift`, `ChannelTransfer.swift`) |
| `Sources/K5K1Prog` | the AppKit app (main window, Memory Editor, Settings) |
| `Sources/K5Sim`, `Sources/k5emu` | the radio simulator on a pseudo terminal |
| `Tests/K5CoreTests` | unit, simulator, reference and channel tests |
| `Tests/Reference` | recordings of the original k5prog-win and CHIRP decodes of synthetic images |
| `scripts/` | app build, release, icon, CHIRP reference generator |

## Rules for changes

- **The UV-K5 V1 path is a one-to-one port of k5prog-win 0.1.26.** Same bytes on the wire, same log
  lines, same timeouts. `ReferenceTests` check this; they must stay green. Deviations are only
  allowed on the safe side, and each one is listed in README "Differences from k5prog-win".
- Refuse rather than guess: unknown bootloader, unknown firmware, wrong file type, odd file size.
- The Memory Editor writes channels only (`0x0000–0x1CFF`, changed 128-byte blocks, after a backup,
  read back and compared). Settings and calibration are never written by it.
- Channel value tables follow the CHIRP drivers. When a profile changes, regenerate the references
  with `scripts/chirp-golden/golden.py` and keep the tests on synthetic images.
- Never commit firmware images of other authors or personal radio dumps.
- New files get the GPL v3 header used in the other sources.
- English everywhere (UI, code, comments, docs). No localization.
- Keep the bundle id `io.github.eruban.k5k1prog`: updates and settings depend on it.
- Update the test count in README "Development" when you add or remove tests.

## Pull requests

- One topic per branch and pull request; describe what and why in a few lines.
- `swift test` green, `./scripts/build_app.sh` builds.
- Say how you checked it: tests, simulator run, real radio (model, firmware, bootloader).
- Releases (version bump, signing, notarization, publishing) are done by the maintainer.

By contributing you agree that your contribution is licensed under the GPL v3, like the project.

## AI coding agents

Instructions for agents are in [AGENTS.md](AGENTS.md).
