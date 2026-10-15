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

/// Minimal TIniFile equivalent (Win32 private profile semantics: case-insensitive
/// section/key names, "Key=Value" lines, CRLF line ends when written).
public final class IniFile {
    public let path: String
    private var sections: [(name: String, entries: [(key: String, value: String)])] = []

    public init(path: String) {
        self.path = path
        load()
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: path) else { return }
        let text = String(decoding: data, as: UTF8.self)
        var current: Int? = nil
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if let idx = sections.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    current = idx
                } else {
                    sections.append((name, []))
                    current = sections.count - 1
                }
                continue
            }
            guard let c = current, let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if !sections[c].entries.contains(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
                sections[c].entries.append((key, value))
            }
        }
    }

    public func readString(_ section: String, _ key: String, _ def: String) -> String {
        guard let s = sections.first(where: { $0.name.caseInsensitiveCompare(section) == .orderedSame }),
              let e = s.entries.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })
        else { return def }
        return e.value
    }

    /// TIniFile::ReadInteger -> StrToIntDef(value, def) (also accepts $hex / 0x hex).
    public func readInteger(_ section: String, _ key: String, _ def: Int) -> Int {
        let v = readString(section, key, "")
        if v.isEmpty { return def }
        if v.hasPrefix("$") { return Int(v.dropFirst(), radix: 16) ?? def }
        if v.lowercased().hasPrefix("0x") { return Int(v.dropFirst(2), radix: 16) ?? def }
        return Int(v) ?? def
    }

    public func writeString(_ section: String, _ key: String, _ value: String) {
        let idx: Int
        if let i = sections.firstIndex(where: { $0.name.caseInsensitiveCompare(section) == .orderedSame }) {
            idx = i
        } else {
            sections.append((section, []))
            idx = sections.count - 1
        }
        if let k = sections[idx].entries.firstIndex(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
            sections[idx].entries[k].value = value
        } else {
            sections[idx].entries.append((key, value))
        }
    }

    public func writeInteger(_ section: String, _ key: String, _ value: Int) {
        writeString(section, key, String(value))
    }

    /// Serialised exactly like the Windows profile API writes a fresh file.
    public var text: String {
        var out = ""
        for s in sections {
            out += "[\(s.name)]\r\n"
            for e in s.entries { out += "\(e.key)=\(e.value)\r\n" }
        }
        return out
    }

    @discardableResult
    public func save() -> Bool {
        FileManager.default.createFile(atPath: path, contents: Data(text.utf8))
    }

    /// saveSettings() starts with DeleteFile(m_ini_filename).
    public static func fresh(path: String) -> IniFile {
        try? FileManager.default.removeItem(atPath: path)
        return IniFile(path: path)
    }
}
