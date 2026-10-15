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

// Constants copied verbatim from Unit1.h / Unit1.cpp of the original.

public enum K5 {
    public static let helloTries = 2                 // UVK5_HELLO_TRIES

    public static let configSize = 0x1D00            // UVK5_CONFIG_SIZE      7424
    public static let calibSize = 0x0200             // UVK5_CALIB_SIZE        512
    public static let maxConfigSize = 0x2000         // UVK5_MAX_CONFIG_SIZE  8192
    public static let configBlockSize = 128          // UVK5_CONFIG_BLOCKSIZE

    public static let flashSize = 0xF000             // UVK5_FLASH_SIZE      61440
    public static let maxFlashSize = 0x10000         // UVK5_MAX_FLASH_SIZE  65536 (bootloader is F000..FFFF)
    public static let flashBlockSize = 256           // UVK5_FLASH_BLOCKSIZE

    public static let defaultSerialSpeed = 38400     // DEFAULT_SERIAL_SPEED

    /// Fixed session id ("timestamp") sent with every user-mode command.
    public static let sessionID: [UInt8] = [0x6A, 0x39, 0x57, 0x64]

    /// Serial speed list in the same order as the original combo box.
    public static let serialSpeeds: [(title: String, value: Int)] = [
        ("300", 300), ("600", 600), ("1200", 1200), ("2400", 2400), ("4800", 4800),
        ("9600", 9600), ("19200", 19200), ("38400 - k5/k6", 38400), ("57600", 57600),
        ("76800", 76800), ("115200", 115200), ("230400", 230400), ("250000", 250000),
        ("460800", 460800), ("500000", 500000), ("921600", 921600), ("1000000", 1000000),
        ("1843200", 1843200), ("2000000", 2000000), ("3000000", 3000000),
    ]

    // --- UV-K5 V3 / UV-K1 (PY32F071, bootloader 7.xx) — NOT part of k5prog-win 0.1.26 ---
    // Protocol as in serialtool (muzkr, tools/serialtool/_prog.py in
    // armel/uv-k1-k5v3-firmware-custom).

    /// Application flash area: 0x08002800, 118K (linker script py32f071xb.ld).
    public static let py32FlashSize = 0x1D800
    public static let py32PageSize = 256
    /// Oldest supported bootloader.
    public static let py32MinBootloader = "7.00.07"
    /// Valid 0x0518 beacon intervals in a row before the handshake.
    public static let py32BeaconsNeeded = 5
    /// 0x0530 handshake messages sent, one per received beacon.
    public static let py32HandshakeCount = 3
    /// Re-sends of one page after an error or timeout.
    public static let py32MaxRetries = 3

    public static let appTitle = "K5K1 Prog"
    public static let version = "1.1.1"
}
