// K5K1 Prog - macOS programmer for Quansheng UV-K5 / UV-K5 V3 / UV-K1 radios.
//
// Port of k5prog-win v0.1.26 by OneOfEleven (https://github.com/OneOfEleven/k5prog-win),
// which uses comm routines from k5prog by Jacek Lipkowski SQ5BPF
// (https://github.com/sq5bpf/k5prog). Rewritten in Swift for macOS and extended
// (UV-K5 V3 / UV-K1 firmware upload, safety fixes), 2026.
//
// Copyright (C) 2026 Evgeny Ruban (changes and the macOS app).
//
// This program is free software: you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option) any later version.
// This program is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE. See the GNU General Public License (LICENSE) for more details.

import XCTest
@testable import K5Core
import K5Sim

/// Fake form: records the memo and answers dialogs.
final class RecordingUI: K5UI {
    var lines: [String] = []
    var errors: [String] = []
    var questions: [String] = []
    var answerYes = false
    var openPath: String?
    var savePath: String?
    var saveTitles: [String] = []
    var gaugeVisible = false
    private let lock = NSLock()

    func memoAdd(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
    func memoClear() { lock.lock(); lines.removeAll(); lock.unlock() }
    func gauge(max: Int, progress: Int, visible: Bool) { gaugeVisible = visible }
    func connectionStateChanged() {}
    func messageBoxError(_ text: String) { errors.append(text) }
    func messageBoxYesNo(_ text: String) -> Bool { questions.append(text); return answerYes }
    func openDialog(_ dialog: FileDialog, title: String) -> String? { openPath }
    func saveDialog(_ dialog: FileDialog, title: String) -> String? { saveTitles.append(title); return savePath }
}

final class IntegrationTests: XCTestCase {
    var sim: RadioSim!
    var prog: K5Programmer!
    var ui: RecordingUI!
    var saved: [String: [UInt8]] = [:]
    var files: [String: [UInt8]] = [:]

    func makeSim(_ configure: (inout RadioSim.Options) -> Void = { _ in }, eeprom: [UInt8]? = nil) throws {
        var o = RadioSim.Options()
        o.beaconIntervalMs = 100
        configure(&o)
        sim = RadioSim(options: o, eeprom: eeprom)
        let path = try sim.openPTY()
        sim.start()
        prog = K5Programmer()
        ui = RecordingUI()
        prog.ui = ui
        prog.selectedPort = path
        prog.selectedSpeed = 38400
        prog.verbose = 1
        saved = [:]
        prog.saveFileHook = { [unowned self] name, data in self.saved[name] = data }
        prog.loadFileHook = { [unowned self] name in self.files[name] }
    }

    override func tearDown() {
        sim?.close()
        sim = nil
    }

    func testReadConfigurationTranscriptAndData() throws {
        try makeSim()
        ui.savePath = "/tmp/x/my_config"
        prog.readConfigButtonClick()

        XCTAssertEqual(saved["/tmp/x/my_config.bin"], Array(sim.eeprom[0..<K5.configSize]))
        XCTAssertEqual(ui.saveTitles, ["Save configuration file .."])
        let path = sim.slavePath
        var expected = ["", "'\(path)' opened at 38400 Baud", "", "Downloading configuration data from the radio ..",
                        "", "sending k5_hello ..", "", "  firmware version: 'k5_2.01.26'",
                        "has custom AES key: no", " is in lock screen: no", "         challenge: 42 3D 28 55", ""]
        for i in stride(from: 0, to: K5.configSize, by: 128) {
            expected.append(String(format: "read_config  offset %04X  len 128", i))
        }
        expected += ["read CONFIG complete", "", "'\(path)' closed", ""]
        XCTAssertEqual(ui.lines, expected)

        // exactly one hello and 58 reads, each with the fixed session id
        let sent = sim.clientPayloads()
        XCTAssertEqual(sent.first, "C>R 14 05 04 00 6A 39 57 64")
        XCTAssertEqual(sent.count, 1 + K5.configSize / 128)
        XCTAssertEqual(sent[1], "C>R 1B 05 08 00 00 00 80 00 6A 39 57 64")
        XCTAssertEqual(sent.last, "C>R 1B 05 08 00 80 1C 80 00 6A 39 57 64")
    }

    func testReadCalibration() throws {
        try makeSim()
        ui.savePath = "/tmp/x/cal.bin"
        prog.readCalibrationButtonClick()
        XCTAssertEqual(saved["/tmp/x/cal.bin"], Array(sim.eeprom[0x1E00..<0x2000]))
        XCTAssertTrue(ui.lines.contains("read CALIBRATION complete"))
        XCTAssertTrue(ui.lines.contains { $0.hasPrefix("0001F0  ") })   // always dumped
        XCTAssertEqual(sim.clientPayloads()[1], "C>R 1B 05 08 00 00 1E 80 00 6A 39 57 64")
    }

    func testWriteCalibrationWritesOnlyCalibArea() throws {
        try makeSim()
        let before = sim.eeprom
        let cal = (0..<512).map { UInt8(truncatingIfNeeded: 255 - $0) }
        files["/f/my_calibration.bin"] = cal
        ui.openPath = "/f/my_calibration.bin"
        prog.writeCalibrationButtonClick()
        XCTAssertTrue(ui.errors.isEmpty, "\(ui.errors)")
        XCTAssertEqual(Array(sim.eeprom[0x1E00..<0x2000]), cal)
        XCTAssertEqual(Array(sim.eeprom[0..<0x1E00]), Array(before[0..<0x1E00]))
        XCTAssertEqual(sim.rebootCount, 1)
        XCTAssertTrue(ui.lines.contains("write CALIBRATION complete"))
        let sent = sim.clientPayloads()
        XCTAssertEqual(sent.count, 1 + 4 + 1)  // hello, 4 writes, reboot
        XCTAssertTrue(sent[1].hasPrefix("C>R 1D 05 88 00 00 1E 80 01 6A 39 57 64 FF FE"))
        XCTAssertEqual(sent.last, "C>R DD 05 00 00")
    }

    func testWriteCalibrationRejectsWrongSize() throws {
        try makeSim()
        files["/f/c.bin"] = [UInt8](repeating: 1, count: 511)
        ui.openPath = "/f/c.bin"
        prog.writeCalibrationButtonClick()
        XCTAssertEqual(ui.errors, ["File size is invalid"])
        XCTAssertTrue(sim.clientPayloads().isEmpty)
    }

    func testWriteConfigurationRoundTripWithRealCRC() throws {
        try makeSim { $0.realCRC = true }
        let before = sim.eeprom
        let cfg = (0..<K5.configSize).map { UInt8(truncatingIfNeeded: $0 &* 13) }
        files["/f/my_config.bin"] = cfg
        ui.openPath = "/f/my_config.bin"
        prog.writeConfigButtonClick()
        XCTAssertTrue(ui.errors.isEmpty)
        XCTAssertTrue(ui.questions.isEmpty)
        XCTAssertEqual(Array(sim.eeprom[0..<K5.configSize]), cfg)
        XCTAssertEqual(Array(sim.eeprom[K5.configSize...]), Array(before[K5.configSize...]))   // calibration untouched
        XCTAssertEqual(sim.rebootCount, 1)
    }

    func testWriteConfigurationOversizeAsksAndDefaultsToNo() throws {
        try makeSim()
        files["/f/big.bin"] = [UInt8](repeating: 0x11, count: 0x2000)
        ui.openPath = "/f/big.bin"
        ui.answerYes = false
        prog.writeConfigButtonClick()
        XCTAssertEqual(ui.questions, ["File is larger than normal (0x1D00)\n\nStill upload ?"])
        XCTAssertTrue(sim.clientPayloads().isEmpty)

        files["/f/huge.bin"] = [UInt8](repeating: 0x11, count: 0x2001)
        ui.openPath = "/f/huge.bin"
        prog.writeConfigButtonClick()
        XCTAssertEqual(ui.errors, ["File is to large to be an config file (max 0x2000)"])
    }

    func testWriteConfigurationPartialLastBlockKeepsRadioBytes() throws {
        try makeSim()
        let before = sim.eeprom
        let cfg = [UInt8](repeating: 0x5A, count: 1100)   // 8 full blocks + 76 bytes
        files["/f/odd.bin"] = cfg
        ui.openPath = "/f/odd.bin"
        prog.writeConfigButtonClick()
        XCTAssertEqual(Array(sim.eeprom[0..<1100]), cfg)
        XCTAssertEqual(Array(sim.eeprom[1100...]), Array(before[1100...]))
    }

    func testFirmwareUploadPackedV1() throws {
        let raw = syntheticV1Image()   // 61412 bytes, like a Karina V1 image
        let packed = vendorPacked(raw, version: "*karina-21.08")
        try makeSim { $0.mode = .boot }
        files["/f/fw.bin"] = packed
        ui.openPath = "/f/fw.bin"
        prog.writeFirmwareButtonClick()
        XCTAssertTrue(ui.errors.isEmpty, "\(ui.errors)")
        XCTAssertEqual(sim.acceptedVersion, "*karina-21.08")
        XCTAssertEqual(Array(sim.flash[0..<raw.count]), raw)
        XCTAssertEqual(sim.flashWritten.count, raw.count)
        XCTAssertEqual(sim.rebootCount, 1)
        XCTAssertTrue(ui.lines.contains("Bootloader version '2.00.06'"))
        XCTAssertTrue(ui.lines.contains("firmware file version '*karina-21.08'"))
        XCTAssertTrue(ui.lines.contains("write FLASH complete"))

        let writes = sim.clientPayloads().filter { $0.hasPrefix("C>R 19 05") }
        XCTAssertEqual(writes.count, (raw.count + 255) / 256)
        // every block is a full 4+12+256 payload, max block address F0 (61412 -> 0xF000)
        XCTAssertTrue(writes.allSatisfy { $0.count == "C>R ".count + (272 * 3 - 1) })
        XCTAssertTrue(writes[0].hasPrefix("C>R 19 05 0C 01 8A 8D 9F 1D 00 00 F0 00 00 01 00 00"))
        XCTAssertTrue(writes.last!.hasPrefix(String(format: "C>R 19 05 0C 01 8A 8D 9F 1D EF 00 F0 00 %02X 00 00 00", raw.count - 0xEF00)))
    }

    func testFirmwareUploadStockVersionGetsStar() throws {
        let stock = vendorPacked(syntheticV1Image(size: 58690), version: "4.00.07")
        try makeSim { $0.mode = .boot; $0.keepBeacon = true }   // bootloader keeps beaconing
        files["/f/fw.bin"] = stock
        ui.openPath = "/f/fw.bin"
        prog.writeFirmwareButtonClick()
        XCTAssertTrue(ui.errors.isEmpty, "\(ui.errors)")
        XCTAssertEqual(sim.acceptedVersion, "*.00.07")
        let expect = FirmwareFile.process(stock).data
        XCTAssertEqual(Array(sim.flash[0..<expect.count]), expect)
        XCTAssertEqual(sim.rebootCount, 1)
    }

    func testFirmwareRefusedWhenRadioInUserMode() throws {
        let packed = vendorPacked(syntheticV1Image(), version: "*karina-21.08")
        try makeSim()   // user mode
        files["/f/fw.bin"] = packed
        ui.openPath = "/f/fw.bin"
        prog.writeFirmwareButtonClick()
        XCTAssertEqual(ui.lines.last, "error: radio is not in firmware update mode - turn the radio off, then back on whilst pressing the PTT")
        XCTAssertFalse(sim.clientPayloads().contains { $0.hasPrefix("C>R 19 05") || $0.hasPrefix("C>R 30 05") })
    }

    func testFirmwareRejectsFileThatRunsIntoBootloader() throws {
        try makeSim { $0.mode = .boot }
        var img = [UInt8](repeating: 0, count: 0xF001)
        img[3] = 0x20
        files["/f/fw.bin"] = img
        ui.openPath = "/f/fw.bin"
        prog.writeFirmwareButtonClick()
        XCTAssertEqual(ui.errors, ["File runs into bootloader area (0xF000)\n\nUpload cancelled"])
        XCTAssertTrue(sim.clientPayloads().isEmpty)
    }

    func testReadConfigInBootloaderModeIsRefused() throws {
        try makeSim { $0.mode = .boot }
        prog.readConfigButtonClick()
        XCTAssertEqual(ui.lines.last, "error: radio is in firmware update mode - turn the radio off, then back on whilst NOT pressing the PTT")
        XCTAssertTrue(ui.saveTitles.isEmpty)
    }

    func testRadioNotDetected() throws {
        try makeSim { $0.silent = true }
        prog.readCalibrationButtonClick()
        XCTAssertEqual(ui.lines.last, "radio not detected")
        XCTAssertEqual(sim.clientPayloads().count, 2)   // two hello tries
    }

    func testFetchRadioDetails() throws {
        try makeSim { $0.mode = .boot }
        prog.serialPortComboBoxSelect()
        XCTAssertEqual(ui.lines.last, "radio is in firmware update mode")

        sim.close()
        try makeSim()
        prog.serialPortComboBoxSelect()
        XCTAssertEqual(ui.lines.last, "error: radio is in user mode")
    }

    func testVerbose2ShowsTxDump() throws {
        try makeSim()
        prog.verbose = 2
        ui.savePath = "/tmp/x/cal"
        prog.readCalibrationButtonClick()
        XCTAssertTrue(ui.lines.contains("tx crc_ok 1"))
        XCTAssertTrue(ui.lines.contains { $0.hasPrefix("tx obfuscated [ 16] AB CD 08 00 ") })
        XCTAssertTrue(ui.lines.contains { $0.hasPrefix("tx clear      [  8]             14 05 04 00 6A 39 57 64 - ") }, "hello")
    }

    func testEscapeAbortsWrite() throws {
        try makeSim { $0.responseDelayMs = 10 }
        files["/f/c.bin"] = [UInt8](repeating: 0x33, count: K5.configSize)
        ui.openPath = "/f/c.bin"
        let done = expectation(description: "done")
        DispatchQueue.global().async {
            self.prog.writeConfigButtonClick()
            done.fulfill()
        }
        usleep(150_000)
        prog.port.requestAbort()
        wait(for: [done], timeout: 10)
        XCTAssertTrue(ui.lines.contains { $0.hasPrefix("error: k5_write_eeprom() [0]") }, "\(ui.lines.suffix(5))")
        XCTAssertFalse(prog.connected)
        XCTAssertEqual(sim.rebootCount, 0)
    }
}
