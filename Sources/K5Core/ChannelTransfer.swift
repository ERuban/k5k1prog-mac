// K5K1 Prog - macOS programmer for Quansheng UV-K5 / UV-K5 V3 / UV-K1 radios.
//
// Channel editor: copy between firmware profiles, import / export (CHIRP CSV and .img).
// The CSV columns and the .img container are CHIRP's (https://github.com/kk7ds/chirp).
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

// MARK: - conversion between profiles

public enum ChannelConverter {
    /// Converts `c` (decoded with `from`; nil = a generic source such as CSV) for `to`, value by
    /// value. Returns nil when the channel can't be used on `to` (frequency out of range).
    /// Every adjusted value is reported in `notes`.
    public static func convert(_ c: Channel, from: FirmwareProfile?, to: FirmwareProfile, notes: inout [String]) -> Channel? {
        var r = c
        let tag = c.name.isEmpty ? String(format: "%.5f", Double(c.freq) / 1e6) : c.name
        func note(_ s: String) { notes.append("\(tag): \(s)") }

        guard to.isValidFrequency(c.freq) else {
            note(String(format: "%.5f MHz is not supported by %@, skipped", Double(c.freq) / 1e6, to.label))
            return nil
        }
        if let tx = c.txFreq, !to.isValidFrequency(tx) {
            note(String(format: "transmit frequency %.5f MHz is not supported by %@, skipped", Double(tx) / 1e6, to.label))
            return nil
        }
        r.name = ChannelMemory.sanitizedName(c.name)
        if r.name != c.name { note("name → “\(r.name)”") }

        if let m = c.mode, to.modes.contains(m) {
        } else {
            note("mode \(c.mode?.rawValue ?? "?") → FM"); r.mode = .fm
        }
        if let s = c.step, to.steps.contains(s) {
        } else {
            let want = c.step ?? 12.5
            let s = to.steps.min { abs($0 - want) < abs($1 - want) }!
            note("step \(c.step.map { fmtStep($0) } ?? "?") → \(fmtStep(s)) kHz"); r.step = s
        }
        let sameScramblers = from.map { $0.scramblers == to.scramblers } ?? false
        if let s = c.scrambler, s == "OFF" || (sameScramblers && to.scramblers.contains(s)) {
            r.scrambler = s
        } else {
            note("scrambler \(c.scrambler ?? "?") → OFF"); r.scrambler = "OFF"
        }
        if c.pttID >= to.pttIDs.count {
            note("PTT ID \(from?.pttIDs[safe: c.pttID] ?? String(c.pttID)) → OFF"); r.pttID = 0
        }
        if c.compander != 0 && !to.hasCompander {
            note("compander → OFF"); r.compander = 0
        }
        return r
    }

    static func fmtStep(_ s: Double) -> String {
        s == s.rounded() ? String(Int(s)) : String(format: "%g", s)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}

// MARK: - files

public enum ChannelFileError: Error, CustomStringConvertible {
    case unknownFormat(String), badCSV(String), tooSmall
    public var description: String {
        switch self {
        case .unknownFormat(let s): return s
        case .badCSV(let s): return "CSV: \(s)"
        case .tooSmall: return "The file is too small to be a radio memory image."
        }
    }
}

public struct ImportedChannels {
    /// 0-based slot in the source and the channel.
    public var channels: [(slot: Int, channel: Channel)]
    /// Profile the channels were decoded with; nil for CSV (generic values).
    public var source: FirmwareProfile?
    public var kind: String
    /// What was left out while reading (shown with the import report).
    public var notes: [String] = []
}

public enum ChannelFiles {
    static let chirpMagic: [UInt8] = [0x00, 0xFF] + Array("chirp".utf8) + [0xEE] + Array("img".utf8) + [0x00, 0x01]

    // CHIRP model names of the drivers we follow, for .img metadata
    static func chirpModel(_ p: FirmwareProfile) -> (rclass: String, model: String) {
        switch (p.firmware, p.radio) {
        case (.stock, .v1): return ("UVK5Radio", "UV-K5")
        case (.stock, .k1): return ("UVK1Radio", "UV-K1")
        case (.karina, .v1): return ("UVK5RadioEgzumer", "UV-K5 (Karina - autumn rain (module based on F4)")
        case (.karina, .k1): return ("UVK5RadioEgzumer", "UV-K5V3/K1 (Karina (module based on F4)")
        }
    }

    static func profile(forCHIRPModel model: String) -> FirmwareProfile? {
        FirmwareProfile.all.first { chirpModel($0).model == model }
    }

    /// Reads a CHIRP .img: raw memory + metadata (vendor / model). Profile from the model, if known.
    public static func readCHIRPImage(_ data: [UInt8]) -> (memory: [UInt8], profile: FirmwareProfile?, model: String?, firmware: String?) {
        guard let idx = find(chirpMagic, in: data) else { return (data, nil, nil, nil) }
        let meta = Array(data[(idx + chirpMagic.count)...])
        var model: String? = nil, fw: String? = nil
        if let d = Data(base64Encoded: Data(meta)), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            model = j["model"] as? String
            fw = j["uvk5_firmware"] as? String
        }
        return (Array(data[..<idx]), model.flatMap(profile(forCHIRPModel:)), model, fw)
    }

    /// First index of `needle` in `hay` (no copies per position).
    static func find(_ needle: [UInt8], in hay: [UInt8]) -> Int? {
        guard !needle.isEmpty, needle.count <= hay.count else { return nil }
        outer: for i in 0...(hay.count - needle.count) {
            for k in 0..<needle.count where hay[i + k] != needle[k] { continue outer }
            return i
        }
        return nil
    }

    public static func chirpImage(_ memory: [UInt8], profile: FirmwareProfile, firmwareString: String) -> [UInt8] {
        let (rclass, model) = chirpModel(profile)
        var mem = memory
        if mem.count < K5.maxConfigSize { mem += [UInt8](repeating: 0xFF, count: K5.maxConfigSize - mem.count) }
        let meta: [String: Any] = ["rclass": rclass, "vendor": "Quansheng", "model": model, "variant": "",
                                   "chirp_version": "next-20261009", "uvk5_firmware": firmwareString]
        let json = try! JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys])
        return mem + chirpMagic + Array(json.base64EncodedString().utf8)
    }

    /// Channels of a memory image (.bin from Read Configuration, or the memory of a .img).
    public static func channels(ofMemory memory: [UInt8], profile: FirmwareProfile) throws -> ImportedChannels {
        guard memory.count >= Channels.nameBase + Channels.count * 16 else { throw ChannelFileError.tooSmall }
        let m = ChannelMemory(bytes: Array(memory.prefix(K5.configSize)), profile: profile)
        return ImportedChannels(channels: (0..<Channels.count).compactMap { i in m.channel(i).map { (i, $0) } }, source: profile, kind: "memory image")
    }

    // MARK: CSV (CHIRP generic columns)

    public static let csvHeader = ["Location", "Name", "Frequency", "Duplex", "Offset", "Tone", "rToneFreq", "cToneFreq", "DtcsCode",
                                   "DtcsPolarity", "RxDtcsCode", "CrossMode", "Mode", "TStep", "Skip", "Power", "Comment",
                                   "URCALL", "RPT1CALL", "RPT2CALL", "DVCODE"]

    static func fmtFreq(_ hz: Int) -> String { String(format: "%d.%06d", hz / 1_000_000, hz % 1_000_000) }

    static func csvField(_ s: String) -> String {
        s.contains(",") || s.contains("\"") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// CHIRP's tone columns from TX / RX tones (chirp_common.split_tone_decode).
    static func toneColumns(_ c: Channel) -> (tmode: String, rtone: Double, ctone: Double, dtcs: Int, pol: String, rxDtcs: Int, cross: String) {
        var r = (tmode: "", rtone: 88.5, ctone: 88.5, dtcs: 23, pol: "NN", rxDtcs: 23, cross: "Tone->Tone")
        func kind(_ t: ChannelTone) -> String { if case .ctcss = t { return "Tone" }; if case .dcs = t { return "DTCS" }; return "" }
        var txPol = "N", rxPol = "N"
        if case .dcs(_, let inv) = c.txTone { txPol = inv ? "R" : "N" }
        if case .dcs(_, let inv) = c.rxTone { rxPol = inv ? "R" : "N" }
        r.pol = txPol + rxPol
        switch (c.txTone, c.rxTone) {
        case (.none, .none): return r
        case (.ctcss(let t), .none): r.tmode = "Tone"; r.rtone = t; return r
        case (.ctcss(let a), .ctcss(let b)) where a == b: r.tmode = "TSQL"; r.ctone = a; return r
        case (.dcs(let a, _), .dcs(let b, _)) where a == b: r.tmode = "DTCS"; r.dtcs = a; return r
        default: break
        }
        r.tmode = "Cross"
        r.cross = kind(c.txTone) + "->" + kind(c.rxTone)
        if case .ctcss(let t) = c.txTone { r.rtone = t }
        if case .dcs(let d, _) = c.txTone { r.dtcs = d }
        if case .ctcss(let t) = c.rxTone { r.ctone = t }
        if case .dcs(let d, _) = c.rxTone { r.rxDtcs = d }
        return r
    }

    public static func csv(_ channels: [(slot: Int, channel: Channel)]) -> String {
        var lines = [csvHeader.joined(separator: ",")]
        for (slot, c) in channels {
            let t = toneColumns(c)
            let watts = ["1.5W", "3.0W", "5.0W"][c.power.rawValue]
            let row = [String(slot + 1), csvField(c.name), fmtFreq(c.freq), c.duplex.rawValue, fmtFreq(c.duplex == .plus || c.duplex == .minus ? c.offset : 0),
                       t.tmode, String(format: "%.1f", t.rtone), String(format: "%.1f", t.ctone), String(format: "%03d", t.dtcs), t.pol,
                       String(format: "%03d", t.rxDtcs), t.cross, (c.mode ?? .fm).rawValue, String(format: "%.2f", c.step ?? 12.5), "", watts,
                       "", "", "", "", ""]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func parseCSVLine(_ line: String) -> [String] {
        var out: [String] = [], cur = "", quoted = false
        let it = Array(line); var i = 0
        while i < it.count {
            let ch = it[i]
            if quoted {
                if ch == "\"" { if i + 1 < it.count && it[i + 1] == "\"" { cur.append("\""); i += 1 } else { quoted = false } }
                else { cur.append(ch) }
            } else if ch == "\"" { quoted = true }
            else if ch == "," { out.append(cur); cur = "" }
            else { cur.append(ch) }
            i += 1
        }
        out.append(cur)
        return out
    }

    /// MHz as written in CHIRP files and typed in the editor ("433.125", "433", ".6") to Hz.
    /// ASCII digits only, at most 5 digits before the point, never negative: anything else
    /// (signs, exponents, "inf", other scripts' digits) is nil instead of a crash or a wrap.
    public static func parseFreq(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let whole = String(parts[0]), frac = parts.count > 1 ? String(parts[1]) : ""
        func digits(_ x: String) -> Bool { x.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } }
        guard !(whole.isEmpty && frac.isEmpty), whole.utf8.count <= 5, digits(whole), digits(frac) else { return nil }
        return (Int(whole) ?? 0) * 1_000_000 + Int(String((frac + "000000").prefix(6)))!
    }

    public static func readCSV(_ text: String) throws -> ImportedChannels {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let head = lines.first else { throw ChannelFileError.badCSV("empty file") }
        let cols = parseCSVLine(head).map { $0.trimmingCharacters(in: .whitespaces) }
        func col(_ n: String) -> Int? { cols.firstIndex(of: n) }
        guard let iLoc = col("Location"), let iFreq = col("Frequency") else { throw ChannelFileError.badCSV("no Location / Frequency columns (not a CHIRP CSV)") }
        var out: [(Int, Channel)] = []
        for (ln, line) in lines.dropFirst().enumerated() {
            let v = parseCSVLine(line)
            func get(_ n: String) -> String { col(n).flatMap { $0 < v.count ? v[$0].trimmingCharacters(in: .whitespaces) : nil } ?? "" }
            guard iLoc < v.count, let loc = Int(v[iLoc].trimmingCharacters(in: .whitespaces)), iFreq < v.count,
                  let f = parseFreq(v[iFreq]), f > 0 else { throw ChannelFileError.badCSV("line \(ln + 2): bad location or frequency") }
            var c = Channel()
            c.name = get("Name")
            c.freq = f
            c.duplex = Duplex(rawValue: get("Duplex")) ?? .none
            c.offset = parseFreq(get("Offset")) ?? 0
            if get("Duplex") == "split" { throw ChannelFileError.badCSV("line \(ln + 2): split duplex is not supported by these radios") }
            let pol = Array(get("DtcsPolarity") + "NN")
            let rt = Double(get("rToneFreq")) ?? 88.5, ct = Double(get("cToneFreq")) ?? 88.5
            let dt = Int(get("DtcsCode")) ?? 23, rdt = Int(get("RxDtcsCode")) ?? 23
            func tone(_ kind: Substring, ctcss: Double, dcs: Int, inv: Character) -> ChannelTone {
                kind == "Tone" ? .ctcss(ctcss) : (kind == "DTCS" ? .dcs(dcs, inverted: inv == "R") : .none)
            }
            switch get("Tone") {
            case "Tone": c.txTone = .ctcss(rt)
            case "TSQL": c.txTone = .ctcss(ct); c.rxTone = .ctcss(ct)
            case "DTCS": c.txTone = .dcs(dt, inverted: pol[0] == "R"); c.rxTone = .dcs(dt, inverted: pol[1] == "R")
            case "Cross":
                let p = get("CrossMode").split(separator: ">", omittingEmptySubsequences: false)
                let tx = p.first.map { $0.replacingOccurrences(of: "-", with: "") } ?? "", rx = p.count > 1 ? String(p[1]) : ""
                c.txTone = tone(Substring(tx), ctcss: rt, dcs: dt, inv: pol[0])
                c.rxTone = tone(Substring(rx), ctcss: ct, dcs: rdt, inv: pol[1])
            default: break
            }
            for t in [c.txTone, c.rxTone] {
                if case .ctcss(let hz) = t, !Channels.ctcssTones.contains(hz) { throw ChannelFileError.badCSV("line \(ln + 2): tone \(hz) Hz is not supported") }
                if case .dcs(let d, _) = t, !Channels.dcsCodes.contains(d) { throw ChannelFileError.badCSV("line \(ln + 2): DCS \(d) is not supported") }
            }
            c.mode = ChannelMode(rawValue: get("Mode"))
            c.step = Double(get("TStep"))
            let pw = get("Power").lowercased()
            if pw.hasPrefix("high") { c.power = .high }
            else if pw.hasPrefix("med") || pw.hasPrefix("mid") { c.power = .mid }
            else if let w = Double(pw.replacingOccurrences(of: "w", with: "")) { c.power = w <= 2 ? .low : (w <= 4 ? .mid : .high) }
            else { c.power = .low }
            // CSV has no scan lists: none, as when CHIRP imports a CSV
            out.append((loc, c))
        }
        // Location = the channel number (CHIRP numbers these radios 1-200, our export too); a
        // part of a list (channels 50-60) keeps its numbers. Location 0 is CHIRP's own scratch
        // memory of its generic CSV (146.01 MHz), not a channel of the radio: skipped, reported.
        if let bad = out.first(where: { $0.0 < 0 }) { throw ChannelFileError.badCSV("bad location \(bad.0)") }
        let zero = out.filter { $0.0 == 0 }.count
        return ImportedChannels(channels: out.filter { $0.0 > 0 }.map { ($0.0 - 1, $0.1) }, source: nil, kind: "CSV",
                                notes: zero > 0 ? ["location 0 (CHIRP's scratch memory) skipped"] : [])
    }
}
