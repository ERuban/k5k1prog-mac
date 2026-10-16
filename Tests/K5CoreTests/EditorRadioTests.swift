// K5K1 Prog - channel editor radio operations against the simulator.
//
// Copyright (C) 2026 Evgeny Ruban (changes and the macOS app).
//
// This program is free software: you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option) any later version.

import XCTest
@testable import K5Core
import K5Sim

final class EditorRadioTests: XCTestCase {
    var sim: RadioSim!
    var prog: K5Programmer!
    var ui: RecordingUI!
    var saved: [String: [UInt8]] = [:]

    func start(firmware: String = "autumn rain 21.0", eeprom: [UInt8]? = nil, boot: Bool = false) throws {
        var o = RadioSim.Options()
        o.firmwareVersion = firmware
        o.beaconIntervalMs = 100
        if boot { o.mode = .boot }
        sim = RadioSim(options: o, eeprom: eeprom)
        let path = try sim.openPTY()
        sim.start()
        prog = K5Programmer()
        ui = RecordingUI()
        prog.ui = ui
        prog.selectedPort = path
        prog.verbose = 1
        saved = [:]
        prog.saveFileHook = { [unowned self] n, d in self.saved[n] = d }
    }

    override func tearDown() { sim?.close(); sim = nil }

    var writes: [String] { sim.log.filter { $0.hasPrefix("C>R 1D 05") } }

    /// The K1's real state: everything FF after the memory clear, calibration below.
    func emptyK1() -> [UInt8] {
        var m = [UInt8](repeating: 0xFF, count: 0x2000)
        for i in 0x1E00..<0x2000 { m[i] = UInt8(truncatingIfNeeded: i * 13) }
        return m
    }

    func testReadReturnsWholeMemoryAndFirmware() throws {
        try start(firmware: "7.03.01")
        let r = try XCTUnwrap(prog.editorRead())
        XCTAssertEqual(r.firmware, "7.03.01")
        XCTAssertEqual(r.memory, sim.eeprom)
        XCTAssertEqual(r.memory.count, 0x2000)
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(sim.rebootCount, 0)
        XCTAssertFalse(prog.connected)
    }

    func testWriteOnlyChangedBlocksWithBackupAndVerify() throws {
        try start(eeprom: emptyK1())
        let read = try XCTUnwrap(prog.editorRead())
        let profile = FirmwareProfile(.karina, .k1)
        var mem = ChannelMemory(bytes: Array(read.memory.prefix(K5.configSize)), profile: profile)
        var c = Channel(); c.name = "PMR-1"; c.freq = 446_006_250; c.mode = .nfm; c.step = 6.25; c.scanList1 = true
        mem.setChannel(0, c)
        c.name = "PMR-2"; c.freq = 446_018_750
        mem.setChannel(1, c)
        let calibBefore = Array(sim.eeprom[0x1D00..<0x2000])
        let blocks = mem.changedBlocks(from: ChannelMemory(bytes: Array(read.memory.prefix(K5.configSize)), profile: profile))
        XCTAssertEqual(blocks, [0x0000, 0x0D00, 0x0F00], "channels, attributes, names")

        let res = prog.editorWrite(snapshot: read.memory, edited: mem.bytes, firmware: read.firmware, backupPath: "/tmp/b/backup.bin")
        XCTAssertEqual(res, .ok, ui.lines.joined(separator: "\n"))
        XCTAssertEqual(writes.count, 3)
        XCTAssertEqual(Array(sim.eeprom[0..<K5.configSize]), mem.bytes)
        XCTAssertEqual(Array(sim.eeprom[0x1D00..<0x2000]), calibBefore, "calibration untouched")
        XCTAssertEqual(saved["/tmp/b/backup.bin"], Array(read.memory.prefix(K5.configSize)), "backup = radio before the write")
        XCTAssertEqual(sim.rebootCount, 1)
        XCTAssertTrue(ui.lines.contains("write CHANNELS complete, verified"))
        let back = ChannelMemory(bytes: Array(sim.eeprom.prefix(K5.configSize)), profile: profile)
        XCTAssertEqual(back.channel(0)?.name, "PMR-1")
        XCTAssertEqual(back.channel(1)?.freq, 446_018_750)
        XCTAssertNil(back.channel(2))
    }

    func testRefusesWhenFirmwareChanged() throws {
        try start(eeprom: emptyK1())
        let read = try XCTUnwrap(prog.editorRead())
        var edited = read.memory; edited[0] = 0x10
        sim.close()
        try start(firmware: "7.03.01", eeprom: emptyK1())   // another radio on the cable
        guard case .failed(let msg) = prog.editorWrite(snapshot: read.memory, edited: edited, firmware: read.firmware, backupPath: "/tmp/b/x.bin")
        else { return XCTFail("written") }
        XCTAssertTrue(msg.contains("7.03.01"), msg)
        XCTAssertTrue(writes.isEmpty)
        XCTAssertTrue(saved.isEmpty, "no backup either")
    }

    func testRefusesWhenRadioChangedWhereWeWrite() throws {
        try start(eeprom: emptyK1())
        let read = try XCTUnwrap(prog.editorRead())
        var edited = read.memory; edited[0x0010] = 0x55        // block 0000
        sim.eeprom[0x0020] = 0x77                                 // the radio changed block 0000 meanwhile
        guard case .failed(let msg) = prog.editorWrite(snapshot: read.memory, edited: edited, firmware: read.firmware, backupPath: "/tmp/b/y.bin")
        else { return XCTFail("written") }
        XCTAssertTrue(msg.contains("0000"), msg)
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(sim.eeprom[0x0010], 0xFF)
        XCTAssertNotNil(saved["/tmp/b/y.bin"], "the backup is taken first")
    }

    func testRadioChangesElsewhereAreKept() throws {
        try start(eeprom: emptyK1())
        let read = try XCTUnwrap(prog.editorRead())
        var edited = read.memory; edited[0x0010] = 0x55        // block 0000
        sim.eeprom[0x0C90] = 0x33                                 // VFO area changed by the radio: not ours
        XCTAssertEqual(prog.editorWrite(snapshot: read.memory, edited: edited, firmware: read.firmware, backupPath: "/tmp/b/z.bin"), .ok)
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(sim.eeprom[0x0010], 0x55)
        XCTAssertEqual(sim.eeprom[0x0C90], 0x33)
    }

    func testNeverWritesAboveConfigArea() throws {
        try start(eeprom: emptyK1())
        let read = try XCTUnwrap(prog.editorRead())
        var edited = read.memory
        for i in 0x1D00..<0x2000 { edited[i] = 0 }               // calibration "edits" are ignored
        XCTAssertEqual(prog.editorWrite(snapshot: read.memory, edited: edited, firmware: read.firmware, backupPath: "/tmp/b/c.bin"), .failed("nothing changed"))
        XCTAssertTrue(writes.isEmpty)
    }

    func testBootloaderModeRefused() throws {
        try start(boot: true)
        XCTAssertNil(prog.editorRead())
        XCTAssertTrue(ui.lines.contains { $0.contains("firmware update mode") })
    }
}

final class EditorProbeTests: XCTestCase {
    func testProbeIsQuietAndReadsBlocks() throws {
        var o = RadioSim.Options(); o.firmwareVersion = "autumn rain 21.0"; o.beaconIntervalMs = 100
        let sim = RadioSim(options: o, eeprom: nil)
        defer { sim.close() }
        let path = try sim.openPTY()
        sim.start()
        let prog = K5Programmer(), ui = RecordingUI()
        prog.ui = ui
        prog.verbose = 3
        let r = prog.editorProbe(port: path, blocks: [0x0000, 0x0D80])
        XCTAssertEqual(r, .radio(firmware: "autumn rain 21.0", blocks: [0x0000: Array(sim.eeprom[0..<128]), 0x0D80: Array(sim.eeprom[0x0D80..<0x0E00])]))
        XCTAssertEqual(ui.lines, [], "nothing in the log")
        XCTAssertFalse(prog.connected)
        XCTAssertFalse(sim.log.contains { $0.hasPrefix("C>R 1D 05") }, "no writes")
        // the log works again afterwards
        prog.selectedPort = path
        prog.readCalibrationButtonClick()
        XCTAssertFalse(ui.lines.isEmpty)
    }

    func testProbeNoRadioIsFast() throws {
        var o = RadioSim.Options(); o.silent = true
        let sim = RadioSim(options: o, eeprom: nil)
        defer { sim.close() }
        let path = try sim.openPTY()
        sim.start()
        let prog = K5Programmer()
        let t = Date()
        XCTAssertEqual(prog.editorProbe(port: path, blocks: [0]), .noRadio)
        XCTAssertLessThan(Date().timeIntervalSince(t), 0.8)
        XCTAssertEqual(prog.editorProbe(port: "/dev/cu.no-such-port", blocks: [0]), .noPort)
    }

    func testProbeFlashMode() throws {
        var o = RadioSim.Options(); o.mode = .boot; o.beaconIntervalMs = 50
        let sim = RadioSim(options: o, eeprom: nil)
        defer { sim.close() }
        let path = try sim.openPTY()
        sim.start()
        XCTAssertEqual(K5Programmer().editorProbe(port: path, blocks: [0]), .flashMode(bootloader: "2.00.06"))
    }
}
