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

import Foundation
import Darwin
import K5Core

/// UV-K5 radio simulator on a pseudo terminal, used to test K5K1 Prog.
///
/// Behaviour follows the stock DP32G030 firmware/bootloader as seen by k5prog:
/// user mode answers 0x0514/0x051B/0x051D/0x0527/0x0529/0x05DD, bootloader mode
/// beacons 0x0518 and accepts 0x0530 + 0x0519.
///
/// A bootloader version starting with "7" switches the bootloader to the UV-K5 V3 /
/// UV-K1 (PY32F071) protocol: 0x0530 carries 4 version chars, 0x0519 carries
/// stamp/page/page-count, 0x051A answers stamp/page/error, and the bootloader starts
/// the firmware by itself after the last page.
public final class RadioSim {
    public enum Mode: String { case user, boot }

    public struct Options {
        public var mode: Mode = .user
        public var firmwareVersion = "k5_2.01.26"
        public var bootloaderVersion = "2.00.06"
        public var beaconIntervalMs = 500
        /// Keep beaconing 0x0518 during the firmware upload (stress test).
        public var keepBeacon = false
        /// Send a real CRC instead of the stock 0xFFFF filler.
        public var realCRC = false
        /// Enforce the session id given in hello like the stock firmware.
        public var checkSession = true
        /// Do not answer at all (radio switched off).
        public var silent = false
        /// Artificial processing delay per command (ms).
        public var responseDelayMs = 0
        public var adcVoltage: UInt16 = 0x07AC
        public var rssi: (UInt16, UInt8, UInt8) = (0x008E, 0x50, 0x42)
        /// PY32 bootloader fault injection (page indexes, 0-based).
        public var failPagesOnce: Set<Int> = []
        public var failPagesAlways: Set<Int> = []
        public var dropPagesOnce: Set<Int> = []
        /// PY32: refuse 0x0519 until a 0x0530 handshake was received.
        public var py32RequireHandshake = true
        public init() {}
        public var isPY32: Bool { bootloaderVersion.hasPrefix("7") }
    }

    public private(set) var options: Options
    public var eeprom: [UInt8]
    public var flash: [UInt8]
    public private(set) var flashWritten = IndexSet()
    public private(set) var log: [String] = []
    public private(set) var rebootCount = 0
    public private(set) var acceptedVersion: String?
    /// PY32: 0x0530 messages received, pages written in order, page count announced.
    public private(set) var py32Handshakes = 0
    public private(set) var py32PagesWritten: [Int] = []
    public private(set) var py32PageCount = 0
    public private(set) var py32Completed = false
    private var py32Stamp: [UInt8]?
    private var py32Failed: Set<Int> = []
    private var py32Dropped: Set<Int> = []
    public private(set) var masterFD: Int32 = -1
    public private(set) var slaveFD: Int32 = -1
    public private(set) var slavePath = ""

    private var mode: Mode
    private var session: [UInt8]?
    private var versionAccepted = false
    private var rxbuf: [UInt8] = []
    private var lastBeacon = Date.distantPast
    private let lock = NSLock()
    private var running = false
    private var thread: Thread?
    public var onEvent: ((String) -> Void)?

    public init(options: Options, eeprom: [UInt8]? = nil) {
        self.options = options
        self.mode = options.mode
        self.eeprom = eeprom ?? (0..<0x2000).map { UInt8(truncatingIfNeeded: ($0 * 7 + 3) ^ ($0 >> 8)) }
        if self.eeprom.count < 0x2000 { self.eeprom += [UInt8](repeating: 0xFF, count: 0x2000 - self.eeprom.count) }
        self.flash = [UInt8](repeating: 0xFF, count: options.isPY32 ? K5.py32FlashSize : K5.maxFlashSize)
    }

    /// Opens the pty pair. Returns the slave path (e.g. /dev/ttys012).
    public func openPTY() throws -> String {
        var m: Int32 = -1, s: Int32 = -1
        guard openpty(&m, &s, nil, nil, nil) == 0 else { throw NSError(domain: "pty", code: Int(errno)) }
        var t = termios()
        tcgetattr(s, &t)
        cfmakeraw(&t)
        tcsetattr(s, TCSANOW, &t)
        let fl = fcntl(m, F_GETFL)
        _ = fcntl(m, F_SETFL, fl | O_NONBLOCK)
        masterFD = m
        slaveFD = s
        slavePath = String(cString: ttyname(s))
        return slavePath
    }

    public func start() {
        running = true
        let t = Thread { [weak self] in self?.loop() }
        t.name = "RadioSim"
        thread = t
        t.start()
    }

    public func stop() {
        lock.lock(); running = false; lock.unlock()
        usleep(20_000)
    }

    public func close() {
        stop()
        if masterFD >= 0 { Darwin.close(masterFD); masterFD = -1 }
        if slaveFD >= 0 { Darwin.close(slaveFD); slaveFD = -1 }
    }

    public func snapshotLog() -> [String] { lock.lock(); defer { lock.unlock() }; return log }

    /// Client->radio payloads only (what the programmer sent), in order.
    public func clientPayloads() -> [String] {
        snapshotLog().filter { $0.hasPrefix("C>R ") }
    }

    private func record(_ s: String) {
        lock.lock(); log.append(s); lock.unlock()
        onEvent?(s)
    }

    private var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    private func loop() {
        var buf = [UInt8](repeating: 0, count: 4096)
        while isRunning {
            let n = buf.withUnsafeMutableBytes { read(masterFD, $0.baseAddress, 4096) }
            if n > 0 {
                rxbuf += buf[0..<n]
                parse()
            } else {
                usleep(1000)
            }
            // the V1 bootloader stops beaconing once the version is accepted; the PY32 one
            // is modelled conservatively: it keeps beaconing until the first page arrives
            let beaconing = options.isPY32 ? py32Stamp == nil : !versionAccepted
            if mode == .boot && !options.silent && (beaconing || options.keepBeacon) {
                if Date().timeIntervalSince(lastBeacon) * 1000 >= Double(options.beaconIntervalMs) {
                    lastBeacon = Date()
                    send(beaconPayload(), quiet: true)
                }
            }
        }
    }

    private func beaconPayload() -> [UInt8] {
        // 18 05 20 00 01 02 02 06 1c 53 50 4a 37 47 ff 0f 8c 00 53 00 "2.00.06" ..
        var p: [UInt8] = [0x18, 0x05, 0x20, 0x00, 0x01, 0x02, 0x02, 0x06, 0x1C, 0x53, 0x50, 0x4A,
                          0x37, 0x47, 0xFF, 0x0F, 0x8C, 0x00, 0x53, 0x00]
        var v = Array(options.bootloaderVersion.utf8.prefix(16))
        v += [UInt8](repeating: 0, count: 16 - v.count)
        p += v
        return p
    }

    private func parse() {
        while rxbuf.count >= 8 {
            guard rxbuf[0] == 0xAB, rxbuf[1] == 0xCD else {
                record("ERR junk byte \(String(format: "%02X", rxbuf[0]))")
                rxbuf.removeFirst()
                continue
            }
            let len = Int(rxbuf[2]) | (Int(rxbuf[3]) << 8)
            let total = 4 + len + 4
            if rxbuf.count < total { return }
            let frame = Array(rxbuf[0..<total])
            rxbuf.removeFirst(total)
            guard frame[total - 2] == 0xDC, frame[total - 1] == 0xBA else {
                record("ERR bad footer " + HexDump.bytes(frame))
                continue
            }
            var body = Array(frame[4..<(4 + len + 2)])
            Codec.xorPayload(&body)
            let payload = Array(body[0..<len])
            let crc = UInt16(body[len]) | (UInt16(body[len + 1]) << 8)
            if crc != Codec.crc16(payload) {
                record("ERR bad crc " + HexDump.bytes(payload))
                continue
            }
            record("C>R " + HexDump.bytes(payload))
            if options.responseDelayMs > 0 { usleep(useconds_t(options.responseDelayMs * 1000)) }
            handle(payload)
        }
    }

    private func send(_ payload: [UInt8], quiet: Bool = false) {
        var body = payload
        if options.realCRC {
            let c = Codec.crc16(payload)
            body += [UInt8(c & 0xFF), UInt8(c >> 8)]
        } else {
            body += [0xFF, 0xFF]
        }
        Codec.xorPayload(&body)
        let frame: [UInt8] = [0xAB, 0xCD, UInt8(payload.count & 0xFF), UInt8(payload.count >> 8)] + body + [0xDC, 0xBA]
        _ = frame.withUnsafeBytes { write(masterFD, $0.baseAddress, frame.count) }
        if !quiet { record("R>C " + HexDump.bytes(payload)) }
    }

    private func le16(_ p: [UInt8], _ i: Int) -> Int { Int(p[i]) | (Int(p[i + 1]) << 8) }

    private func handle(_ p: [UInt8]) {
        guard p.count >= 4, !options.silent else { return }
        let cmd = le16(p, 0)

        if mode == .boot && options.isPY32 {
            handlePY32(cmd, p)
            return
        }

        if mode == .boot {
            switch cmd {
            case 0x0530:
                let ver = Array(p[4..<min(p.count, 20)])
                let v = ver.prefix(while: { $0 != 0 })
                let s = String(decoding: v, as: UTF8.self)
                let bl = Array(options.bootloaderVersion.utf8)
                if let f = v.first, f == UInt8(ascii: "*") || (!bl.isEmpty && f == bl[0]) {
                    versionAccepted = true
                    acceptedVersion = s
                    record("EVT version accepted '\(s)'")
                    send(beaconPayload())
                } else {
                    record("EVT version refused '\(s)'")
                }
            case 0x0519:
                guard versionAccepted, p.count >= 16 + 1 else { record("EVT write refused"); return }
                guard p[4] == 0x8A, p[5] == 0x8D, p[6] == 0x9F, p[7] == 0x1D else {
                    send([0x1A, 0x05, 0x08, 0x00, 0, 0, 0, 0, 0, 0, 0x01, 0x00]); return
                }
                let offset = (Int(p[8]) << 8) | Int(p[9])
                let len = le16(p, 12)
                guard len <= 256, p.count >= 16 + len, offset + len <= K5.flashSize else {
                    send([0x1A, 0x05, 0x08, 0x00, 0, 0, 0, 0, 0, 0, 0x01, 0x00]); return
                }
                flash.replaceSubrange(offset..<(offset + len), with: p[16..<(16 + len)])
                flashWritten.insert(integersIn: offset..<(offset + len))
                send([0x1A, 0x05, 0x08, 0x00, 0x8A, 0x8D, 0x9F, 0x1D, p[8], p[9], 0x00, 0x00])
            case 0x05DD:
                rebootCount += 1
                record("EVT reboot")
                mode = .user
                versionAccepted = false
                session = nil
            default:
                record("EVT ignored in bootloader")
            }
            return
        }

        switch cmd {
        case 0x0514:
            session = Array(p[4..<8])
            var r: [UInt8] = [0x15, 0x05, 0x24, 0x00]
            var v = Array(options.firmwareVersion.utf8.prefix(16))
            v += [UInt8](repeating: 0, count: 16 - v.count)
            r += v
            r += [0x00, 0x00, 0x00, 0x00]                         // custom AES key, lock screen, padding
            r += [0x42, 0x3D, 0x28, 0x55, 0x36, 0x49, 0xD8, 0x27, // challenge
                  0x51, 0xDF, 0x0C, 0x54, 0x99, 0xDB, 0x2B, 0x7F]
            send(r)
        case 0x051B:
            guard sessionOK(p, at: 8) else { return }
            let off = le16(p, 4), len = Int(p[6])
            guard off + len <= eeprom.count else { return }
            var r: [UInt8] = [0x1C, 0x05, UInt8((4 + len) & 0xFF), UInt8((4 + len) >> 8), p[4], p[5], p[6], 0]
            r += eeprom[off..<(off + len)]
            send(r)
        case 0x051D:
            guard sessionOK(p, at: 8) else { return }
            let off = le16(p, 4), len = Int(p[6])
            guard p.count >= 12 + len, off + len <= eeprom.count else { record("EVT bad write"); return }
            eeprom.replaceSubrange(off..<(off + len), with: p[12..<(12 + len)])
            send([0x1E, 0x05, 0x02, 0x00, p[4], p[5]])
        case 0x0527:   // stock CMD_0527() takes no timestamp
            let (rs, n, g) = options.rssi
            send([0x28, 0x05, 0x04, 0x00, UInt8(rs & 0xFF), UInt8(rs >> 8), n, g])
        case 0x0529:   // stock CMD_0529() takes no timestamp
            let v = options.adcVoltage
            send([0x2A, 0x05, 0x04, 0x00, UInt8(v & 0xFF), UInt8(v >> 8), 0x00, 0x00])
        case 0x05DD:
            rebootCount += 1
            session = nil
            record("EVT reboot")
        default:
            record("EVT unknown command")
        }
    }

    private func handlePY32(_ cmd: Int, _ p: [UInt8]) {
        switch cmd {
        case 0x0530:
            let v = Array(p[4..<min(p.count, 8)])
            let expect = Array(options.bootloaderVersion.utf8.prefix(4))
            let s = String(decoding: v.prefix(while: { $0 != 0 }), as: UTF8.self)
            guard p.count == 8, le16(p, 2) == 4, v == expect else {
                record("EVT py32 handshake refused '\(s)'"); return
            }
            py32Handshakes += 1
            versionAccepted = true
            acceptedVersion = s
            record("EVT py32 handshake '\(s)' #\(py32Handshakes)")
        case 0x0519:
            guard versionAccepted || !options.py32RequireHandshake, p.count == 4 + 268, le16(p, 2) == 268 else {
                record("EVT py32 write refused"); return
            }
            let stamp = Array(p[4..<8])
            let page = le16(p, 8), count = le16(p, 10)
            func answer(_ err: Int) {
                send([0x1A, 0x05, 0x08, 0x00] + stamp + [UInt8(page & 0xFF), UInt8(page >> 8), UInt8(err & 0xFF), UInt8(err >> 8)])
            }
            if py32Stamp == nil {
                guard page == 0, count > 0, count * K5.py32PageSize <= K5.py32FlashSize else { answer(3); return }
                py32Stamp = stamp
                py32PageCount = count
            }
            guard stamp == py32Stamp, count == py32PageCount else { answer(1); return }
            let next = py32PagesWritten.last.map { $0 + 1 } ?? 0
            guard page == next || page == next - 1, Array(p[12..<16]) == [0, 0, 0, 0] else { answer(2); return }
            if options.dropPagesOnce.contains(page) && !py32Dropped.contains(page) {
                py32Dropped.insert(page); record("EVT py32 page \(page) dropped"); return
            }
            if options.failPagesAlways.contains(page) || (options.failPagesOnce.contains(page) && !py32Failed.contains(page)) {
                py32Failed.insert(page); answer(5); return
            }
            let off = page * K5.py32PageSize
            flash.replaceSubrange(off..<(off + K5.py32PageSize), with: p[16..<(16 + K5.py32PageSize)])
            flashWritten.insert(integersIn: off..<(off + K5.py32PageSize))
            if page == next { py32PagesWritten.append(page) }
            answer(0)
            if page == count - 1 {
                py32Completed = true
                rebootCount += 1
                record("EVT py32 firmware complete, starting it")
                mode = .user
                versionAccepted = false
                session = nil
            }
        case 0x05DD:
            record("EVT py32 0x05DD ignored")
        default:
            record("EVT ignored in bootloader")
        }
    }

    private func sessionOK(_ p: [UInt8], at i: Int) -> Bool {
        guard options.checkSession else { return true }
        guard p.count >= i + 4, let s = session, Array(p[i..<(i + 4)]) == s else {
            record("EVT session mismatch")
            return false
        }
        return true
    }
}
