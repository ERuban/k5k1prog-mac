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

import XCTest
@testable import K5Core
import K5Sim

/// Synthetic PY32F071 image (valid vector table, varied content). The tests use no
/// third-party firmware files.
func py32Image(size: Int, seed: Int = 0) -> [UInt8] {
    var img = (0..<size).map { UInt8(truncatingIfNeeded: ($0 &* (31 &+ seed)) ^ ($0 >> 7)) }
    img[0...7] = [0x00, 0x40, 0x00, 0x20, 0xC9, 0x0A, 0x01, 0x08][...]   // SP 0x20004000, reset 0x08010AC9
    return img
}

/// Synthetic DP32G030 (V1) image: reset vector 0x0000xxxx, passes the original looksPlain() test.
func syntheticV1Image(size: Int = 61412) -> [UInt8] {
    var img = (0..<size).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ 5) }
    img[0...15] = [0xF0, 0x3F, 0x00, 0x20, 0x0B, 0x01, 0x00, 0x00,
                   0xD5, 0x00, 0x00, 0x00, 0xD7, 0x00, 0x00, 0x00][...]
    return img
}

/// Quansheng vendor ".packed" encoding (inverse of FirmwareFile.process() / processPY32()).
func vendorPacked(_ raw: [UInt8], version: String) -> [UInt8] {
    var v = Array(version.utf8.prefix(16))
    v += [UInt8](repeating: 0, count: 16 - v.count)
    var d = Array(raw[0..<0x2000]) + v + Array(raw[0x2000...])
    Codec.xorFirmware(&d)
    let c = Codec.crc16(d)
    return d + [UInt8(c & 0xFF), UInt8(c >> 8)]
}

/// "C>R 19 05 0C 01 .." -> bytes
func payloadBytes(_ line: String) -> [UInt8] {
    line.dropFirst(4).split(separator: " ").map { UInt8($0, radix: 16)! }
}

final class PY32ImageTests: XCTestCase {
    func testSyntheticPackedRoundTrip() {
        let raw = py32Image(size: 76468)
        let p = FirmwareFile.processPY32(vendorPacked(raw, version: "*karina-21.08"))
        XCTAssertEqual(p, FirmwareFile.PY32Result(data: raw, unpacked: true, version: Array("*karina-21.08".utf8)))
        let v1 = syntheticV1Image()
        XCTAssertNil(FirmwareFile.processPY32(v1))
        XCTAssertNil(FirmwareFile.processPY32(vendorPacked(v1, version: "2.01.26")))
        XCTAssertFalse(FirmwareFile.process(v1).encrypted)
    }

    func testVectorTableRule() {
        var d = [UInt8](repeating: 0, count: 16)
        d[0...3] = [0x00, 0x40, 0x00, 0x20][...]   // SP 0x20004000
        d[4...7] = [0xC9, 0x0A, 0x01, 0x08][...]   // RV 0x08010AC9
        XCTAssertTrue(FirmwareFile.isPY32Image(d))
        d[4...7] = [0xC9, 0x0A, 0x00, 0x00][...]   // RV 0x00000AC9 (DP32G030)
        XCTAssertFalse(FirmwareFile.isPY32Image(d))
        d[4...7] = [0xC9, 0x0A, 0x00, 0x08][...]   // RV 0x08000AC9 (d[6] == 0: V1 looksPlain() alone would take it)
        XCTAssertTrue(FirmwareFile.isPY32Image(d))
        XCTAssertFalse(FirmwareFile.isPY32Image([0x00, 0x40, 0x00]))
    }

    func testBootloaderVersionCompare() {
        XCTAssertTrue(FirmwareFile.bootloaderAtLeast("7.00.07", "7.00.07"))
        XCTAssertTrue(FirmwareFile.bootloaderAtLeast("7.03.01", "7.00.07"))
        XCTAssertTrue(FirmwareFile.bootloaderAtLeast("7.00.10", "7.00.07"))
        XCTAssertFalse(FirmwareFile.bootloaderAtLeast("7.00.06", "7.00.07"))
        XCTAssertFalse(FirmwareFile.bootloaderAtLeast("2.00.06", "7.00.07"))
    }
}

final class PY32FlashTests: XCTestCase {
    var sim: RadioSim!
    var prog: K5Programmer!
    var ui: RecordingUI!
    var files: [String: [UInt8]] = [:]

    func makeSim(bootloader: String = "7.00.07", _ configure: (inout RadioSim.Options) -> Void = { _ in }) throws {
        var o = RadioSim.Options()
        o.mode = .boot
        o.bootloaderVersion = bootloader
        o.beaconIntervalMs = 100
        configure(&o)
        sim = RadioSim(options: o)
        let path = try sim.openPTY()
        sim.start()
        prog = K5Programmer()
        ui = RecordingUI()
        prog.ui = ui
        prog.selectedPort = path
        prog.selectedSpeed = 38400
        prog.verbose = 1
        prog.loadFileHook = { [unowned self] name in self.files[name] }
    }

    override func tearDown() {
        sim?.close()
        sim = nil
    }

    func k1Raw() throws -> [UInt8] {
        py32Image(size: 76468)   // size of a Karina K1 image: 299 pages, last one 180 bytes
    }

    func flash(_ image: [UInt8]) {
        files["/f/fw.bin"] = image
        ui.openPath = "/f/fw.bin"
        prog.writeFirmwareButtonClick()
    }

    var pagePayloads: [[UInt8]] { sim.clientPayloads().filter { $0.hasPrefix("C>R 19 05") }.map(payloadBytes) }
    var handshakePayloads: [String] { sim.clientPayloads().filter { $0.hasPrefix("C>R 30 05") } }

    /// Every page message must match the PY32 bootloader protocol byte for byte.
    func assertWireFormat(_ image: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
        let pages = (image.count + 255) / 256
        let msgs = pagePayloads
        XCTAssertEqual(msgs.count, pages, file: file, line: line)
        let stamp = Array(msgs[0][4..<8])
        for (i, m) in msgs.enumerated() {
            XCTAssertEqual(m.count, 272, file: file, line: line)
            XCTAssertEqual(Array(m[0..<4]), [0x19, 0x05, 0x0C, 0x01], file: file, line: line)
            XCTAssertEqual(Array(m[4..<8]), stamp, "same stamp in every page", file: file, line: line)
            XCTAssertEqual(Int(m[8]) | Int(m[9]) << 8, i, "page index LE16", file: file, line: line)
            XCTAssertEqual(Int(m[10]) | Int(m[11]) << 8, pages, "page count LE16", file: file, line: line)
            XCTAssertEqual(Array(m[12..<16]), [0, 0, 0, 0], file: file, line: line)
            let off = i * 256, len = min(256, image.count - off)
            XCTAssertEqual(Array(m[16..<(16 + len)]), Array(image[off..<(off + len)]), file: file, line: line)
            XCTAssertTrue(m[(16 + len)...].allSatisfy { $0 == 0 }, "last page padded with 00", file: file, line: line)
        }
        XCTAssertEqual(handshakePayloads, Array(repeating: "C>R 30 05 04 00 " + HexDump.bytes(Array(sim.options.bootloaderVersion.utf8.prefix(4))), count: 3), file: file, line: line)
        XCTAssertFalse(sim.clientPayloads().contains { $0.hasPrefix("C>R DD 05") }, "no reboot command", file: file, line: line)
    }

    func assertFlashed(_ image: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
        let pages = (image.count + 255) / 256
        XCTAssertTrue(ui.errors.isEmpty, "\(ui.errors)", file: file, line: line)
        XCTAssertTrue(sim.py32Completed, "\(ui.lines.suffix(8))", file: file, line: line)
        XCTAssertEqual(sim.py32PagesWritten, Array(0..<pages), file: file, line: line)
        XCTAssertEqual(Array(sim.flash[0..<image.count]), image, file: file, line: line)
        XCTAssertTrue(sim.flash[image.count..<(pages * 256)].allSatisfy { $0 == 0 }, file: file, line: line)
        XCTAssertTrue(sim.flash[(pages * 256)...].allSatisfy { $0 == 0xFF }, file: file, line: line)
        XCTAssertTrue(ui.lines.contains("write FLASH complete"), file: file, line: line)
        XCTAssertFalse(prog.connected, file: file, line: line)
    }

    func testK1RawUpload() throws {
        let raw = try k1Raw()
        try makeSim()
        flash(raw)
        assertFlashed(raw)
        assertWireFormat(raw)
        XCTAssertEqual(sim.py32Handshakes, 3)
        XCTAssertEqual(sim.acceptedVersion, "7.00")
        XCTAssertEqual(sim.rebootCount, 1)
        XCTAssertTrue(ui.lines.contains("Bootloader version '7.00.07'"))
        XCTAssertTrue(ui.lines.contains("firmware file is for UV-K5 V3 / UV-K1 (PY32F071, bootloader 7.xx)"))
        XCTAssertTrue(ui.lines.contains("sending bootloader version '7.00' .."))
        XCTAssertTrue(ui.lines.contains("write_flash  page   1/299  offset 00000  len 256"))
        XCTAssertTrue(ui.lines.contains("write_flash  page 299/299  offset 12A00  len 180"))
        XCTAssertFalse(ui.lines.contains { $0.hasPrefix("error") }, "\(ui.lines.filter { $0.hasPrefix("error") })")
    }

    func testK1PackedUpload() throws {
        let raw = try k1Raw()
        let packed = vendorPacked(raw, version: "*karina-21.08")
        try makeSim(bootloader: "7.03.02")
        flash(packed)
        assertFlashed(raw)
        assertWireFormat(raw)
        XCTAssertTrue(ui.lines.contains("firmware file de-obfuscated"))
        XCTAssertTrue(ui.lines.contains("firmware file version '*karina-21.08'"))
        XCTAssertEqual(sim.acceptedVersion, "7.03")
    }

    func testK5V3RawUpload() throws {
        let raw = py32Image(size: 76532, seed: 1)
        try makeSim()
        flash(raw)
        assertFlashed(raw)
        assertWireFormat(raw)
    }

    func testBeaconsDuringProgrammingAreIgnored() throws {
        let raw = try k1Raw()
        try makeSim { $0.keepBeacon = true; $0.beaconIntervalMs = 20 }
        flash(raw)
        assertFlashed(raw)
        assertWireFormat(raw)
    }

    func testRetriesRejectedAndLostPages() throws {
        let raw = try k1Raw()
        try makeSim { $0.failPagesOnce = [0, 7, 298]; $0.dropPagesOnce = [100] }
        flash(raw)
        assertFlashed(raw)
        XCTAssertTrue(ui.lines.contains("error: page 1 rejected [5], retry 1/3"))
        XCTAssertTrue(ui.lines.contains("error: page 8 rejected [5], retry 1/3"))
        XCTAssertTrue(ui.lines.contains("error: page 299 rejected [5], retry 1/3"))
        XCTAssertTrue(ui.lines.contains("error: no answer for page 101, retry 1/3"))
        let idx = pagePayloads.map { Int($0[8]) | Int($0[9]) << 8 }
        XCTAssertEqual(idx.count, 299 + 4)
        XCTAssertEqual(idx.filter { $0 == 7 }.count, 2)
        XCTAssertEqual(idx.filter { $0 == 100 }.count, 2)
    }

    func testGivesUpAfterThreeRetries() throws {
        let raw = try k1Raw()
        try makeSim { $0.failPagesAlways = [10] }
        flash(raw)
        XCTAssertFalse(sim.py32Completed)
        XCTAssertEqual(pagePayloads.filter { Int($0[8]) == 10 }.count, 4, "1 try + 3 retries")
        XCTAssertTrue(ui.lines.contains("error: page 11 rejected [5], retry 3/3"))
        XCTAssertTrue(ui.lines.contains("error: k5_write_flash() [-5]"), "\(ui.lines.suffix(6))")
        XCTAssertFalse(ui.lines.contains("write FLASH complete"))
        XCTAssertFalse(prog.connected)
    }

    func testK1FileRefusedByV1Bootloader() throws {
        let raw = try k1Raw()
        try makeSim(bootloader: "2.00.06")
        flash(raw)
        XCTAssertEqual(ui.lines.last, "error: bootloader '2.00.06' is not a UV-K5 V3 / UV-K1 bootloader (7.xx), this firmware file is for UV-K5 V3 / UV-K1 - upload cancelled")
        XCTAssertTrue(handshakePayloads.isEmpty)
        XCTAssertTrue(pagePayloads.isEmpty)
        XCTAssertTrue(sim.flashWritten.isEmpty)
    }

    func testV1FileRefusedByPY32Bootloader() throws {
        let v1 = syntheticV1Image()
        try makeSim()
        flash(v1)
        XCTAssertEqual(ui.lines.last, "error: bootloader '7.00.07' is a UV-K5 V3 / UV-K1 bootloader, this firmware file is for UV-K5 V1 / K6 - upload cancelled")
        XCTAssertTrue(handshakePayloads.isEmpty)
        XCTAssertTrue(pagePayloads.isEmpty)
        XCTAssertTrue(sim.flashWritten.isEmpty)
    }

    func testV2BootloaderRefusesV1File() throws {
        try makeSim(bootloader: "1.02.01")
        flash(syntheticV1Image())
        XCTAssertEqual(ui.lines.last, "error: bootloader '1.02.01' is a UV-K5 V2 / K6 V2 (PY32F030) bootloader, firmware upload to this radio is not supported - upload cancelled")
        XCTAssertFalse(sim.clientPayloads().contains { $0.hasPrefix("C>R 30 05") || $0.hasPrefix("C>R 19 05") })
        XCTAssertTrue(sim.flashWritten.isEmpty)
        XCTAssertEqual(ui.errors, ["This radio is a UV-K5 V2 / K6 V2 (bootloader 1.02.01, PY32F030).\n\nFirmware upload to this radio is not supported. Nothing was written."])
    }

    func testV2BootloaderRefusesPY32File() throws {
        try makeSim(bootloader: "1.01.07")
        flash(try k1Raw())
        XCTAssertEqual(ui.lines.last, "error: bootloader '1.01.07' is a UV-K5 V2 / K6 V2 (PY32F030) bootloader, firmware upload to this radio is not supported - upload cancelled")
        XCTAssertEqual(ui.errors.count, 1)
        XCTAssertTrue(handshakePayloads.isEmpty)
        XCTAssertTrue(pagePayloads.isEmpty)
        XCTAssertTrue(sim.flashWritten.isEmpty)
    }

    func testOldPY32BootloaderRefused() throws {
        let raw = try k1Raw()
        try makeSim(bootloader: "7.00.06")
        flash(raw)
        XCTAssertEqual(ui.lines.last, "error: bootloader '7.00.06' is too old, 7.00.07 or newer is needed - upload cancelled")
        XCTAssertTrue(handshakePayloads.isEmpty)
        XCTAssertTrue(pagePayloads.isEmpty)
    }

    func testRadioInUserModeIsRefused() throws {
        let raw = try k1Raw()
        try makeSim { $0.mode = .user }
        flash(raw)
        XCTAssertEqual(ui.lines.last, "error: radio is not in firmware update mode - turn the radio off, then back on whilst pressing the PTT")
        XCTAssertTrue(pagePayloads.isEmpty)
    }

    func testTooLargeImageRefusedBeforeConnecting() throws {
        try makeSim()
        var img = [UInt8](repeating: 0, count: K5.py32FlashSize + 1)
        img[0...7] = [0x00, 0x40, 0x00, 0x20, 0x01, 0x29, 0x00, 0x08][...]
        flash(img)
        XCTAssertEqual(ui.errors, ["File is to large for a UV-K5 V3 / UV-K1 firmware (max 0x1D800)"])
        XCTAssertTrue(sim.clientPayloads().isEmpty)
        XCTAssertFalse(ui.lines.contains { $0.contains("opened at") })
    }

    func testMaximumSizeImageFits() throws {
        try makeSim()
        var img = (0..<K5.py32FlashSize).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
        img[0...7] = [0x00, 0x40, 0x00, 0x20, 0x01, 0x29, 0x00, 0x08][...]
        flash(img)
        assertFlashed(img)
        XCTAssertEqual(pagePayloads.count, 472)
    }

    func testEscapeAbortsFlash() throws {
        let raw = try k1Raw()
        try makeSim { $0.responseDelayMs = 5 }
        let done = expectation(description: "done")
        files["/f/fw.bin"] = raw
        ui.openPath = "/f/fw.bin"
        DispatchQueue.global().async {
            self.prog.writeFirmwareButtonClick()
            done.fulfill()
        }
        let deadline = Date().addingTimeInterval(10)
        while pagePayloads.count < 20 && Date() < deadline { usleep(10_000) }
        prog.port.requestAbort()
        wait(for: [done], timeout: 15)
        XCTAssertFalse(sim.py32Completed)
        XCTAssertTrue(ui.lines.contains { $0.hasPrefix("error: k5_write_flash() [0]") }, "\(ui.lines.suffix(5))")
        XCTAssertFalse(prog.connected)
    }
}
