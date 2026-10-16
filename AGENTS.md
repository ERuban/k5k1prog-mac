# Instructions for AI coding agents

K5K1 Prog is a native macOS app (Swift, AppKit, SwiftPM) that backs up, restores and flashes
Quansheng UV-K5 / UV-K5 V3 / UV-K1 radios. A mistake here can brick a radio. Read
[CONTRIBUTING.md](CONTRIBUTING.md) first; this file adds what an agent must know.

## Safety rules (never break these)

- **Never talk to a real radio.** No writes, no flashing, not even "just a read", unless the human
  asks for that exact step. Use the simulator: `swift run k5emu --mode user|boot --link /tmp/k5com`
  and `K5PROG_EXTRA_PORTS=/tmp/k5com`.
- **The UV-K5 V1 path is a one-to-one port of k5prog-win 0.1.26** (protocol, timeouts, retries, log
  lines, message texts). Don't "clean it up". `ReferenceTests` must stay green. Any deviation must be
  on the safe side and listed in README "Differences from k5prog-win".
- Refuse instead of guessing (unknown bootloader or firmware, wrong file type, odd sizes). Checks run
  before the first byte is sent.
- The Memory Editor writes only changed 128-byte blocks inside `0x0000–0x1CFF`, after a backup and a
  check that the radio still matches what was read, then reads back and compares. Never write
  settings or calibration from the editor; never write above `0x1CFF`.
- Never add firmware images of other authors or personal radio dumps to the repository. Tests use
  synthetic images (`Tests/Reference/channels`, synthetic vector tables for firmware).
- Don't change the bundle id `io.github.eruban.k5k1prog` or the settings keys (`Section.Key`).
- Don't publish: no tags, releases, appcast edits or signing. The maintainer releases.

## Commands

```sh
swift build
swift test                      # must pass; no radio and no firmware files needed
./scripts/build_app.sh          # builds "K5K1 Prog.app" (ad-hoc signed)
```

Drive the real app without dialogs (combine with `k5emu` and `K5PROG_EXTRA_PORTS`):

```sh
K5PROG_SETTINGS_SUITE=agent K5PROG_UITEST=editor,wait,snap,quit K5PROG_UITEST_SNAP=/tmp/snaps \
  K5PROG_UITEST_MEMO=/tmp/memo.txt .build/debug/K5K1Prog
```

Steps: `readconfig`, `writeconfig`, `readcalib`, `writecalib`, `firmware`, `clear`, `wait` (3 s),
`snap` (window PNGs into `K5PROG_UITEST_SNAP`), `gauge`, `settings`, `quit`, `probe-quit`, and for
the editor `editor`, `editor-profile=<karina|stock>.<v1|k1>`, `editor-edit=<column>:<channel>`,
`editor-set=<column>:<channel>:<text>`, `editor-caret` / `editor-caret-end` (caret checks, logged),
`editor-import` / `editor-export` (`K5PROG_UITEST_OPEN` /
`K5PROG_UITEST_SAVE`, a `.bin` needs `K5PROG_UITEST_BIN_PROFILE`), `editor-write`, `editor-close`.
`K5PROG_UITEST_MEMO` gets the log after every step; editor messages appear there as `[editor] …`.
Always set `K5PROG_SETTINGS_SUITE` (and `K5PROG_BACKUP_DIR`) so the user's own settings and backups
stay untouched; delete the test suite afterwards (`defaults delete <name>`).

## Code notes

- `Sources/K5Core/K5Programmer.swift` keeps the original function names in doc comments
  (`k5_hello()`, `ReadConfigButtonClick()`); keep that mapping when you change something.
- Workers run on a serial queue and are started from `DispatchQueue.main.async` (a keyboard-pressed
  button runs a private run-loop mode; `main.sync` from the worker would deadlock).
- Never call `NSAlert.runModal` or bring windows to the front from background flows: the app must not
  steal focus. Use sheets.
- The quiet radio check (every 2 s, `editorProbe`) logs nothing and must not disturb typing,
  operations or closing.
- Channel profiles (stock / Karina, UV-K5 V1 / UV-K1) differ only in value tables; they come from the
  CHIRP drivers (GPLv2+, credited in README and the file headers). Regenerate references with
  `scripts/chirp-golden/golden.py` when a table changes.
- Parse user and file input strictly (`ChannelFiles.parseFreq`): never `Double` → `Int` conversions
  that can trap, never force-unwraps on input.
- English only; GPL v3 header in new files; update the README test count when the suite changes.

## Before you hand the change back

- `swift test` green, `./scripts/build_app.sh` builds.
- For UI changes: a simulator run with `snap`, and look at the PNGs.
- Say what you verified and how (tests, simulator, snapshots), and what you did not.
