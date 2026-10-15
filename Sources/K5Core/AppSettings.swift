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

/// App settings in UserDefaults (~/Library/Preferences/<bundle id>.plist), the macOS place for
/// them. The original keeps them in k5prog_win.ini next to the exe; the keys here are that ini's
/// "Section.Key" names, so loadSettings()/saveSettings() keep the original logic one-to-one.
public final class AppSettings {
    public let defaults: UserDefaults

    /// Every setting the app stores, with its type (true = integer).
    public static let keys: [(section: String, key: String, integer: Bool)] = [
        ("MainForm", "Top", true), ("MainForm", "Left", true),
        ("MainForm", "Width", true), ("MainForm", "Height", true),
        ("GUI", "Verbose", true),
        ("SerialPort", "Name", false), ("SerialPort", "Speed", true),
    ]

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private static func name(_ section: String, _ key: String) -> String { "\(section).\(key)" }

    public func readInteger(_ section: String, _ key: String, _ def: Int) -> Int {
        (defaults.object(forKey: Self.name(section, key)) as? NSNumber)?.intValue ?? def
    }

    public func readString(_ section: String, _ key: String, _ def: String) -> String {
        defaults.string(forKey: Self.name(section, key)) ?? def
    }

    public func writeInteger(_ section: String, _ key: String, _ value: Int) {
        defaults.set(value, forKey: Self.name(section, key))
    }

    public func writeString(_ section: String, _ key: String, _ value: String) {
        defaults.set(value, forKey: Self.name(section, key))
    }

    public var isEmpty: Bool {
        !Self.keys.contains { defaults.object(forKey: Self.name($0.section, $0.key)) != nil }
    }

    /// One-time move of the settings that 1.0 / 1.1 kept in K5K1Prog.ini: next to the app, or in
    /// Application Support when the app folder was read-only. Runs only while no setting is
    /// stored yet. The first readable candidate is imported; then every candidate ini (all are
    /// files of this app) is deleted, and an empty `removeEmptyDir` with it.
    /// Returns the imported path, or nil.
    @discardableResult
    public func importIni(candidates: [String], removeEmptyDir: String? = nil) -> String? {
        let fm = FileManager.default
        guard isEmpty, let path = candidates.first(where: { fm.isReadableFile(atPath: $0) }) else { return nil }
        let ini = IniFile(path: path)
        for k in Self.keys {
            let v = ini.readString(k.section, k.key, "")
            if v.isEmpty { continue }
            if k.integer {
                if let n = Int(v.trimmingCharacters(in: .whitespaces)) { writeInteger(k.section, k.key, n) }
            } else {
                writeString(k.section, k.key, v)
            }
        }
        for c in candidates where fm.fileExists(atPath: c) {
            try? fm.removeItem(atPath: c)
        }
        if let dir = removeEmptyDir, (try? fm.contentsOfDirectory(atPath: dir))?.isEmpty == true {
            try? fm.removeItem(atPath: dir)
        }
        return path
    }
}
