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

final class CodecTests: XCTestCase {
    func testCRC16XModem() {
        XCTAssertEqual(Codec.crc16(Array("123456789".utf8)), 0x31C3)
        XCTAssertEqual(Codec.crc16([UInt8]()), 0)
    }

    func testObfuscateMatchesOriginalLayout() {
        // hello: 14 05 04 00 6A 39 57 64
        let payload: [UInt8] = [0x14, 0x05, 0x04, 0x00] + K5.sessionID
        let (frame, crc) = Codec.obfuscate(payload)
        XCTAssertEqual(frame.count, payload.count + 8)
        XCTAssertEqual(Array(frame[0..<4]), [0xAB, 0xCD, 0x08, 0x00])
        XCTAssertEqual(Array(frame[(frame.count - 2)...]), [0xDC, 0xBA])
        var body = Array(frame[4..<(frame.count - 2)])
        Codec.xorPayload(&body)
        XCTAssertEqual(Array(body[0..<8]), payload)
        XCTAssertEqual(UInt16(body[8]) | (UInt16(body[9]) << 8), crc)
        XCTAssertEqual(crc, Codec.crc16(payload))
    }

    func testFirmwareXorIsInvolution() {
        var d = (0..<1000).map { UInt8($0 & 0xFF) }
        let orig = d
        Codec.xorFirmware(&d)
        XCTAssertNotEqual(d, orig)
        Codec.xorFirmware(&d)
        XCTAssertEqual(d, orig)
    }
}

final class RxEngineTests: XCTestCase {
    private func radioFrame(_ payload: [UInt8], realCRC: Bool = false, corruptCRC: Bool = false) -> [UInt8] {
        var body = payload
        if realCRC {
            var c = Codec.crc16(payload)
            if corruptCRC { c ^= 0x0101 }
            body += [UInt8(c & 0xFF), UInt8(c >> 8)]
        } else {
            body += [0xFF, 0xFF]
        }
        Codec.xorPayload(&body)
        return [0xAB, 0xCD, UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)] + body + [0xDC, 0xBA]
    }

    func testExtractsPacketWithFillerCRC() {
        var rx = RxEngine()
        rx.append(radioFrame([0x2A, 0x05, 0x04, 0x00, 0xAC, 0x07, 0x00, 0x00])[...])
        rx.extract()
        XCTAssertEqual(rx.queue.count, 1)
        XCTAssertEqual(Array(rx.queue[0][0..<8]), [0x2A, 0x05, 0x04, 0x00, 0xAC, 0x07, 0x00, 0x00])
        XCTAssertEqual(rx.queue[0].count, 10)   // payload + 2 CRC bytes, like the original
        XCTAssertEqual(rx.wr, 0)
    }

    func testRealCRCAcceptedAndBadCRCDropped() {
        var rx = RxEngine()
        rx.append(radioFrame([0x28, 0x05, 0x04, 0x00, 1, 2, 3, 4], realCRC: true)[...])
        rx.append(radioFrame([0x28, 0x05, 0x04, 0x00, 1, 2, 3, 4], realCRC: true, corruptCRC: true)[...])
        rx.extract()
        XCTAssertEqual(rx.queue.count, 1)
    }

    func testResyncAfterJunkAndSplitDelivery() {
        var rx = RxEngine()
        let f = radioFrame([0x1E, 0x05, 0x02, 0x00, 0x80, 0x00])
        rx.append(([0x00, 0x11, 0xAB, 0x22] + f[0..<5])[...])
        rx.extract()
        XCTAssertTrue(rx.queue.isEmpty)
        rx.append(f[5...])
        rx.extract()
        XCTAssertEqual(rx.queue.count, 1)
        XCTAssertEqual(Array(rx.queue[0][0..<6]), [0x1E, 0x05, 0x02, 0x00, 0x80, 0x00])
    }

    func testTooLongLengthAndBadFooterSlide() {
        var rx = RxEngine()
        rx.append([0xAB, 0xCD, 0xFF, 0x7F, 0, 0, 0, 0][...])   // len 0x7FFF > 270
        var bad = radioFrame([0x2A, 0x05, 0x00, 0x00])
        bad[bad.count - 1] = 0x00                              // broken footer
        rx.append(bad[...])
        rx.append(radioFrame([0x2A, 0x05, 0x00, 0x01])[...])
        rx.extract()
        XCTAssertEqual(rx.queue.count, 1)
        XCTAssertEqual(Array(rx.queue[0][0..<4]), [0x2A, 0x05, 0x00, 0x01])
    }

    func testQueueCappedAtFour() {
        var rx = RxEngine()
        for i in 0..<6 { rx.append(radioFrame([0x18, 0x05, 0, UInt8(i)])[...]) }
        rx.extract()
        XCTAssertEqual(rx.queue.count, 4)
        XCTAssertEqual(rx.wr, 0)
    }
}

final class FirmwareFileTests: XCTestCase {
    func testVersionFixups() {
        func v(_ fw: String, _ bl: String) -> String {
            String(decoding: FirmwareFile.versionForBootloader(firmware: Array(fw.utf8), bootloader: Array(bl.utf8)), as: UTF8.self)
        }
        XCTAssertEqual(v("4.00.07", "2.00.06"), "*.00.07")
        XCTAssertEqual(v("2.01.26", "2.00.06"), "2.01.26")
        XCTAssertEqual(v("*karina-21.08", "2.00.06"), "*karina-21.08")
        XCTAssertEqual(v("k5_2.01.26", "2.00.06"), "k5_2.01.26")
        XCTAssertEqual(v("", "2.00.06"), "*")
        XCTAssertEqual(v("4.00.07", ""), "*")
        XCTAssertEqual(v("5.00.01", "5.00.01"), "5.00.01")
    }

    func testMaxBlockAddr() {
        XCTAssertEqual(FirmwareFile.maxBlockAddr(firmwareSize: 61412), 0xF000)
        XCTAssertEqual(FirmwareFile.maxBlockAddr(firmwareSize: 0xE500), 0xE500)
        XCTAssertEqual(FirmwareFile.maxBlockAddr(firmwareSize: 0xE501), 0xE600)
        XCTAssertEqual(FirmwareFile.maxBlockAddr(firmwareSize: 58710), 0xE600)
    }

    func testVendorPackedV1ImageIsDecoded() {
        let raw = syntheticV1Image()
        let r = FirmwareFile.process(vendorPacked(raw, version: "*karina-21.08"))
        XCTAssertFalse(r.encrypted)
        XCTAssertTrue(r.deobfuscated)
        XCTAssertEqual(String(decoding: r.version ?? [], as: UTF8.self), "*karina-21.08")
        XCTAssertEqual(r.data, raw)

        let p = FirmwareFile.process(raw)
        XCTAssertFalse(p.encrypted)
        XCTAssertFalse(p.deobfuscated)
        XCTAssertNil(p.version)
        XCTAssertEqual(p.data, raw)
    }

    func testGarbageIsRejected() {
        let junk = (0..<5000).map { UInt8(truncatingIfNeeded: $0 * 31 + 7) }
        XCTAssertTrue(FirmwareFile.process(junk).encrypted)
    }
}

final class HexDumpTests: XCTestCase {
    func testFormatMatchesOriginal() {
        // from the comment in k5_hello(): 000000  15 05 24 00 6B 35 5F 32 2E 30 31 2E 32 36 00 00  ..$.k5_2.01.26..
        let d: [UInt8] = [0x15, 0x05, 0x24, 0x00, 0x6B, 0x35, 0x5F, 0x32, 0x2E, 0x30, 0x31, 0x2E, 0x32, 0x36, 0x00, 0x00,
                          0x51, 0xDF]
        let l = HexDump.lines(d)
        XCTAssertEqual(l.count, 2)
        XCTAssertEqual(l[0], "000000  15 05 24 00 6B 35 5F 32 2E 30 31 2E 32 36 00 00  ..$.k5_2.01.26..")
        XCTAssertTrue(l[1].hasPrefix("000010  51 DF "))
        XCTAssertEqual(l[1].count, 8 + 65)
    }
}

final class IniFileTests: XCTestCase {
    func testReadsWindowsIniAndWritesSameFormat() throws {
        let dir = NSTemporaryDirectory() + "k5ini-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let p = dir + "/K5K1Prog.ini"
        let win = "[MainForm]\r\nTop=-108\r\nLeft=-1544\r\nWidth=1552\r\nHeight=936\r\n[GUI]\r\nVerbose=1\r\n[SerialPort]\r\nName=COM6\r\nSpeed=38400\r\n"
        FileManager.default.createFile(atPath: p, contents: Data(win.utf8))
        let ini = IniFile(path: p)
        XCTAssertEqual(ini.readInteger("MainForm", "Top", 0), -108)
        XCTAssertEqual(ini.readInteger("mainform", "LEFT", 0), -1544)
        XCTAssertEqual(ini.readInteger("GUI", "Verbose", 9), 1)
        XCTAssertEqual(ini.readString("SerialPort", "Name", ""), "COM6")
        XCTAssertEqual(ini.readInteger("SerialPort", "Missing", 42), 42)

        let out = IniFile.fresh(path: p)
        out.writeInteger("MainForm", "Top", -108)
        out.writeInteger("MainForm", "Left", -1544)
        out.writeInteger("MainForm", "Width", 1552)
        out.writeInteger("MainForm", "Height", 936)
        out.writeInteger("GUI", "Verbose", 1)
        out.writeString("SerialPort", "Name", "COM6")
        out.writeInteger("SerialPort", "Speed", 38400)
        out.save()
        XCTAssertEqual(String(decoding: FileManager.default.contents(atPath: p)!, as: UTF8.self), win)
    }

    func testIniLocationFallsBackWhenAppFolderIsReadOnly() throws {
        let fm = FileManager.default
        let root = NSTemporaryDirectory() + "k5iniloc-\(UUID().uuidString)"
        let app = root + "/Applications", support = root + "/Support/K5K1 Prog"
        try fm.createDirectory(atPath: app, withIntermediateDirectories: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app)
            try? fm.removeItem(atPath: root)
        }
        // writable folder: next to the app, like the original
        XCTAssertEqual(IniFile.location(appDir: app, name: "K5K1Prog.ini", supportDir: support), app + "/K5K1Prog.ini")
        XCTAssertFalse(fm.fileExists(atPath: support))

        // read-only folder with an existing ini: fallback, seeded from that ini, and saving works
        fm.createFile(atPath: app + "/K5K1Prog.ini", contents: Data("[GUI]\r\nVerbose=2\r\n".utf8))
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: app)
        let p = IniFile.location(appDir: app, name: "K5K1Prog.ini", supportDir: support)
        XCTAssertEqual(p, support + "/K5K1Prog.ini")
        XCTAssertEqual(IniFile(path: p).readInteger("GUI", "Verbose", 0), 2)
        let out = IniFile.fresh(path: p)
        out.writeInteger("GUI", "Verbose", 3)
        XCTAssertTrue(out.save())
        XCTAssertEqual(IniFile(path: p).readInteger("GUI", "Verbose", 0), 3)
        // the seed is copied only once: later runs keep the fallback's own settings
        XCTAssertEqual(IniFile(path: IniFile.location(appDir: app, name: "K5K1Prog.ini", supportDir: support))
            .readInteger("GUI", "Verbose", 0), 3)

        // translocated path: always the fallback
        XCTAssertEqual(IniFile.location(appDir: root + "/AppTranslocation/X/d", name: "K5K1Prog.ini", supportDir: support),
                       support + "/K5K1Prog.ini")
    }
}
