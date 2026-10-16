// K5K1 Prog - macOS programmer for Quansheng UV-K5 / UV-K5 V3 / UV-K1 radios.
//
// Channel editor: channel layout and per-firmware value lists. The layout and the value
// tables follow the CHIRP drivers for these radios: the UV-K5 driver by Jacek Lipkowski
// SQ5BPF (https://github.com/sq5bpf/uvk5-reverse-engineering), the UV-K1 driver by Thibaut
// Berg (both in CHIRP, https://github.com/kk7ds/chirp), and Karina's CHIRP modules by M2Boo
// (based on the egzumer / JOC2 / F4HWN drivers). Those are GPLv2 or later.
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

// MARK: - value types

public enum ChannelTone: Equatable, Hashable, Codable {
    case none
    case ctcss(Double)                 // Hz, one of Channels.ctcssTones
    case dcs(Int, inverted: Bool)      // octal code as written (023 -> 23), one of Channels.dcsCodes

    public var label: String {
        switch self {
        case .none: return ""
        case .ctcss(let hz): return String(format: "%.1f", hz)
        case .dcs(let code, let inv): return String(format: "D%03d%@", code, inv ? "I" : "N")
        }
    }
}

public enum Duplex: String, CaseIterable, Codable { case none = "", plus = "+", minus = "-", off }

public enum ChannelMode: String, CaseIterable, Codable { case fm = "FM", nfm = "NFM", am = "AM", nam = "NAM", usb = "USB" }

public enum ChannelPower: Int, CaseIterable, Codable {
    case low = 0, mid = 1, high = 2
    public var label: String { ["Low", "Mid", "High"][rawValue] }
}

/// One channel, independent of the firmware. `nil` = the radio holds a value this profile
/// does not know: shown as "?" and kept byte for byte unless the user sets it.
public struct Channel: Equatable, Codable {
    public var name = ""
    public var freq = 0                // Hz
    public var offset = 0              // Hz
    public var duplex = Duplex.none
    public var txTone = ChannelTone.none
    public var rxTone = ChannelTone.none
    public var mode: ChannelMode? = .fm
    public var step: Double? = 12.5    // kHz
    public var power = ChannelPower.low
    public var scrambler: String? = "OFF"
    public var scanList1 = false
    public var scanList2 = false
    public var busyLock = false
    public var reverse = false
    public var pttID = 0
    public var dtmfDecode = false
    public var compander = 0

    public init() {}

    public var txFreq: Int? {
        switch duplex {
        case .none: return freq
        case .plus: return freq + offset
        case .minus: return freq - offset
        case .off: return nil
        }
    }
}

public enum Channels {
    public static let count = 200
    public static let ctcssTones: [Double] = [
        67.0, 69.3, 71.9, 74.4, 77.0, 79.7, 82.5, 85.4, 88.5, 91.5, 94.8, 97.4, 100.0, 103.5, 107.2, 110.9,
        114.8, 118.8, 123.0, 127.3, 131.8, 136.5, 141.3, 146.2, 151.4, 156.7, 159.8, 162.2, 165.5, 167.9, 171.3, 173.8,
        177.3, 179.9, 183.5, 186.2, 189.9, 192.8, 196.6, 199.5, 203.5, 206.5, 210.7, 218.1, 225.7, 229.1, 233.6, 241.8,
        250.3, 254.1]
    public static let dcsCodes: [Int] = [
        23, 25, 26, 31, 32, 36, 43, 47, 51, 53, 54, 65, 71, 72, 73, 74, 114, 115, 116, 122, 125, 131, 132, 134, 143, 145,
        152, 155, 156, 162, 165, 172, 174, 205, 212, 223, 225, 226, 243, 244, 245, 246, 251, 252, 255, 261, 263, 265, 266,
        271, 274, 306, 311, 315, 325, 331, 332, 343, 346, 351, 356, 364, 365, 371, 411, 412, 413, 423, 431, 432, 445, 446,
        452, 454, 455, 462, 464, 465, 466, 503, 506, 516, 523, 526, 532, 546, 565, 606, 612, 624, 627, 631, 632, 654, 662,
        664, 703, 712, 723, 731, 732, 734, 743, 754]

    // memory map (same on stock and Karina, V1 and K1 / V3)
    public static let channelBase = 0x0000
    public static let attributeBase = 0x0D60
    public static let nameBase = 0x0F50
    public static let powerOnText1 = 0x0EB0
    public static let powerOnText2 = 0x0EC0
    public static let nameLength = 10
    public static let powerOnTextLength = 12
}

// MARK: - firmware profiles

public enum RadioType: String, CaseIterable, Codable {
    case v1 = "UV-K5 V1"
    case k1 = "UV-K1 · UV-K5 V3"
}

public enum FirmwareFamily: String, CaseIterable, Codable {
    case karina = "Karina"
    case stock = "Stock"
}

public struct FirmwareProfile: Equatable, Codable {
    public let firmware: FirmwareFamily
    public let radio: RadioType

    public var label: String { "\(firmware.rawValue) · \(radio.rawValue)" }

    public init(_ firmware: FirmwareFamily, _ radio: RadioType) {
        self.firmware = firmware
        self.radio = radio
    }

    /// "karina.k1" etc., for settings keys.
    public var key: String { "\(firmware == .karina ? "karina" : "stock").\(radio == .v1 ? "v1" : "k1")" }
    public init?(key: String) {
        guard let p = FirmwareProfile.all.first(where: { $0.key == key }) else { return nil }
        self = p
    }

    public static let all: [FirmwareProfile] = [
        .init(.karina, .v1), .init(.karina, .k1), .init(.stock, .v1), .init(.stock, .k1),
    ]

    var isKarina: Bool { firmware == .karina }

    /// Mode list, index = `modulation*2 + bandwidth` (Karina) or `enable_am*2 + bandwidth` (stock).
    public var modes: [ChannelMode] { isKarina ? [.fm, .nfm, .am, .nam, .usb] : [.fm, .nfm, .am, .nam] }

    public var steps: [Double] {
        isKarina ? [0.01, 0.1, 0.5, 1, 2.5, 5, 6.25, 8.33, 10, 12.5, 25, 50, 100] : [2.5, 5, 6.25, 10, 12.5, 25]
    }

    public var scramblers: [String] {
        switch (firmware, radio) {
        case (.karina, .v1): return ["OFF"] + (26...35).map { "\($0 * 100) Hz" }
        case (.karina, .k1): return ["OFF"] + (1...20).map(String.init)
        case (.stock, _): return ["OFF"] + (1...10).map(String.init)
        }
    }

    /// PTT ID list (stock 2 bits, Karina 3 bits).
    public var pttIDs: [String] {
        isKarina ? ["OFF", "UP CODE", "DOWN CODE", "UP+DOWN CODE", "APOLLO QUINDAR"] : ["OFF", "BOT", "EOT", "BOTH"]
    }

    public var hasCompander: Bool { isKarina }

    /// Offset direction bits of byte 11: Karina `offsetDir:4`, stock `shift:2`.
    var offsetDirMask: UInt8 { isKarina ? 0x0F : 0x03 }

    /// Shows the power-on text from 0x0EB0 / 0x0EC0 (Karina shows its own fixed text).
    public var hasPowerOnText: Bool { !isKarina }

    /// Bands written to the channel attributes (and the receive range the editor accepts).
    var bands: [(Double, Double)] {
        isKarina
            ? [(15.0, 108.9999), (109.0, 139.9999), (140.0, 199.9999), (200.0, 279.9999), (280.0, 399.9999), (400.0, 469.9999), (470.0, 1349.9999)]
            : [(18.0, 76.0), (108.0, 136.9999), (137.0, 173.9999), (174.0, 349.9999), (350.0, 399.9999), (400.0, 469.9999), (470.0, 1300.0)]
    }

    /// The radio's own TX / RX ranges as the CHIRP driver checks them (stock: the radio's bands,
    /// Karina: the module's band table).
    var validRanges: [(Double, Double)] {
        isKarina ? bands : [(50.0, 76.0), (108.0, 136.9999), (137.0, 173.9999), (174.0, 349.9999), (350.0, 399.9999), (400.0, 469.9999), (470.0, 600.0)]
    }

    func band(forHz hz: Int) -> UInt8 {
        let mhz = Double(hz) / 1_000_000
        if !isKarina && mhz < 50.0 { return 1 }   // as the CHIRP UV-K5 driver
        for (i, r) in bands.enumerated() where mhz >= r.0 && mhz <= r.1 { return UInt8(i) }
        return 0
    }

    public func isValidFrequency(_ hz: Int) -> Bool {
        let mhz = Double(hz) / 1_000_000
        return validRanges.contains { mhz >= $0.0 && mhz <= $0.1 }
    }

    /// Pre-selection from the firmware string of the hello reply (only a suggestion, the user
    /// confirms; nil = unknown). Stock: Quansheng version numbers (the list CHIRP accepts).
    public static func suggest(firmwareString s: String) -> (FirmwareFamily?, RadioType?) {
        var v = s
        for p in ["k5_", "app_"] where v.hasPrefix(p) { v.removeFirst(p.count) }
        if v.hasPrefix("7.03.") { return (.stock, .k1) }
        if ["2.01.", "3.00.", "4.00.", "5.00.", "7.00.", "7.01."].contains(where: v.hasPrefix) { return (.stock, .v1) }
        if s.lowercased().hasPrefix("autumn rain") { return (.karina, nil) }
        return (nil, nil)
    }
}

// MARK: - memory image

/// The radio's configuration memory (0x0000-0x1CFF as Read Configuration saves it, or the
/// full 0x2000 image) with channel decode / encode for one profile. Every byte that is not
/// part of a field the user changed is kept as it was.
public struct ChannelMemory: Equatable {
    public var bytes: [UInt8]
    public let profile: FirmwareProfile

    public init(bytes: [UInt8], profile: FirmwareProfile) {
        var b = bytes
        if b.count < K5.configSize { b += [UInt8](repeating: 0xFF, count: K5.configSize - b.count) }
        self.bytes = b
        self.profile = profile
    }

    private func u32(_ o: Int) -> Int {
        Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24
    }
    private mutating func put32(_ o: Int, _ v: Int) {
        for k in 0..<4 { bytes[o + k] = UInt8((v >> (8 * k)) & 0xFF) }
    }

    private static func tone(flag: UInt8, code: UInt8) -> ChannelTone {
        switch flag {
        case 1: return Int(code) < Channels.ctcssTones.count ? .ctcss(Channels.ctcssTones[Int(code)]) : .none
        case 2, 3: return Int(code) < Channels.dcsCodes.count ? .dcs(Channels.dcsCodes[Int(code)], inverted: flag == 3) : .none
        default: return .none
        }
    }
    private static func toneBytes(_ t: ChannelTone) -> (flag: UInt8, code: UInt8) {
        switch t {
        case .none: return (0, 0)
        case .ctcss(let hz): return (1, UInt8(Channels.ctcssTones.firstIndex(of: hz) ?? 0))
        case .dcs(let c, let inv): return (inv ? 3 : 2, UInt8(Channels.dcsCodes.firstIndex(of: c) ?? 0))
        }
    }

    /// Channel `i` (0-based), nil when empty.
    public func channel(_ i: Int) -> Channel? {
        precondition(i >= 0 && i < Channels.count)
        let o = Channels.channelBase + i * 16
        let freq = u32(o)
        let attr = bytes[Channels.attributeBase + i]
        if freq == 0xFFFF_FFFF || freq == 0 || attr & 0x08 != 0 { return nil }
        var c = Channel()
        c.freq = freq * 10
        let offset = u32(o + 4) * 10
        let dir = bytes[o + 11] & profile.offsetDirMask
        if offset == 0 {
            c.duplex = .none
        } else if dir == 2 {
            if u32(o + 4) == freq { c.duplex = .off } else { c.duplex = .minus; c.offset = offset }
        } else if dir == 1 {
            c.duplex = .plus; c.offset = offset
        } else {
            c.duplex = .none; c.offset = offset   // offset without direction: kept, not used
        }
        c.rxTone = Self.tone(flag: bytes[o + 10] & 0x0F, code: bytes[o + 8])
        c.txTone = Self.tone(flag: bytes[o + 10] >> 4, code: bytes[o + 9])

        let b12 = bytes[o + 12]
        let bw = Int((b12 >> 1) & 1)
        if profile.isKarina {
            let m = Int(bytes[o + 11] >> 4) * 2 + bw
            c.mode = m < 5 ? profile.modes[m] : (m == 5 ? .usb : nil)
        } else {
            c.mode = profile.modes[Int((bytes[o + 11] >> 4) & 1) * 2 + bw]
        }
        let step = Int(bytes[o + 14])
        c.step = step < profile.steps.count ? profile.steps[step] : nil
        let pw = Int((b12 >> 2) & 3)
        c.power = pw == 2 ? .high : (pw == 1 ? .mid : .low)
        c.busyLock = b12 & 0x10 != 0
        c.reverse = b12 & 0x01 != 0
        let b13 = bytes[o + 13]
        c.pttID = Int((b13 >> 1) & (profile.isKarina ? 0x07 : 0x03))
        c.dtmfDecode = b13 & 1 != 0
        let scr = Int(profile.isKarina ? bytes[o + 15] : bytes[o + 15] & 0x0F)
        c.scrambler = scr < profile.scramblers.count ? profile.scramblers[scr] : nil
        c.scanList1 = attr & 0x80 != 0
        c.scanList2 = attr & 0x40 != 0
        c.compander = profile.hasCompander ? Int((attr >> 4) & 3) : 0

        var name = ""
        for k in 0..<16 {
            let ch = bytes[Channels.nameBase + i * 16 + k]
            if ch == 0x00 || ch == 0xFF { break }
            name.append(Character(Unicode.Scalar(ch)))
        }
        while name.hasSuffix(" ") { name.removeLast() }
        c.name = name
        return c
    }

    public var channels: [Channel?] { (0..<Channels.count).map(channel) }

    private mutating func setDir(_ o: Int, _ d: UInt8) {
        bytes[o + 11] = (bytes[o + 11] & ~profile.offsetDirMask) | d
    }

    /// Store channel `i` (nil = delete), as the CHIRP drivers do: every field of the channel is
    /// set, unknown values (nil) keep the radio's bits, bits of no field are kept.
    public mutating func setChannel(_ i: Int, _ c: Channel?) {
        precondition(i >= 0 && i < Channels.count)
        let o = Channels.channelBase + i * 16
        let a = Channels.attributeBase + i
        let n = Channels.nameBase + i * 16
        guard let c = c else {
            for k in 0..<16 { bytes[o + k] = 0xFF; bytes[n + k] = 0xFF }
            bytes[a] = 0x0F                                      // scan lists 0, compander 0, free, band 7
            return
        }
        if bytes[o] == 0xFF || channel(i) == nil {
            // a free slot: start from zeros (the CHIRP UV-K5 driver does this; the radios' own
            // channels have these unused bits at 0 too)
            for k in 0..<16 { bytes[o + k] = 0 }
        }
        put32(o, c.freq / 10)
        switch c.duplex {
        case .none:
            put32(o + 4, 0); setDir(o, 0)
        case .plus:
            put32(o + 4, c.offset / 10); setDir(o, 1)
        case .minus:
            put32(o + 4, c.offset / 10); setDir(o, 2)
        case .off:
            put32(o + 4, c.freq / 10); setDir(o, 2)
        }
        let rx = Self.toneBytes(c.rxTone), tx = Self.toneBytes(c.txTone)
        bytes[o + 8] = rx.code; bytes[o + 9] = tx.code
        bytes[o + 10] = tx.flag << 4 | rx.flag

        if let m = c.mode, let idx = profile.modes.firstIndex(of: m) {
            var bw = UInt8(idx % 2)
            if m == .usb { bw = 1 }
            let mod = UInt8(idx / 2)
            if profile.isKarina {
                bytes[o + 11] = (bytes[o + 11] & 0x0F) | mod << 4
            } else {
                bytes[o + 11] = (bytes[o + 11] & 0xEF) | (mod & 1) << 4
            }
            bytes[o + 12] = (bytes[o + 12] & ~0x02) | bw << 1
        }
        var b12 = bytes[o + 12] & ~(0x10 | 0x0C | 0x01)
        b12 |= (c.busyLock ? 0x10 : 0) | UInt8(c.power.rawValue) << 2 | (c.reverse ? 0x01 : 0)
        bytes[o + 12] = b12
        let pttMask: UInt8 = profile.isKarina ? 0x0E : 0x06
        bytes[o + 13] = (bytes[o + 13] & ~(pttMask | 0x01)) | (UInt8(c.pttID << 1) & pttMask) | (c.dtmfDecode ? 1 : 0)
        if let s = c.step, let idx = profile.steps.firstIndex(of: s) { bytes[o + 14] = UInt8(idx) }
        if let s = c.scrambler, let idx = profile.scramblers.firstIndex(of: s) {
            bytes[o + 15] = profile.isKarina ? UInt8(idx) : (bytes[o + 15] & 0xF0) | UInt8(idx)
        }

        let comp = profile.hasCompander ? UInt8(c.compander & 3) : 0
        bytes[a] = (c.scanList1 ? 0x80 : 0) | (c.scanList2 ? 0x40 : 0) | comp << 4 | profile.band(forHz: c.freq)

        let nm = Array(Self.sanitizedName(c.name).utf8)
        for k in 0..<16 { bytes[n + k] = k < 10 ? (k < nm.count ? nm[k] : 0x20) : 0x00 }
    }

    public static func sanitizedName(_ s: String) -> String {
        String(s.unicodeScalars.filter { $0.value >= 0x20 && $0.value < 0x7F }.map(Character.init).prefix(Channels.nameLength))
    }

    // power-on text (only meaningful when profile.hasPowerOnText)
    public func powerOnText(_ line: Int) -> String {
        let o = line == 0 ? Channels.powerOnText1 : Channels.powerOnText2
        var s = ""
        for k in 0..<16 {
            let ch = bytes[o + k]
            if ch == 0 || ch == 0xFF { break }
            s.append(Character(Unicode.Scalar(ch)))
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    public mutating func setPowerOnText(_ line: Int, _ text: String) {
        let o = line == 0 ? Channels.powerOnText1 : Channels.powerOnText2
        let t = Array(String(text.unicodeScalars.filter { $0.value >= 0x20 && $0.value < 0x7F }.map(Character.init)
            .prefix(Channels.powerOnTextLength)).utf8)
        // as the CHIRP drivers write it: up to 12 characters, then 00 FF FF FF
        let field = Array((t + [UInt8](repeating: 0x20, count: 12)).prefix(12)) + [0x00, 0xFF, 0xFF, 0xFF]
        bytes.replaceSubrange(o..<(o + 16), with: field)
    }

    public enum MoveResult: Equatable { case moved, targetsNotEmpty, noRoom }

    /// Moves the channels of `rows` (in this order) to `dest`, `dest + 1`, ...: the old rows are
    /// freed first, the target rows must then be empty and must exist (nothing is cut off).
    /// On refusal nothing changes.
    public mutating func moveChannels(_ rows: [Int], to dest: Int) -> MoveResult {
        let moving = rows.compactMap { i in channel(i).map { (i, $0) } }
        guard !moving.isEmpty else { return .moved }
        guard dest >= 0, dest + moving.count <= Channels.count else { return .noRoom }
        let before = bytes
        for (i, _) in moving { setChannel(i, nil) }
        if (dest..<(dest + moving.count)).contains(where: { channel($0) != nil }) {
            bytes = before
            return .targetsNotEmpty
        }
        for (k, (_, c)) in moving.enumerated() { setChannel(dest + k, c) }
        return .moved
    }

    /// 128-byte blocks (start addresses) whose bytes differ from `other`.
    public func changedBlocks(from other: ChannelMemory) -> [Int] {
        stride(from: 0, to: K5.configSize, by: K5.configBlockSize).filter { b in
            bytes[b..<(b + K5.configBlockSize)] != other.bytes[b..<(b + K5.configBlockSize)]
        }
    }
}
