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
import Darwin

/// POSIX replacement for the original CSerialPort (Win32 COM port).
///
/// Mirrors the original settings: 8N1, binary, no XON/XOFF, no CTS/DSR flow
/// control, DTR + RTS asserted while open (DTR_CONTROL_ENABLE / RTS_CONTROL_ENABLE),
/// both cleared before closing, Tx/Rx purged on open, exclusive access like a
/// Windows COM handle, non-blocking reads (ReadIntervalTimeout = MAXDWORD).
public final class SerialPort {
    private var fd: Int32 = -1
    private let lock = NSLock()
    private var _connected = false
    private var abortRequested = false

    public init() {}

    /// True while the port is open and no abort (Esc) was requested.
    public var connected: Bool {
        lock.lock(); defer { lock.unlock() }
        return _connected && !abortRequested
    }

    /// Thread safe: marks the port as disconnected (used by Esc / window close).
    /// The worker thread notices `connected == false`, exactly like the original
    /// `m_serial.port.Disconnect()` from FormKeyDown.
    public func requestAbort() {
        lock.lock(); abortRequested = true; lock.unlock()
    }

    /// Lists call-out serial devices (/dev/cu.*), the macOS equivalent of
    /// HKLM\HARDWARE\DEVICEMAP\SERIALCOMM.
    public static func listPorts() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        var ports = names.filter { $0.hasPrefix("cu.") }.sorted().map { "/dev/" + $0 }
        // test hook: extra device paths (e.g. a k5emu pty), colon separated
        if let extra = ProcessInfo.processInfo.environment["K5PROG_EXTRA_PORTS"] {
            ports += extra.split(separator: ":").map(String.init)
        }
        return ports
    }

    /// Returns 0 on success, otherwise errno.
    public func connect(path: String, baudRate: Int) -> Int32 {
        disconnect()

        let h = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        if h < 0 { return errno }

        if ioctl(h, TIOCEXCL) != 0 {
            let e = errno; close(h); return e
        }

        var t = termios()
        if tcgetattr(h, &t) != 0 {
            let e = errno; close(h); return e
        }
        cfmakeraw(&t)
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        t.c_cflag &= ~tcflag_t(CSIZE | PARENB | CSTOPB | CRTSCTS)
        t.c_cflag |= tcflag_t(CS8)
        t.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY | INPCK | ISTRIP | PARMRK)
        t.c_iflag |= tcflag_t(IGNBRK)
        withUnsafeMutableBytes(of: &t.c_cc) { cc in
            cc[Int(VMIN)] = 0
            cc[Int(VTIME)] = 0
        }
        cfsetspeed(&t, speed_t(baudRate))
        // The original ignores SetCommState() failures, but a wrong baud rate would
        // only make the radio not answer. Fall back to IOSSIOSPEED for odd rates.
        if tcsetattr(h, TCSANOW, &t) != 0 {
            cfsetspeed(&t, speed_t(B9600))
            _ = tcsetattr(h, TCSANOW, &t)
            var speed = speed_t(baudRate)
            _ = ioctl(h, SerialPort.IOSSIOSPEED, &speed)
        }

        // DTR + RTS on (DTR_CONTROL_ENABLE / RTS_CONTROL_ENABLE)
        var bits: Int32 = TIOCM_DTR | TIOCM_RTS
        _ = ioctl(h, TIOCMBIS, &bits)

        // PurgeComm(RX/TX)
        tcflush(h, TCIOFLUSH)

        lock.lock()
        fd = h
        _connected = true
        abortRequested = false
        lock.unlock()
        return 0
    }

    /// Clears RTS + DTR (rts = false; dtr = false) and closes the port.
    public func disconnect() {
        lock.lock()
        let h = fd
        fd = -1
        _connected = false
        lock.unlock()
        guard h >= 0 else { return }
        // make sure everything queued (e.g. the reboot command) has left the UART
        tcdrain(h)
        var bits: Int32 = TIOCM_DTR | TIOCM_RTS
        _ = ioctl(h, TIOCMBIC, &bits)
        _ = ioctl(h, TIOCNXCL)
        close(h)
    }

    /// Non-blocking read. Returns number of bytes (0 = nothing), -1 on error.
    public func rxBytes(into buf: inout [UInt8], max: Int) -> Int {
        guard connected, max > 0 else { return connected ? 0 : -1 }
        lock.lock(); let h = fd; lock.unlock()
        if h < 0 { return -1 }
        if buf.count < max { buf = [UInt8](repeating: 0, count: max) }
        let n = buf.withUnsafeMutableBytes { read(h, $0.baseAddress, max) }
        if n < 0 {
            if errno == EAGAIN || errno == EINTR { return 0 }
            return -1
        }
        return n
    }

    /// Blocking write of the whole buffer (like non-overlapped WriteFile). Returns bytes sent.
    public func txBytes(_ data: [UInt8]) -> Int {
        guard connected else { return 0 }
        lock.lock(); let h = fd; lock.unlock()
        if h < 0 { return 0 }
        var sent = 0
        let deadline = Date().addingTimeInterval(5)
        while sent < data.count {
            let n = data.withUnsafeBytes { raw -> Int in
                write(h, raw.baseAddress!.advanced(by: sent), data.count - sent)
            }
            if n > 0 {
                sent += n
                continue
            }
            if n < 0 && errno != EAGAIN && errno != EINTR { break }
            if Date() > deadline || !connected { break }
            var p = pollfd(fd: h, events: Int16(POLLOUT), revents: 0)
            _ = poll(&p, 1, 10)
        }
        return sent
    }

    // _IOW('T', 2, speed_t)
    static let IOSSIOSPEED: UInt = 0x8008_5402
}
