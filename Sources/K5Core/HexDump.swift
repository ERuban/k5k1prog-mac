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

import Foundation

public enum HexDump {
    /// Port of TForm1::k5_hdump(): "%06X  %.65s" lines, 16 bytes per line,
    /// printable test `b >= 32` (bytes >= 0x80 are shown as Latin-1 characters,
    /// like the ANSI code page on Windows).
    public static func lines(_ buf: [UInt8]) -> [String] {
        guard !buf.isEmpty else { return [] }
        var out: [String] = []
        var i = 0
        while i < buf.count {
            let end = min(i + 16, buf.count)
            var hex = ""
            var asc = ""
            for k in i..<end {
                hex += String(format: "%02X ", buf[k])
                let b = buf[k]
                asc.append(b >= 32 ? HexDump.ansiChar(b) : ".")
            }
            hex = hex.padding(toLength: 48, withPad: " ", startingAt: 0)
            asc = asc.padding(toLength: 16, withPad: " ", startingAt: 0)
            out.append(String(format: "%06X  ", i) + hex + " " + asc)
            i = end
        }
        return out
    }

    /// A byte as the Windows ANSI code page (cp1252) shows it.
    public static func ansiChar(_ b: UInt8) -> Character {
        if b < 0x80 { return Character(Unicode.Scalar(b)) }
        if let s = String(bytes: [b], encoding: .windowsCP1252), let c = s.first { return c }
        return Character(Unicode.Scalar(b))
    }

    /// Hex bytes separated by single spaces, e.g. "AB CD 01".
    public static func bytes(_ buf: [UInt8]) -> String {
        buf.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

extension Array where Element == UInt8 {
    /// AnsiString-style conversion (stops at the first NUL), Latin-1 mapping.
    var cString: [UInt8] {
        if let z = firstIndex(of: 0) { return Array(self[..<z]) }
        return self
    }

    /// AnsiString -> text (Windows cp1252 view of the bytes).
    var latin1: String {
        String(map { HexDump.ansiChar($0) })
    }
}
