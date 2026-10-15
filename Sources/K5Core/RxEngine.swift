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

/// Port of TForm1::threadProcess() packet extraction (k5prog-win v0.1.26).
///
/// The original runs this in a 1 ms thread loop; here it is pumped from the wait
/// loops (every ~1 ms) and from clearRxPacketQueue(). Behaviour (buffer size, 5 s
/// idle purge, resync rules, CRC rule, max 4 queued payloads) is identical.
public struct RxEngine {
    public static let bufferSize = 2048
    public static let maxQueued = 4
    public static let idlePurgeSeconds = 5.0

    public private(set) var buffer = [UInt8](repeating: 0, count: RxEngine.bufferSize)
    public private(set) var wr = 0
    /// De-obfuscated payloads (data + 2 CRC bytes), exactly like m_rx_packet_queue.
    public var queue: [[UInt8]] = []
    private var lastRx = Date()

    public init() {}

    public var space: Int { RxEngine.bufferSize - wr }

    public mutating func markTimer() { lastRx = Date() }

    /// Append freshly received bytes (m_serial.rx_buffer_wr += num_bytes; rx_timer.mark()).
    public mutating func append(_ bytes: ArraySlice<UInt8>) {
        guard !bytes.isEmpty else { return }
        let n = min(bytes.count, space)
        buffer.replaceSubrange(wr..<(wr + n), with: bytes.prefix(n))
        wr += n
        lastRx = Date()
    }

    public mutating func resetBuffer() { wr = 0 }

    private mutating func drop(_ n: Int) {
        if n < wr {
            buffer.replaceSubrange(0..<(wr - n), with: buffer[n..<wr])
        }
        wr -= n
    }

    /// Packet extraction part of threadProcess().
    public mutating func extract(now: Date = Date()) {
        if wr > 0 && now.timeIntervalSince(lastRx) >= RxEngine.idlePurgeSeconds {
            wr = 0   // no data rx'ed for a while .. empty the rx buffer
        }

        while wr >= 8 {   // '8' is the very minimum packet size
            if buffer[0] != 0xAB || buffer[1] != 0xCD {
                // scan for a start byte
                var i = 1
                while i < wr && buffer[i] != 0xAB { i += 1 }
                if i < wr {
                    drop(i)     // possible start byte found - remove all rx'ed bytes before it
                } else {
                    wr = 0      // no start byte found - remove all rx'ed bytes
                }
                continue
            }

            let dataLen = (Int(buffer[3]) << 8) | Int(buffer[2])
            if dataLen > 270 {
                drop(1)         // too big .. assume it's an error
                continue
            }

            let packetLen = 4 + dataLen + 2 + 2
            if wr < packetLen { break }   // not yet received the complete packet

            if buffer[packetLen - 2] != 0xDC || buffer[packetLen - 1] != 0xBA {
                drop(1)         // invalid end bytes - slide the data down one byte
                continue
            }

            if dataLen > 0 {
                var rx = Array(buffer[4..<(4 + dataLen + 2)])
                let crc0 = (UInt16(rx[rx.count - 1]) << 8) | UInt16(rx[rx.count - 2])
                Codec.xorPayload(&rx)
                let crc1 = (UInt16(rx[rx.count - 1]) << 8) | UInt16(rx[rx.count - 2])
                if crc0 != 0xFFFF && crc1 != 0xFFFF {
                    let crc2 = Codec.crc16(rx[0..<(rx.count - 2)])
                    if crc2 != crc1 { rx.removeAll() }   // CRC error .. dump the payload
                }
                if !rx.isEmpty && queue.count < RxEngine.maxQueued {
                    queue.append(rx)
                }
            }

            drop(packetLen)   // remove the spent packet from the RX buffer
        }
    }
}
