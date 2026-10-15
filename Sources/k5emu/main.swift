// K5K1 Prog - macOS programmer for Quansheng UV-K5 / UV-K5 V3 / UV-K1 radios.
//
// Port of k5prog-win v0.1.26 by OneOfEleven (https://github.com/OneOfEleven/k5prog-win),
// which uses comm routines from k5prog by Jacek Lipkowski SQ5BPF
// (https://github.com/sq5bpf/k5prog). Rewritten in Swift for macOS and extended
// (UV-K5 V3 / UV-K1 firmware upload, safety fixes), 2026.
//
// This program is free software: you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option) any later version.
// This program is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE. See the GNU General Public License (LICENSE) for more details.

import Foundation
import Darwin
import K5Sim

// k5emu - UV-K5 radio simulator on a pty, for testing K5K1 Prog / k5prog-win.
//
//   k5emu [--mode user|boot] [--fw-version S] [--bl-version S] [--eeprom FILE]
//         [--out-eeprom FILE] [--out-flash FILE] [--log FILE] [--link PATH]
//         [--keep-beacon] [--real-crc] [--silent] [--seconds N] [--beacon-ms N]
//         [--no-handshake-check]
//   --bl-version 7.xx.xx switches the bootloader to the UV-K5 V3 / UV-K1 (PY32F071) protocol.

var opts = RadioSim.Options()
var eepromIn: String?
var outEEPROM: String?
var outFlash: String?
var logPath: String?
var linkPath: String?
var seconds: Double = 0

var args = Array(CommandLine.arguments.dropFirst())
func next() -> String { args.isEmpty ? "" : args.removeFirst() }
while !args.isEmpty {
    switch next() {
    case "--mode": opts.mode = RadioSim.Mode(rawValue: next()) ?? .user
    case "--fw-version": opts.firmwareVersion = next()
    case "--bl-version": opts.bootloaderVersion = next()
    case "--eeprom": eepromIn = next()
    case "--out-eeprom": outEEPROM = next()
    case "--out-flash": outFlash = next()
    case "--log": logPath = next()
    case "--link": linkPath = next()
    case "--keep-beacon": opts.keepBeacon = true
    case "--real-crc": opts.realCRC = true
    case "--silent": opts.silent = true
    case "--no-session-check": opts.checkSession = false
    case "--seconds": seconds = Double(next()) ?? 0
    case "--beacon-ms": opts.beaconIntervalMs = Int(next()) ?? opts.beaconIntervalMs
    case "--no-handshake-check": opts.py32RequireHandshake = false
    case let a:
        FileHandle.standardError.write("unknown argument \(a)\n".data(using: .utf8)!)
        exit(2)
    }
}

var initial: [UInt8]? = nil
if let p = eepromIn, let d = FileManager.default.contents(atPath: p) { initial = [UInt8](d) }

let sim = RadioSim(options: opts, eeprom: initial)
let path = try sim.openPTY()
if let l = linkPath {
    try? FileManager.default.removeItem(atPath: l)
    try FileManager.default.createSymbolicLink(atPath: l, withDestinationPath: path)
}

let logHandle: FileHandle? = {
    guard let p = logPath else { return nil }
    FileManager.default.createFile(atPath: p, contents: nil)
    return FileHandle(forWritingAtPath: p)
}()

func dump() {
    if let p = outEEPROM { FileManager.default.createFile(atPath: p, contents: Data(sim.eeprom)) }
    if let p = outFlash {
        let used = sim.flashWritten.last.map { $0 + 1 } ?? 0
        FileManager.default.createFile(atPath: p, contents: Data(sim.flash[0..<used]))
    }
}

let t0 = Date()
sim.onEvent = { line in
    let s = String(format: "%8.3f ", Date().timeIntervalSince(t0)) + line + "\n"
    logHandle?.write(s.data(using: .utf8)!)
    if line.hasPrefix("EVT reboot") { dump() }
}

print(path)
fflush(stdout)
sim.start()

signal(SIGINT) { _ in dump(); exit(0) }
signal(SIGTERM) { _ in dump(); exit(0) }

if seconds > 0 {
    Thread.sleep(forTimeInterval: seconds)
    dump()
    exit(0)
}
while true { Thread.sleep(forTimeInterval: 1) }
