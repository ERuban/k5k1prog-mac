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

/// Firmware file handling from TForm1::WriteFirmwareButtonClick() (k5prog-win v0.1.26).
public enum FirmwareFile {
    /// The original "is this a plain (unencrypted) image" test.
    public static func looksPlain(_ d: [UInt8]) -> Bool {
        guard d.count > 14 else { return false }
        return d[2] == 0x00 && d[3] == 0x20 && d[6] == 0x00 && d[10] == 0x00 && d[14] == 0x00
    }

    public struct Result: Equatable {
        /// Data as it will be written to flash.
        public var data: [UInt8]
        /// Still considered encrypted -> "File doesn't appear to be valid for uploading".
        public var encrypted: Bool
        /// "firmware file de-obfuscated" was logged.
        public var deobfuscated: Bool
        /// Version string extracted from offset 0x2000 (AnsiString semantics, up to NUL).
        public var version: [UInt8]?
    }

    /// Exact transliteration of the decode part of WriteFirmwareButtonClick().
    /// Caller guarantees data.count >= 1000 (checked before, like the original).
    public static func process(_ input: [UInt8]) -> Result {
        var data = input
        var encrypted = true
        var deobfuscated = false
        var version: [UInt8]? = nil

        let crc1 = Codec.crc16(data[0..<(data.count - 2)])
        let crc2 = (UInt16(data[data.count - 1]) << 8) | UInt16(data[data.count - 2])

        if looksPlain(data) { encrypted = false }

        if encrypted && crc1 == crc2 {
            data.removeLast(2)            // drop the 16-bit CRC
            Codec.xorFirmware(&data)      // decrypt it
            if looksPlain(data) { encrypted = false }
            if !encrypted { deobfuscated = true }
            if !encrypted && data.count >= 0x2000 + 16 {
                // extract and remove the 16-byte version string
                let ver = Array(data[0x2000..<(0x2000 + 16)])
                data.removeSubrange(0x2000..<(0x2000 + 16))
                version = ver.cString
            }
        }
        return Result(data: data, encrypted: encrypted, deobfuscated: deobfuscated, version: version)
    }

    /// The "bootloader will at times refuse the firmware version" fix-up.
    /// AnsiString indexes are 1-based in the original; [1] == first char here.
    public static func versionForBootloader(firmware: [UInt8], bootloader: [UInt8]) -> [UInt8] {
        var fw = firmware
        if fw.count >= 2 && bootloader.count >= 2 {
            if fw[0] >= UInt8(ascii: "0") && fw[0] <= UInt8(ascii: "9") {
                if fw[1] == UInt8(ascii: ".") && bootloader[1] == UInt8(ascii: ".") {
                    if fw[0] != bootloader[0] {
                        fw[0] = UInt8(ascii: "*")
                    }
                }
            }
        } else {
            fw = [UInt8(ascii: "*")]
        }
        return fw
    }

    // MARK: - UV-K5 V3 / UV-K1 (PY32F071) images — not part of k5prog-win 0.1.26

    /// Raw PY32F071 image: initial SP in SRAM (0x200xxxxx) and reset vector in flash
    /// (0x080xxxxx). A DP32G030 (K5 V1) image has its reset vector at 0x0000xxxx, so the
    /// two can't be confused (same rule as serialtool _fwcodec.is_raw_image()).
    public static func isPY32Image(_ d: [UInt8]) -> Bool {
        guard d.count >= 8 else { return false }
        let sp = UInt32(d[0]) | UInt32(d[1]) << 8 | UInt32(d[2]) << 16 | UInt32(d[3]) << 24
        let rv = UInt32(d[4]) | UInt32(d[5]) << 8 | UInt32(d[6]) << 16 | UInt32(d[7]) << 24
        return (sp & 0xFFF0_0000) == 0x2000_0000 && (rv & 0xFFF0_0000) == 0x0800_0000
    }

    public struct PY32Result: Equatable {
        public var data: [UInt8]
        /// The file was a vendor ".packed" image (CRC + XOR + version at 0x2000).
        public var unpacked: Bool
        public var version: [UInt8]?
    }

    /// Recognises a UV-K5 V3 / UV-K1 firmware file, raw or packed. nil = not one.
    /// Packed format is the same Quansheng format as for the V1 (serialtool _fwcodec.py).
    public static func processPY32(_ input: [UInt8]) -> PY32Result? {
        if isPY32Image(input) { return PY32Result(data: input, unpacked: false, version: nil) }
        guard input.count > 0x2000 + 16 + 2 else { return nil }
        let crc1 = Codec.crc16(input[0..<(input.count - 2)])
        let crc2 = (UInt16(input[input.count - 1]) << 8) | UInt16(input[input.count - 2])
        guard crc1 == crc2 else { return nil }
        var data = Array(input[0..<(input.count - 2)])
        Codec.xorFirmware(&data)
        let ver = Array(data[0x2000..<(0x2000 + 16)]).cString
        data.removeSubrange(0x2000..<(0x2000 + 16))
        guard isPY32Image(data) else { return nil }
        return PY32Result(data: data, unpacked: true, version: ver)
    }

    /// "7.00.07" >= "7.00.07" style compare (major.minor.patch).
    public static func bootloaderAtLeast(_ version: String, _ minimum: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            var p = v.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
            while p.count < 3 { p.append(0) }
            return p
        }
        let a = parts(version), b = parts(minimum)
        for i in 0..<3 where a[i] != b[i] { return a[i] > b[i] }
        return true
    }

    /// flash_max_block_addr from k5_write_flash() (uint16_t arithmetic).
    public static func maxBlockAddr(firmwareSize: Int) -> UInt16 {
        let s = UInt16(truncatingIfNeeded: firmwareSize)
        return (s & 0xFF) != 0 ? (s & 0xFF00) &+ UInt16(K5.flashBlockSize) : (s & 0xFF00)
    }
}
