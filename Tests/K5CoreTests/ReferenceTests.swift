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

/// Compares K5K1 Prog with the ORIGINAL k5prog-win v0.1.26 exe, using the transcripts
/// and radio logs it produced against the same RadioSim (Tests/Reference):
///
///   memo_<op>.txt   Memo1 text of the original after each button
///   win_*.log       everything the original sent to the simulated radio
///
/// Both programs must send byte-identical payloads in the same order and print the
/// same memo lines.
final class ReferenceTests: XCTestCase {
    static let refDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Reference")

    func ref(_ name: String) -> URL { ReferenceTests.refDir.appendingPathComponent(name) }

    /// Original memo text -> lines, without the "serial error:" timer lines of the recording setup
    /// (each followed by an empty line from the FormatMessage CRLF).
    func referenceMemo(_ name: String) throws -> [String] {
        let text = try String(contentsOf: ref("memo_\(name).txt"), encoding: .utf8)
        var lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var i = 0
        while i < lines.count {
            if lines[i].hasPrefix("serial error: ") {
                if i + 1 < lines.count && lines[i + 1].isEmpty { i += 1 }
                i += 1
                continue
            }
            out.append(lines[i])
            i += 1
        }
        lines = out
        while lines.last == "" { lines.removeLast() }
        return lines
    }

    func referencePayloads(_ log: String) throws -> [String] {
        try String(contentsOf: ref(log), encoding: .utf8)
            .components(separatedBy: "\n")
            .compactMap { l in l.range(of: "C>R ").map { String(l[$0.lowerBound...]) } }
    }

    func normalized(_ lines: [String], port: String) -> [String] {
        var l = lines.map { $0.replacingOccurrences(of: "'\(port)'", with: "'COM6'") }
        while l.last == "" { l.removeLast() }
        return l
    }

    func assertSameLines(_ mine: [String], _ theirs: [String], _ op: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(theirs.count, 10, "\(op): empty reference", file: file, line: line)
        if mine == theirs { return }
        let n = max(mine.count, theirs.count)
        for i in 0..<n {
            let a = i < mine.count ? mine[i] : "<none>"
            let b = i < theirs.count ? theirs[i] : "<none>"
            if a != b {
                XCTFail("\(op): first difference at line \(i): mac=\(a.debugDescription) win=\(b.debugDescription)", file: file, line: line)
                return
            }
        }
    }

    func testUserModeSessionMatchesOriginal() throws {
        guard FileManager.default.fileExists(atPath: ref("win_user.log").path) else { throw XCTSkip("no reference") }
        let seed = [UInt8](try Data(contentsOf: ref("eeprom_seed.bin")))
        let calibFile = Array(seed[0x1E00..<0x2000])
        let configFile = Array(seed[0..<K5.configSize])

        var o = RadioSim.Options()
        o.firmwareVersion = "*karina-21.08"
        let sim = RadioSim(options: o, eeprom: seed)
        let path = try sim.openPTY()
        sim.start()
        defer { sim.close() }

        let prog = K5Programmer()
        let ui = RecordingUI()
        prog.ui = ui
        prog.selectedPort = path
        prog.verbose = 1
        var saved: [String: [UInt8]] = [:]
        prog.saveFileHook = { saved[$0] = $1 }
        let files = ["C:\\k5\\29.01.26calib_sql.bin": calibFile, "C:\\k5\\Config-29.01.26.bin": configFile]
        prog.loadFileHook = { files[$0] }

        // start-up: WMInitGUI -> SerialPortComboBoxSelect()
        prog.serialPortComboBoxSelect()

        ui.savePath = "C:\\k5\\out_config.bin"
        prog.readConfigButtonClick()
        assertSameLines(normalized(ui.lines, port: path), try referenceMemo("readconfig"), "Read Configuration")
        XCTAssertEqual(saved["C:\\k5\\out_config.bin"], configFile)

        ui.savePath = "C:\\k5\\out_calib.bin"
        prog.readCalibrationButtonClick()
        assertSameLines(normalized(ui.lines, port: path), try referenceMemo("readcalib"), "Read Calibration")
        XCTAssertEqual(saved["C:\\k5\\out_calib.bin"], calibFile)

        ui.openPath = "C:\\k5\\29.01.26calib_sql.bin"
        prog.writeCalibrationButtonClick()
        assertSameLines(normalized(ui.lines, port: path), try referenceMemo("writecalib"), "Write Calibration")

        ui.openPath = "C:\\k5\\Config-29.01.26.bin"
        ui.lines.removeAll()   // the original memo still had the previous text: compare from "Loaded" on
        prog.writeConfigButtonClick()
        assertSameLines(normalized(ui.lines, port: path), try referenceMemo("writeconfig"), "Write Configuration")

        // byte-identical radio traffic, same order
        let mine = sim.clientPayloads()
        let theirs = try referencePayloads("win_user.log")
        XCTAssertEqual(theirs.count, 131)
        XCTAssertEqual(mine.count, theirs.count)
        for (i, (a, b)) in zip(mine, theirs).enumerated() where a != b {
            XCTFail("payload #\(i) differs:\nmac \(a)\nwin \(b)")
            break
        }
        // and the radio ends up in the same state
        let after = [UInt8](try Data(contentsOf: ref("win_user_eeprom_after.bin")))
        XCTAssertEqual(sim.eeprom, after)
    }

    func testVerbose3ReadCalibrationMatchesOriginal() throws {
        guard FileManager.default.fileExists(atPath: ref("win_v3.log").path) else { throw XCTSkip("no reference") }
        let seed = [UInt8](try Data(contentsOf: ref("eeprom_seed.bin")))
        var o = RadioSim.Options()
        o.firmwareVersion = "*karina-21.08"
        let sim = RadioSim(options: o, eeprom: seed)
        let path = try sim.openPTY()
        sim.start()
        defer { sim.close() }

        let prog = K5Programmer()
        let ui = RecordingUI()
        prog.ui = ui
        prog.selectedPort = path
        prog.verbose = 3
        var saved: [UInt8]?
        prog.saveFileHook = { _, d in saved = d }
        ui.savePath = "C:\\k5\\out_calib_v3.bin"
        prog.readCalibrationButtonClick()

        assertSameLines(normalized(ui.lines, port: path), try referenceMemo("readcalib_v3"), "Read Calibration verbose 3")
        XCTAssertEqual(sim.clientPayloads(), try referencePayloads("win_v3.log"))
        XCTAssertEqual(saved, Array(seed[0x1E00..<0x2000]))
    }
}
