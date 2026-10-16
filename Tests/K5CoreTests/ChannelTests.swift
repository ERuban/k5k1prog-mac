// K5K1 Prog - channel editor tests against CHIRP (golden files from scripts/chirp-golden/golden.py).
//
// Copyright (C) 2026 Evgeny Ruban (changes and the macOS app).
//
// This program is free software: you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option) any later version.

import XCTest
@testable import K5Core

final class ChannelGoldenTests: XCTestCase {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Reference/channels")

    // CHIRP's own value lists, by index (the labels differ from ours, the indexes are the bytes)
    static let chirpScramblers: [String: [String]] = [
        "stockV1": ["off"] + (1...10).map(String.init), "stockK1": ["off"] + (1...10).map(String.init),
        "karinaV1": ["OFF"] + (26...35).map { "\($0 * 100)Hz" }, "karinaK1": ["OFF"] + (1...20).map(String.init),
    ]
    static let profiles: [String: FirmwareProfile] = [
        "stockV1": .init(.stock, .v1), "stockK1": .init(.stock, .k1),
        "karinaV1": .init(.karina, .v1), "karinaK1": .init(.karina, .k1),
    ]

    func load(_ name: String) throws -> [UInt8] { Array(try Data(contentsOf: Self.dir.appendingPathComponent(name))) }
    func json(_ name: String) throws -> Any { try JSONSerialization.jsonObject(with: Data(contentsOf: Self.dir.appendingPathComponent(name))) }

    func chirpScanlists(_ c: Channel, karina: Bool) -> String {
        let i = (c.scanList1 ? 1 : 0) + (c.scanList2 ? 2 : 0)
        return karina ? ["None", "List1", "List2", "List1+2"][i] : ["None", "1", "2", "1+2"][i]
    }

    func toneJSON(_ t: ChannelTone) -> [Any?] {
        switch t {
        case .none: return ["", nil, nil]
        case .ctcss(let hz): return ["Tone", hz, nil]
        case .dcs(let c, let inv): return ["DTCS", c, inv ? "R" : "N"]
        }
    }

    func testDecodeMatchesCHIRP() throws {
        for (key, profile) in Self.profiles {
            let mem = ChannelMemory(bytes: try load(key + ".bin"), profile: profile)
            let golden = try json(key + ".json") as! [[String: Any]]
            XCTAssertEqual(golden.count, 200)
            XCTAssertGreaterThan(compare(mem, golden, key: key), 100, key)
        }
    }

    /// Your own dumps (not in the repo): K5PROG_CHANNEL_DUMPS=<dir> with <name>.<profile>.bin and the
    /// CHIRP decode `golden.py --decode <name>.<profile>.bin --profile <profile> > <name>.<profile>.json`.
    func testLocalDumpsIfPresent() throws {
        guard let dir = ProcessInfo.processInfo.environment["K5PROG_CHANNEL_DUMPS"] else { throw XCTSkip("K5PROG_CHANNEL_DUMPS not set") }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".bin") }
        XCTAssertFalse(files.isEmpty)
        for f in files {
            let key = String(f.dropLast(4).split(separator: ".").last!)
            guard let profile = Self.profiles[key] else { continue }
            let mem = ChannelMemory(bytes: Array(try Data(contentsOf: URL(fileURLWithPath: dir + "/" + f))), profile: profile)
            let golden = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: dir + "/" + f.dropLast(4) + ".json"))) as! [[String: Any]]
            let used = compare(mem, golden.map { var g = $0; g["empty"] = false; return g }, key: key)
            XCTAssertEqual(used, golden.count, f)
            XCTAssertEqual(mem.channels.compactMap { $0 }.count, golden.count, f + ": same number of channels")
        }
    }

    @discardableResult
    func compare(_ mem: ChannelMemory, _ golden: [[String: Any]], key: String) -> Int {
        let profile = mem.profile
        var checked = 0
        for g in golden {
            let n = g["n"] as! Int
            let c = mem.channel(n - 1)
            let msg = "\(key) #\(n)"
            if g["empty"] as! Bool { XCTAssertNil(c, msg); continue }
            guard let c = c else { XCTFail(msg + " decoded as empty"); continue }
            checked += 1
            XCTAssertEqual(c.name, g["name"] as? String, msg)
            XCTAssertEqual(c.freq, g["freq"] as? Int, msg)
            XCTAssertEqual(c.offset, g["offset"] as? Int, msg)
            XCTAssertEqual(c.duplex.rawValue, g["duplex"] as? String, msg)
            for (mine, gk) in [(c.txTone, "tx"), (c.rxTone, "rx")] {
                let gt = g[gk] as! [Any]
                let mt = toneJSON(mine)
                XCTAssertEqual(mt[0] as? String, gt[0] as? String, msg + " " + gk)
                if let hz = mt[1] as? Double { XCTAssertEqual(hz, gt[1] as? Double, msg + " " + gk) }
                if let code = mt[1] as? Int { XCTAssertEqual(code, gt[1] as? Int, msg + " " + gk) }
                XCTAssertEqual(mt[2] as? String, gt[2] as? String, msg + " " + gk)
            }
            if let m = c.mode { XCTAssertEqual(m.rawValue, g["mode"] as? String, msg) }
            else { XCTAssertEqual(g["mode"] as? String, "UNSUPPORTED BY CHIRP", msg) }
            if let s = c.step { XCTAssertEqual(s, g["step"] as? Double, msg) }
            else { XCTAssertEqual(g["step"] as? Double, 2.5, msg + " (unknown step index, CHIRP shows 2.5)") }
            XCTAssertEqual(["Low", "Med", "High"][c.power.rawValue], g["power"] as? String, msg)
            let scrIdx = c.scrambler.flatMap { profile.scramblers.firstIndex(of: $0) }
            XCTAssertEqual(scrIdx.map { Self.chirpScramblers[key]![$0] } ?? Self.chirpScramblers[key]![0], g["scrambler"] as? String, msg)
            XCTAssertEqual(chirpScanlists(c, karina: profile.firmware == .karina), g["scanlists"] as? String, msg)
            XCTAssertEqual(c.busyLock ? "True" : "False", g["busyLock"] as? String, msg)
            XCTAssertEqual(c.reverse ? "True" : "False", g["reverse"] as? String, msg)
            let ptt = c.pttID < profile.pttIDs.count ? profile.pttIDs[c.pttID] : profile.pttIDs[0]
            XCTAssertEqual(ptt.lowercased(), (g["pttid"] as? String)?.lowercased(), msg)
            if let d = g["dtmfDecode"] as? String { XCTAssertEqual(c.dtmfDecode ? "True" : "False", d, msg) }
            if let comp = g["compander"] as? String { XCTAssertEqual(["OFF", "TX", "RX", "TX/RX"][c.compander], comp, msg) }
        }
        return checked
    }

    func testEncodeMatchesCHIRP() throws {
        for (key, profile) in Self.profiles {
            let original = try load(key + ".bin")
            let expected = try load(key + ".edited.bin")
            var mem = ChannelMemory(bytes: original, profile: profile)
            let edits = try json(key + ".edits.json") as! [[String: Any]]
            var newSlots = Set<Int>()
            for e in edits {
                let i = (e["n"] as! Int) - 1
                if e["op"] as! String == "delete" { mem.setChannel(i, nil); continue }
                if mem.channel(i) == nil { newSlots.insert(i) }
                var c = mem.channel(i) ?? Channel()
                c.freq = e["freq"] as! Int
                c.name = e["name"] as! String
                c.duplex = Duplex(rawValue: e["duplex"] as! String)!
                c.offset = e["offset"] as! Int
                func tone(_ a: [Any]) -> ChannelTone {
                    switch a[0] as! String {
                    case "Tone": return .ctcss(a[1] as! Double)
                    case "DTCS": return .dcs(a[1] as! Int, inverted: (a[2] as? String) == "R")
                    default: return .none
                    }
                }
                c.txTone = tone(e["tx"] as! [Any]); c.rxTone = tone(e["rx"] as! [Any])
                c.mode = ChannelMode(rawValue: e["mode"] as! String)
                c.step = e["step"] as? Double
                c.power = ["Low": .low, "Med": .mid, "High": .high][e["power"] as! String]!
                let scrIdx = Self.chirpScramblers[key]!.firstIndex(of: e["scrambler"] as! String)!
                c.scrambler = profile.scramblers[scrIdx]
                let sl = e["scanlists"] as! String
                c.scanList1 = sl.hasSuffix("1") || sl.contains("1+")
                c.scanList2 = sl.hasSuffix("2")
                mem.setChannel(i, c)
            }
            for k in 0..<K5.configSize where mem.bytes[k] != expected[k] {
                // Karina's module leaves a free slot's unused bits at FF; we start from 0 like the
                // UV-K5 driver (and like the radios' own channels): bits 7-5 of byte 12, 7-4 of byte 13
                let i = k / 16, f = k % 16
                if profile.firmware == .karina, k < 200 * 16, newSlots.contains(i), f == 12 || f == 13 {
                    let mask: UInt8 = f == 12 ? 0x1F : 0x0F
                    if mem.bytes[k] & mask == expected[k] & mask && mem.bytes[k] & ~mask == 0 { continue }
                }
                // the UV-K5 driver takes the PTT ID of a free slot from its FF bytes (BOTH); a new
                // channel here gets OFF
                if profile.firmware == .stock, k < 200 * 16, newSlots.contains(i), f == 13,
                   mem.bytes[k] & ~0x06 == expected[k] & ~0x06, mem.bytes[k] & 0x06 == 0 { continue }
                XCTFail(String(format: "%@: byte %04X ours %02X CHIRP %02X", key, k, mem.bytes[k], expected[k]))
            }
        }
    }

    func testRoundTripKeepsEveryByte() throws {
        for (key, profile) in Self.profiles {
            let original = try load(key + ".bin")
            var mem = ChannelMemory(bytes: original, profile: profile)
            for i in 0..<Channels.count { if let c = mem.channel(i) { mem.setChannel(i, c) } }
            for k in 0..<K5.configSize where mem.bytes[k] != original[k] {
                // CHIRP normalises: names padded with spaces, code byte of "no tone" = 0, attributes
                // band from the frequency. Everything else must stay.
                let inName = k >= Channels.nameBase && k < Channels.nameBase + 200 * 16
                let inAttr = k >= Channels.attributeBase && k < Channels.attributeBase + 200
                let inCode = k < 200 * 16 && (k % 16 == 8 || k % 16 == 9)
                let usbNarrow = k < 200 * 16 && k % 16 == 12 && mem.channel(k / 16)?.mode == .usb
                    && original[k] | 0x02 == mem.bytes[k]   // USB is always stored narrow (as Karina's module)
                XCTAssertTrue(inName || inAttr || inCode || usbNarrow, String(format: "%@: byte %04X changed %02X -> %02X", key, k, original[k], mem.bytes[k]))
            }
            XCTAssertEqual(mem.channels, ChannelMemory(bytes: original, profile: profile).channels, key + ": decode(encode(x)) == x")
        }
    }

    func testPowerOnTextAndSuggestions() {
        var mem = ChannelMemory(bytes: [UInt8](repeating: 0xFF, count: K5.configSize), profile: .init(.stock, .k1))
        mem.setPowerOnText(0, "WELCOME")
        mem.setPowerOnText(1, "ABCDEFGHIJKLMNOP")
        XCTAssertEqual(mem.powerOnText(0), "WELCOME")
        XCTAssertEqual(mem.powerOnText(1), "ABCDEFGHIJKL")
        XCTAssertEqual(Array(mem.bytes[0x0EBC..<0x0EC0]), [0x00, 0xFF, 0xFF, 0xFF])
        XCTAssertFalse(FirmwareProfile(.karina, .k1).hasPowerOnText)
        XCTAssertTrue(FirmwareProfile(.stock, .v1).hasPowerOnText)

        XCTAssertTrue(FirmwareProfile.suggest(firmwareString: "7.03.01") == (.stock, .k1))
        XCTAssertTrue(FirmwareProfile.suggest(firmwareString: "2.01.26") == (.stock, .v1))
        XCTAssertTrue(FirmwareProfile.suggest(firmwareString: "k5_4.00.29") == (.stock, .v1))
        XCTAssertTrue(FirmwareProfile.suggest(firmwareString: "autumn rain 21.0") == (.karina, nil))
        XCTAssertTrue(FirmwareProfile.suggest(firmwareString: "IJV 5.0.3") == (nil, nil))
        XCTAssertTrue(FirmwareProfile.suggest(firmwareString: "") == (nil, nil))
    }
}

final class ChannelTransferTests: XCTestCase {
    func sample(_ key: String) throws -> ChannelMemory {
        let url = ChannelGoldenTests.dir.appendingPathComponent(key + ".bin")
        return ChannelMemory(bytes: Array(try Data(contentsOf: url)), profile: ChannelGoldenTests.profiles[key]!)
    }

    func testCSVRoundTrip() throws {
        let mem = try sample("karinaV1")
        let list = (0..<Channels.count).compactMap { i in mem.channel(i).map { (slot: i, channel: $0) } }
        let text = ChannelFiles.csv(list)
        XCTAssertTrue(text.hasPrefix("Location,Name,Frequency,Duplex,Offset,Tone,"))
        let back = try ChannelFiles.readCSV(text)
        XCTAssertEqual(back.channels.count, list.count)
        for (a, b) in zip(list, back.channels) {
            XCTAssertEqual(a.slot, b.slot)
            var x = a.channel, y = b.channel
            // not in CHIRP's CSV: per-firmware extras
            x.scrambler = nil; y.scrambler = nil; x.scanList1 = false; x.scanList2 = false
            x.busyLock = false; x.reverse = false; x.pttID = 0; x.dtmfDecode = false; x.compander = 0
            y.scrambler = nil
            if x.duplex == .none { x.offset = 0 }
            if x.mode == nil { x.mode = .fm }
            if x.step == nil { x.step = 12.5 }
            XCTAssertEqual(x, y, "slot \(a.slot)")
        }
    }

    func testCHIRPImageRoundTrip() throws {
        for (key, p) in ChannelGoldenTests.profiles {
            let mem = try sample(key)
            let img = ChannelFiles.chirpImage(mem.bytes, profile: p, firmwareString: "7.03.01")
            let r = ChannelFiles.readCHIRPImage(img)
            XCTAssertEqual(r.profile, p, key)
            XCTAssertEqual(r.memory.count, K5.maxConfigSize)
            XCTAssertEqual(Array(r.memory.prefix(K5.configSize)), mem.bytes)
            XCTAssertEqual(r.firmware, "7.03.01")
        }
    }

    func testConvertKarinaV1ToK1() throws {
        let v1 = try sample("karinaV1")
        let k1 = FirmwareProfile(.karina, .k1)
        var notes: [String] = []
        var converted = 0
        for i in 0..<Channels.count {
            guard let c = v1.channel(i) else { continue }
            guard let r = ChannelConverter.convert(c, from: v1.profile, to: k1, notes: &notes) else { continue }
            converted += 1
            XCTAssertEqual(r.freq, c.freq); XCTAssertEqual(r.txTone, c.txTone); XCTAssertEqual(r.rxTone, c.rxTone)
            XCTAssertTrue(k1.modes.contains(r.mode!)); XCTAssertTrue(k1.steps.contains(r.step!))
            XCTAssertTrue(k1.scramblers.contains(r.scrambler!))
            if c.scrambler != "OFF" { XCTAssertEqual(r.scrambler, "OFF") }   // 2600 Hz etc. don't exist on K1
            var m = ChannelMemory(bytes: [UInt8](repeating: 0xFF, count: K5.configSize), profile: k1)
            m.setChannel(i, r)
            XCTAssertEqual(m.channel(i), r, "encode/decode on K1 #\(i + 1)")
        }
        XCTAssertGreaterThan(converted, 100)
        XCTAssertTrue(notes.contains { $0.contains("scrambler") })
    }

    func testConvertKarinaToStockDropsUSBAndFineSteps() {
        var c = Channel(); c.name = "20M"; c.freq = 145_500_000; c.mode = .usb; c.step = 0.01; c.scrambler = "2700 Hz"; c.pttID = 4; c.compander = 3
        var notes: [String] = []
        let r = ChannelConverter.convert(c, from: .init(.karina, .v1), to: .init(.stock, .k1), notes: &notes)!
        XCTAssertEqual(r.mode, .fm); XCTAssertEqual(r.step, 2.5); XCTAssertEqual(r.scrambler, "OFF"); XCTAssertEqual(r.pttID, 0); XCTAssertEqual(r.compander, 0)
        XCTAssertEqual(notes.count, 5, notes.joined(separator: "; "))

        var hf = Channel(); hf.freq = 14_200_000
        XCTAssertNil(ChannelConverter.convert(hf, from: nil, to: .init(.stock, .v1), notes: &notes), "14.2 MHz: stock radios don't receive it")
        var tx = Channel(); tx.freq = 433_000_000; tx.duplex = .plus; tx.offset = 300_000_000
        XCTAssertNil(ChannelConverter.convert(tx, from: nil, to: .init(.stock, .k1), notes: &notes), "TX 733 MHz")
        var same = Channel(); same.freq = 446_006_250; same.scrambler = "3"
        notes = []
        XCTAssertEqual(ChannelConverter.convert(same, from: .init(.stock, .v1), to: .init(.stock, .k1), notes: &notes)?.scrambler, "3")
        XCTAssertEqual(notes, [])
    }
}
