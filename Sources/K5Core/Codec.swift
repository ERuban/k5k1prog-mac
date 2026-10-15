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

// CRC16 and XOR (de)obfuscation, ported verbatim from k5prog-win v0.1.26.

public enum Codec {
    /// CRC-16/XMODEM (poly 0x1021, init 0), same as the original table driven crc16().
    public static func crc16<C: Collection>(_ data: C) -> UInt16 where C.Element == UInt8 {
        var crc: UInt16 = 0
        for b in data {
            crc ^= UInt16(b) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }

    /// k5_xor_firmware() pattern.
    public static let firmwareXOR: [UInt8] = [
        0x47, 0x22, 0xc0, 0x52, 0x5d, 0x57, 0x48, 0x94, 0xb1, 0x60, 0x60, 0xdb, 0x6f, 0xe3, 0x4c, 0x7c,
        0xd8, 0x4a, 0xd6, 0x8b, 0x30, 0xec, 0x25, 0xe0, 0x4c, 0xd9, 0x00, 0x7f, 0xbf, 0xe3, 0x54, 0x05,
        0xe9, 0x3a, 0x97, 0x6b, 0xb0, 0x6e, 0x0c, 0xfb, 0xb1, 0x1a, 0xe2, 0xc9, 0xc1, 0x56, 0x47, 0xe9,
        0xba, 0xf1, 0x42, 0xb6, 0x67, 0x5f, 0x0f, 0x96, 0xf7, 0xc9, 0x3c, 0x84, 0x1b, 0x26, 0xe1, 0x4e,
        0x3b, 0x6f, 0x66, 0xe6, 0xa0, 0x6a, 0xb0, 0xbf, 0xc6, 0xa5, 0x70, 0x3a, 0xba, 0x18, 0x9e, 0x27,
        0x1a, 0x53, 0x5b, 0x71, 0xb1, 0x94, 0x1e, 0x18, 0xf2, 0xd6, 0x81, 0x02, 0x22, 0xfd, 0x5a, 0x28,
        0x91, 0xdb, 0xba, 0x5d, 0x64, 0xc6, 0xfe, 0x86, 0x83, 0x9c, 0x50, 0x1c, 0x73, 0x03, 0x11, 0xd6,
        0xaf, 0x30, 0xf4, 0x2c, 0x77, 0xb2, 0x7d, 0xbb, 0x3f, 0x29, 0x28, 0x57, 0x22, 0xd6, 0x92, 0x8b,
    ]

    /// k5_xor_payload() pattern.
    public static let payloadXOR: [UInt8] = [
        0x16, 0x6c, 0x14, 0xe6, 0x2e, 0x91, 0x0d, 0x40, 0x21, 0x35, 0xd5, 0x40, 0x13, 0x03, 0xe9, 0x80,
    ]

    public static func xorFirmware(_ data: inout [UInt8]) {
        let p = firmwareXOR
        for i in data.indices { data[i] ^= p[i % p.count] }
    }

    public static func xorPayload(_ data: inout [UInt8]) {
        let p = payloadXOR
        for i in data.indices { data[i] ^= p[i % p.count] }
    }

    /// k5_obfuscate(): AB CD | len16 LE | xor(payload + crc16 LE) | DC BA
    public static func obfuscate(_ payload: [UInt8]) -> (frame: [UInt8], crc: UInt16) {
        let len = payload.count
        let crc = crc16(payload)
        var body = payload
        body.append(UInt8(crc & 0xFF))
        body.append(UInt8(crc >> 8))
        xorPayload(&body)
        var frame: [UInt8] = [0xAB, 0xCD, UInt8(len & 0xFF), UInt8((len >> 8) & 0xFF)]
        frame += body
        frame += [0xDC, 0xBA]
        return (frame, crc)
    }
}
