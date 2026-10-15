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

/// Everything the original did through VCL (memo, gauge, message boxes, file dialogs).
/// Called from the worker thread; implementations must marshal to the main thread.
public protocol K5UI: AnyObject {
    func memoAdd(_ line: String)
    func memoClear()
    func gauge(max: Int, progress: Int, visible: Bool)
    /// SerialPortComboBoxChange(): refresh enabled state of buttons/combos.
    func connectionStateChanged()
    /// Application->MessageBox(..., MB_ICONERROR | MB_OK)
    func messageBoxError(_ text: String)
    /// Application->MessageBox(..., MB_ICONQUESTION | MB_YESNO | MB_DEFBUTTON2) -> true == IDYES
    func messageBoxYesNo(_ text: String) -> Bool
    /// TOpenDialog / TSaveDialog. Returns the chosen path or nil when cancelled.
    func openDialog(_ dialog: FileDialog, title: String) -> String?
    func saveDialog(_ dialog: FileDialog, title: String) -> String?
}

/// The five file dialogs of the original form (each keeps its own last file name).
public enum FileDialog: String, CaseIterable {
    case openConfig = "OpenDialog1"      // FileName = my_config.bin
    case saveConfig = "SaveDialog1"      // FileName = my_config.bin
    case openCalib = "OpenDialog2"       // FileName = my_calibration.bin
    case saveCalib = "SaveDialog2"       // FileName = my_calibration.bin
    case openFirmware = "OpenDialog3"    // no default FileName

    public var defaultFileName: String {
        switch self {
        case .openConfig, .saveConfig: return "my_config.bin"
        case .openCalib, .saveCalib: return "my_calibration.bin"
        case .openFirmware: return ""
        }
    }
}

/// Port of the radio side of TForm1 (k5prog-win v0.1.26, commit d6102ef).
/// Function names follow the original so the two can be compared side by side.
public final class K5Programmer {
    public weak var ui: K5UI?
    public let port = SerialPort()

    /// Verbose level 0..3 (VerboseTrackBar).
    public var verbose: Int {
        get { lock.lock(); defer { lock.unlock() }; return _verbose }
        set { lock.lock(); _verbose = newValue; lock.unlock() }
    }
    private var _verbose = 1
    private let lock = NSLock()

    /// Selected port ("None" == nil) and speed, set by the UI before an action.
    public var selectedPort: String?
    public var selectedSpeed: Int = K5.defaultSerialSpeed

    public private(set) var portName = ""        // m_serial.port_name
    private var rx = RxEngine()
    private var rxScratch = [UInt8](repeating: 0, count: RxEngine.bufferSize)

    public private(set) var config = [UInt8](repeating: 0, count: K5.configSize)   // m_config
    public private(set) var calib = [UInt8](repeating: 0, count: K5.calibSize)     // m_calib

    public private(set) var firmwareVer: [UInt8] = []     // m_firmware_ver
    public private(set) var bootloaderVer: [UInt8] = []   // m_bootloader_ver
    public private(set) var hasCustomAESKey = false
    public private(set) var isInLockScreen = false
    public private(set) var challenge = [UInt8](repeating: 0, count: 4)

    private var loadfileName = ""                         // m_loadfile_name
    private var loadfileData: [UInt8] = []                // m_loadfile_data

    /// Overridable for tests.
    public var loadFileHook: ((String) -> [UInt8]?)? = nil
    public var saveFileHook: ((String, [UInt8]) -> Void)? = nil

    public init() {}

    public var connected: Bool { port.connected }

    // MARK: - memo helpers

    private func add(_ s: String) { ui?.memoAdd(s) }
    private func clearMemo() { ui?.memoClear() }
    private func hdump(_ buf: [UInt8]) { for l in HexDump.lines(buf) { add(l) } }
    private func gauge(_ max: Int, _ progress: Int, _ visible: Bool) { ui?.gauge(max: max, progress: progress, visible: visible) }
    private func comboChange() { ui?.connectionStateChanged() }

    private static func sleepMs(_ ms: Int) { usleep(useconds_t(ms * 1000)) }

    // MARK: - serial

    /// Port of threadProcess() byte collection + packet extraction.
    private func pump() {
        guard port.connected else { return }
        let space = rx.space
        if space > 0 {
            let n = port.rxBytes(into: &rxScratch, max: space)
            if n < 0 {
                // error -> m_serial.port.Disconnect(); PostMessage(WM_DISCONNECT)
                port.disconnect()
                rx.resetBuffer()
                return
            }
            if n > 0 { rx.append(rxScratch[0..<n]) }
        }
        rx.extract()
    }

    /// clearRxPacket0()
    private func clearRxPacket0() {
        if !rx.queue.isEmpty { rx.queue.removeFirst() }
    }

    /// clearRxPacketQueue(). The original RX thread would already have moved any
    /// pending UART bytes into its buffer, so drain the OS buffer first.
    private func clearRxPacketQueue() {
        if port.connected {
            for _ in 0..<64 {
                let n = port.rxBytes(into: &rxScratch, max: RxEngine.bufferSize)
                if n <= 0 { break }
            }
        }
        rx.queue.removeAll()
        rx.resetBuffer()
    }

    /// disconnect()
    public func disconnect() {
        if port.connected {
            port.disconnect()
            add("'\(portName)' closed")
        } else {
            port.disconnect()   // after Esc: just release the handle, no memo line (as original)
        }
        clearRxPacketQueue()
        rx.resetBuffer()
    }

    /// connect(false)
    public func connect() -> Bool {
        disconnect()

        guard let name = selectedPort?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty, name.lowercased() != "none" else { return false }

        let baudrate = selectedSpeed
        if baudrate <= 0 {
            add("error: serial baudrate: [\(baudrate)]")
            return false
        }

        let res = port.connect(path: name, baudRate: baudrate)
        if res != 0 {
            add("error: serial port open error [\(res)]")
            return false
        }

        portName = name
        add("'\(portName)' opened at \(baudrate) Baud")

        clearRxPacketQueue()
        rx.resetBuffer()
        rx.markTimer()

        // flush the RX
        while port.rxBytes(into: &rxScratch, max: RxEngine.bufferSize) > 0 {
            K5Programmer.sleepMs(50)
        }
        return true
    }

    /// Wait loop used by every k5_* function: GetTickCount() based, 1 ms steps.
    private func waitLoop(_ timeoutMs: Int, _ body: () -> Int?) -> Int? {
        let start = Date()
        while Date().timeIntervalSince(start) * 1000 <= Double(timeoutMs) && port.connected {
            K5Programmer.sleepMs(1)
            pump()
            if rx.queue.isEmpty { continue }
            if let r = body() { return r }
        }
        return nil
    }

    // MARK: - k5 protocol

    /// k5_hex_dump2(cmd, true)
    private func hexDump2Tx(clear: [UInt8], frame: [UInt8], crc: UInt16) {
        add("tx crc_ok 1")
        add((String(format: "tx obfuscated [%3d] ", frame.count) + HexDump.bytes(frame)).trimmingCharacters(in: .whitespaces))
        add(String(format: "tx clear      [%3d]             ", clear.count) + HexDump.bytes(clear) + String(format: " - %04X", crc))
    }

    /// k5_send_buf()
    @discardableResult
    func k5SendBuf(_ buf: [UInt8]) -> Int {
        guard port.connected, !buf.isEmpty else { return 0 }
        clearRxPacketQueue()   // delete any previously rx'ed/saved packets
        let (frame, crc) = Codec.obfuscate(buf)
        if verbose > 1 { hexDump2Tx(clear: buf, frame: frame, crc: crc) }
        let sent = port.txBytes(frame)
        if sent != frame.count { return -2 }
        return 1
    }

    private func isFlashModePacket(_ d: [UInt8]) -> Bool { d.count >= 2 && d[0] == 0x18 && d[1] == 0x05 }

    private func rxDebug(_ d: [UInt8]) {
        if verbose > 2 {
            add("rx ..")
            hdump(d)
        }
    }

    /// k5_read_eeprom()
    func k5ReadEEPROM(into buf: inout [UInt8], at index: Int, len: Int, offset: Int) -> Int {
        guard port.connected, len > 0, len <= 128 else { return 0 }
        if verbose > 0 { add(String(format: "read_config  offset %04X  len %d", offset, len)) }

        var b = [UInt8](repeating: 0, count: 12)
        b[0] = 0x1B; b[1] = 0x05
        b[2] = 8; b[3] = 0
        b[4] = UInt8(offset & 0xFF); b[5] = UInt8((offset >> 8) & 0xFF)
        b[6] = UInt8(len); b[7] = 0
        b.replaceSubrange(8..<12, with: K5.sessionID)

        if k5SendBuf(b) <= 0 { return 0 }

        var result: [UInt8]? = nil
        let r = waitLoop(3000) {
            let d = rx.queue[0]
            let size = d.count - 2
            rxDebug(d)
            if isFlashModePacket(d) { clearRxPacket0(); return -1 }
            if size < 8 + len || d[0] != 0x1C || d[1] != 0x05 || d[4] != b[4] || d[5] != b[5] {
                clearRxPacket0(); return nil
            }
            result = Array(d[8..<(8 + len)])
            clearRxPacket0()
            return 1
        }
        if let r = r {
            if r == 1, let res = result { buf.replaceSubrange(index..<(index + len), with: res) }
            return r
        }
        if verbose > 1 { add("error: no valid packet received") }
        return 0
    }

    /// k5_write_eeprom()
    func k5WriteEEPROM(_ data: [UInt8], len: Int, offset: Int) -> Int {
        guard port.connected, len > 0, len <= 128, data.count >= len else { return 0 }
        if verbose > 0 { add(String(format: "write_config  offset %04X  len %d", offset, len)) }

        var b = [UInt8](repeating: 0, count: 12)
        b[0] = 0x1D; b[1] = 0x05
        b[2] = UInt8((8 + len) & 0xFF); b[3] = UInt8(((8 + len) >> 8) & 0xFF)
        b[4] = UInt8(offset & 0xFF); b[5] = UInt8((offset >> 8) & 0xFF)
        b[6] = UInt8(len)
        b[7] = 0x01   // allow password
        b.replaceSubrange(8..<12, with: K5.sessionID)
        b += data[0..<len]

        if k5SendBuf(b) <= 0 { return 0 }

        if let r = waitLoop(2000, {
            let d = rx.queue[0]
            rxDebug(d)
            if isFlashModePacket(d) { clearRxPacket0(); return -1 }
            // note: the original compares the full size (incl. the 2 CRC bytes) here
            if d.count < 6 || d[0] != 0x1E || d[1] != 0x05 || d[4] != b[4] || d[5] != b[5] {
                clearRxPacket0(); return nil
            }
            clearRxPacket0()
            return 1
        }) { return r }
        if verbose > 1 { add("error: no valid packet received") }
        return 0
    }

    /// k5_wait_flash_message()
    func k5WaitFlashMessage() -> Int {
        guard port.connected else { return 0 }
        bootloaderVer = []
        clearRxPacketQueue()
        if verbose > 0 {
            add("")
            add("listening for firmware update mode packet ..")
        }
        if let r = waitLoop(3000, {
            let d = rx.queue[0]
            let size = d.count - 2
            rxDebug(d)
            if (size != 20 && size != 36) || d[0] != 0x18 || d[1] != 0x05 {
                clearRxPacket0(); return nil
            }
            if size >= 36 {
                var ver: [UInt8] = []
                for i in 0..<16 {
                    let k = i + 20
                    if k >= size { break }
                    let c = d[k]
                    if !(c >= 0x20 && c <= 0x7E) { break }   // isprint()
                    ver.append(c)
                }
                bootloaderVer = ver
                add("")
                add("Bootloader version '" + bootloaderVer.latin1 + "'")
            } else {
                add("")
                add("Bootloader version unknown (short packet rx'ed)")
            }
            clearRxPacket0()
            return 1
        }) { return r }
        return 0
    }

    /// k5_send_flash_version_message()
    func k5SendFlashVersionMessage(_ ver: [UInt8]) -> Int {
        guard port.connected, ver.count <= 16 else { return 0 }
        var b = [UInt8](repeating: 0, count: 4 + 16)
        b[0] = 0x30; b[1] = 0x05
        b[2] = 16; b[3] = 0
        for (i, c) in ver.enumerated() { b[4 + i] = c }

        if k5SendBuf(b) <= 0 { return 0 }

        if let r = waitLoop(2000, {
            let d = rx.queue[0]
            let size = d.count - 2
            rxDebug(d)
            if (size != 20 && size != 36) || d[0] != 0x18 || d[1] != 0x05 {
                clearRxPacket0(); return nil
            }
            clearRxPacket0()
            return 1   // all OK
        }) { return r }
        add("error: no valid packet received, bootloader refused firmware version '" + ver.latin1 + "' ..")
        return 0
    }

    /// k5_write_flash()
    func k5WriteFlash(_ data: ArraySlice<UInt8>, offset: Int, firmwareSize: Int) -> Int {
        let len = data.count
        guard port.connected, len > 0, len <= 256 else { return 0 }
        if verbose > 0 { add(String(format: "write_flash  offset %04X  len %d", offset, len)) }

        let maxAddr = FirmwareFile.maxBlockAddr(firmwareSize: firmwareSize)

        var b = [UInt8](repeating: 0, count: 4 + 12 + 256)
        b[0] = 0x19; b[1] = 0x05
        b[2] = UInt8((12 + 256) & 0xFF); b[3] = UInt8(((12 + 256) >> 8) & 0xFF)
        b[4] = 0x8A; b[5] = 0x8D; b[6] = 0x9F; b[7] = 0x1D
        b[8] = UInt8((offset >> 8) & 0xFF)
        b[9] = UInt8(offset & 0xFF)
        b[10] = UInt8((maxAddr >> 8) & 0xFF)
        b[11] = 0x00
        b[12] = UInt8(len & 0xFF)
        b[13] = UInt8((len >> 8) & 0xFF)
        b[14] = 0x00; b[15] = 0x00
        b.replaceSubrange(16..<(16 + len), with: data)

        if k5SendBuf(b) <= 0 { return 0 }

        if let r = waitLoop(3000, {
            let d = rx.queue[0]
            let size = d.count - 2
            rxDebug(d)
            if size < 12 || d[0] != 0x1A || d[1] != 0x05 || d[2] != 8 || d[3] != 0 ||
                d[4] != b[4] || d[5] != b[5] || d[6] != b[6] || d[7] != b[7] ||
                d[8] != b[8] || d[9] != b[9] {
                clearRxPacket0(); return nil
            }
            clearRxPacket0()
            return 1
        }) { return r }
        if verbose > 1 { add("error: no valid packet received") }
        return 0
    }

    /// k5_hello()
    func k5Hello() -> Int {
        guard port.connected else { return 0 }
        firmwareVer = []
        hasCustomAESKey = false
        isInLockScreen = false
        challenge = [0, 0, 0, 0]

        var b: [UInt8] = [0x14, 0x05, 4, 0]
        b += K5.sessionID

        if verbose > 0 {
            add("")
            add("sending k5_hello ..")
        }
        if k5SendBuf(b) <= 0 { return 0 }

        if let r = waitLoop(1000, {
            let d = rx.queue[0]
            let size = d.count - 2
            rxDebug(d)
            if isFlashModePacket(d) { clearRxPacket0(); return -1 }
            if size < 4 + 16 + 2 + 2 + 4 || d[0] != 0x15 || d[1] != 0x05 {
                clearRxPacket0(); return nil
            }
            firmwareVer = Array(d[4..<20]).cString
            hasCustomAESKey = d[20] != 0
            isInLockScreen = d[21] != 0
            challenge = Array(d[24..<28])

            add("")
            add("  firmware version: '" + firmwareVer.latin1 + "'")
            add("has custom AES key: " + (hasCustomAESKey ? "yes" : "no"))
            add(" is in lock screen: " + (isInLockScreen ? "yes" : "no"))
            add(("         challenge: " + challenge.map { String(format: "%02X ", $0) }.joined()).trimmingTrailingSpaces)
            clearRxPacket0()
            return 1
        }) { return r }
        if verbose > 1 { add("error: no valid packet received") }
        return 0
    }

    /// k5_readADC()
    func k5ReadADC() -> Int {
        guard port.connected else { return 0 }
        var b: [UInt8] = [0x29, 0x05, 4, 0]
        b += K5.sessionID
        if verbose > 0 {
            add("")
            add("sending k5_readADC ..")
        }
        if k5SendBuf(b) <= 0 { return 0 }

        if let r = waitLoop(1000, {
            let d = rx.queue[0]
            let size = d.count - 2
            rxDebug(d)
            if isFlashModePacket(d) { clearRxPacket0(); return -1 }
            if size < 8 || d[0] != 0x2A || d[1] != 0x05 { clearRxPacket0(); return nil }

            let adcVol = (UInt16(d[5]) << 8) | UInt16(d[4])
            // battery calibration entry [3] lives at EEPROM 0x1F40 + 6.
            // The original indexes m_config (only 0x1D00 bytes) with 0x1F46, which
            // reads past m_config AND m_calib into unrelated memory, so its voltage
            // output is random. Display-only (nothing is written), so here the
            // intended value is used: the calibration block read in this session.
            let adcRef = calibrationValue(eepromAddr: 0x1F40 + 2 * 3)
            let s: String
            if adcRef > 1000 && adcRef < 2300 {
                let v = (Float(7.6) * Float(adcVol)) / Float(adcRef)
                s = String(format: "battery ADC 0x%04X %u %0.3fV", adcVol, UInt32(adcVol), Double(v))
            } else {
                s = String(format: "battery ADC 0x%04X %u", adcVol, UInt32(adcVol))
            }
            add("")
            add(s)
            clearRxPacket0()
            return 1
        }) { return r }
        if verbose > 1 { add("error: no valid packet received") }
        return 0
    }

    /// uint16 LE at an EEPROM address inside the calibration area (0x1E00..0x1FFF).
    private func calibrationValue(eepromAddr: Int) -> UInt16 {
        let c = eepromAddr - (K5.maxConfigSize - K5.calibSize)
        guard c >= 0, c + 1 < calib.count else { return 0 }
        return (UInt16(calib[c + 1]) << 8) | UInt16(calib[c])
    }

    /// k5_readRSSI()
    func k5ReadRSSI() -> Int {
        guard port.connected else { return 0 }
        var b: [UInt8] = [0x27, 0x05, 4, 0]
        b += K5.sessionID
        if verbose > 0 {
            add("")
            add("sending k5_readRSSI ..")
        }
        if k5SendBuf(b) <= 0 { return 0 }

        if let r = waitLoop(1000, {
            let d = rx.queue[0]
            let size = d.count - 2
            rxDebug(d)
            if isFlashModePacket(d) { clearRxPacket0(); return -1 }
            if size < 8 || d[0] != 0x28 || d[1] != 0x05 { clearRxPacket0(); return nil }
            let rssiRaw = ((UInt16(d[5]) << 8) | UInt16(d[4])) & 0x01FF
            let noise = d[6] & 0x7F
            let glitch = d[7]
            let rssi = (Float(rssiRaw) / 2) - 160
            add("")
            add(String(format: "RSSI %u %0.1fdBm, Noise 0x%02X %u, Glitch 0x%02X %u",
                       UInt32(rssiRaw), Double(rssi), UInt32(noise), UInt32(noise), UInt32(glitch), UInt32(glitch)))
            clearRxPacket0()
            return 1
        }) { return r }
        if verbose > 1 { add("error: no valid packet received") }
        return 0
    }

    /// k5_reboot()
    @discardableResult
    func k5Reboot() -> Int {
        guard port.connected else { return 0 }
        add("")
        add("sending reboot radio ..")
        return k5SendBuf([0xDD, 0x05, 0, 0])
    }

    // MARK: - file helpers

    /// loadFile()
    private func loadFile(_ filename: String) -> Int {
        let data: [UInt8]
        if let hook = loadFileHook {
            guard let d = hook(filename) else { ui?.messageBoxError("error: file not opened"); return 0 }
            data = d
        } else {
            guard let fh = FileHandle(forReadingAtPath: filename) else {
                ui?.messageBoxError("error: file not opened")
                return 0
            }
            defer { try? fh.close() }
            data = [UInt8](fh.readDataToEndOfFile())
        }
        if data.isEmpty {
            ui?.messageBoxError("error: empty file")
            return 0
        }
        loadfileName = filename
        loadfileData = data
        return loadfileData.count
    }

    /// saveFile()
    private func saveFile(_ filename: String, _ data: [UInt8]) {
        if let hook = saveFileHook { hook(filename, data); return }
        FileManager.default.createFile(atPath: filename, contents: Data(data))
    }

    /// `if (ExtractFileExt(name).IsEmpty()) name += ".bin";`
    private static func withDefaultExt(_ name: String) -> String {
        (name as NSString).pathExtension.isEmpty ? name + ".bin" : name
    }

    private func helloWithRetries() -> Int {
        var r = 0
        for _ in 0..<K5.helloTries {
            r = k5Hello()
            if r != 0 { break }
        }
        return r
    }

    private func fail(_ msg: String) {
        disconnect()
        add("")
        add(msg)
        comboChange()
    }

    private static let msgFlashModeNotPTT = "error: radio is in firmware update mode - turn the radio off, then back on whilst NOT pressing the PTT"
    private static let msgNotFlashMode = "error: radio is not in firmware update mode - turn the radio off, then back on whilst pressing the PTT"

    // MARK: - button handlers (same order of memo lines / dialogs as the original)

    /// ReadConfigButtonClick()
    public func readConfigButtonClick() {
        if port.connected { return }

        clearMemo()
        add("")
        if !connect() { return }
        comboChange()

        add("")
        add("Downloading configuration data from the radio ..")

        var r = helloWithRetries()
        add("")
        if r == 0 { fail("radio not detected"); return }
        if r < 0 { fail(K5Programmer.msgFlashModeNotPTT); return }

        let size = K5.configSize
        let blockLen = K5.configBlockSize
        config = [UInt8](repeating: 0, count: size)

        gauge(size, 0, true)
        var i = 0
        while i < size {
            r = k5ReadEEPROM(into: &config, at: i, len: blockLen, offset: i)
            if r <= 0 {
                add("error: k5_read_eeprom() [\(r)]")
                add("")
                gauge(size, i, false)
                disconnect()
                comboChange()
                return
            }
            gauge(size, i + blockLen, true)
            i += blockLen
        }

        add("read CONFIG complete")
        add("")
        gauge(size, size, false)
        disconnect()
        comboChange()
        add("")

        if verbose > 2 {
            add("")
            hdump(config)
            add("")
        }

        guard let picked = ui?.saveDialog(.saveConfig, title: "Save configuration file ..") else { return }
        saveFile(K5Programmer.withDefaultExt(picked), config)
    }

    /// ReadCalibrationButtonClick()
    public func readCalibrationButtonClick() {
        if port.connected { return }

        clearMemo()
        add("")
        if !connect() { return }
        comboChange()

        add("")
        add("Downloading calibration data from the radio ..")

        var r = helloWithRetries()
        add("")
        if r == 0 { fail("radio not detected"); return }
        if r < 0 { fail(K5Programmer.msgFlashModeNotPTT); return }

        let calibAddr = K5.maxConfigSize - K5.calibSize
        let size = K5.calibSize
        let blockLen = K5.configBlockSize
        calib = [UInt8](repeating: 0, count: size)

        gauge(size, 0, true)
        var i = 0
        while i < size {
            r = k5ReadEEPROM(into: &calib, at: i, len: blockLen, offset: calibAddr + i)
            if r <= 0 {
                add("error: k5_read_eeprom() [\(r)]")
                add("")
                gauge(size, i, false)
                disconnect()
                comboChange()
                return
            }
            gauge(size, i + blockLen, true)
            i += blockLen
        }

        add("read CALIBRATION complete")
        add("")
        gauge(size, size, false)
        disconnect()
        comboChange()
        add("")

        // show the calibration contents (always, like the original)
        hdump(calib)
        add("")

        guard let picked = ui?.saveDialog(.saveCalib, title: "Save CALIBRATION data file ..") else { return }
        saveFile(K5Programmer.withDefaultExt(picked), calib)
    }

    /// WriteConfigButtonClick()
    public func writeConfigButtonClick() {
        if port.connected { return }

        add("")
        guard let picked = ui?.openDialog(.openConfig, title: "Load configuration file ..") else { return }
        let name = K5Programmer.withDefaultExt(picked)

        if loadFile(name) == 0 {
            ui?.messageBoxError("No data loaded")
            return
        }

        clearMemo()
        add("")
        add("Loaded \(loadfileData.count) bytes from ..")
        add(loadfileName)

        if loadfileData.count <= 1000 {
            ui?.messageBoxError("File appears to be to small to be an config file")
            return
        }
        if loadfileData.count > K5.maxConfigSize {
            ui?.messageBoxError(String(format: "File is to large to be an config file (max 0x%04X)", K5.maxConfigSize))
            return
        }
        if loadfileData.count > K5.configSize {
            let yes = ui?.messageBoxYesNo(String(format: "File is larger than normal (0x%04X)\n\nStill upload ?", K5.configSize)) ?? false
            if !yes { return }
        }

        add("")
        if !connect() { return }
        comboChange()

        add("")
        add("Uploading configuration data to the radio ..")

        let r = helloWithRetries()
        add("")
        if r == 0 { fail("radio not detected"); return }
        if r < 0 { fail(K5Programmer.msgFlashModeNotPTT); return }

        if verbose > 2 {
            add("")
            hdump(loadfileData)
            add("")
        }

        add("writing config area ..")
        writeBlocks(loadfileData, baseAddr: 0, completeMsg: "write CONFIG complete")
    }

    /// WriteCalibrationButtonClick()
    public func writeCalibrationButtonClick() {
        if port.connected { return }

        guard let picked = ui?.openDialog(.openCalib, title: "Select a CALIBRATION file to upload") else { return }
        let name = K5Programmer.withDefaultExt(picked)

        if loadFile(name) == 0 {
            ui?.messageBoxError("No data loaded")
            return
        }

        clearMemo()
        add("")
        // (the original prints UVK5_FLASH_SIZE as "max" here)
        add(String(format: "Loaded %u (0x%04X) bytes (max 0x%04X) from '", UInt32(loadfileData.count), UInt32(loadfileData.count), K5.flashSize) + loadfileName + "'")

        if loadfileData.count != K5.calibSize {
            ui?.messageBoxError("File size is invalid")
            return
        }

        if verbose > 2 {
            add("")
            hdump(loadfileData)
        }

        add("")
        if !connect() { return }
        comboChange()

        add("")
        add("Uploading calibration data to the radio ..")

        let r = helloWithRetries()
        add("")
        if r == 0 { fail("radio not detected"); return }
        if r < 0 { fail(K5Programmer.msgFlashModeNotPTT); return }

        if verbose > 2 {
            add("")
            hdump(loadfileData)
            add("")
        }

        add("writing config area ..")
        writeBlocks(loadfileData, baseAddr: K5.maxConfigSize - K5.calibSize, completeMsg: "write CALIBRATION complete")
    }

    /// The common block-write loop of WriteConfigButtonClick / WriteCalibrationButtonClick.
    ///
    /// The original always sends full 128 byte blocks; for a file whose size is not a
    /// multiple of 128 it reads past the end of its buffer and writes heap garbage into
    /// the radio. Here the missing tail of the last block is filled with the radio's
    /// current contents (read back first) instead, so nothing random is ever written.
    private func writeBlocks(_ data: [UInt8], baseAddr: Int, completeMsg: String) {
        let size = data.count
        gauge(size, 0, true)

        var i = 0
        while i < size {
            let len = K5.configBlockSize
            var block: [UInt8]
            if i + len <= size {
                block = Array(data[i..<(i + len)])
            } else {
                var current = [UInt8](repeating: 0xFF, count: len)
                let rr = k5ReadEEPROM(into: &current, at: 0, len: len, offset: baseAddr + i)
                if rr <= 0 {
                    add("error: k5_read_eeprom() [\(rr)]")
                    add("")
                    gauge(size, i, false)
                    disconnect()
                    comboChange()
                    return
                }
                block = current
                block.replaceSubrange(0..<(size - i), with: data[i..<size])
                add(String(format: "note: last block %04X padded with the radio's own %d bytes", baseAddr + i, len - (size - i)))
            }

            let r = k5WriteEEPROM(block, len: len, offset: baseAddr + i)
            if r <= 0 {
                add("error: k5_write_eeprom() [\(r)]")
                add("")
                gauge(size, i, false)
                disconnect()
                comboChange()
                return
            }
            gauge(size, i + len, true)
            i += len
        }

        add(completeMsg)
        gauge(size, size, false)

        k5Reboot()
        K5Programmer.sleepMs(300)   // give the serial port time to complete the data TX

        add("")
        disconnect()
        comboChange()
    }

    /// WriteFirmwareButtonClick()
    public func writeFirmwareButtonClick() {
        if port.connected { return }

        guard let picked = ui?.openDialog(.openFirmware, title: "Select a FIRMWARE file to upload") else { return }
        let name = K5Programmer.withDefaultExt(picked)

        bootloaderVer = []
        firmwareVer = []

        if loadFile(name) == 0 {
            ui?.messageBoxError("No data loaded")
            return
        }

        clearMemo()
        add("")
        add(String(format: "Loaded %u (0x%04X) bytes (max 0x%04X) from ..", UInt32(loadfileData.count), UInt32(loadfileData.count), K5.flashSize))
        add(loadfileName)

        if loadfileData.count < 1000 {
            ui?.messageBoxError("File appears to be to small to be a firmware file")
            return
        }

        // not in k5prog-win 0.1.26: UV-K5 V3 / UV-K1 images go to their own bootloader protocol
        if let py = FirmwareFile.processPY32(loadfileData) {
            writeFirmwarePY32(py)
            return
        }

        let fw = FirmwareFile.process(loadfileData)
        loadfileData = fw.data
        if fw.deobfuscated {
            add("")
            add("firmware file de-obfuscated")
        }
        if let v = fw.version {
            firmwareVer = v
            add("")
            add("firmware file version '" + firmwareVer.latin1 + "'")
        }

        if fw.encrypted {
            ui?.messageBoxError("File doesn't appear to be valid for uploading")
            return
        }
        if loadfileData.count > K5.maxFlashSize {
            ui?.messageBoxError(String(format: "File is to large to be a firmware file (max 0x%05X)", K5.maxFlashSize))
            return
        }
        if loadfileData.count > K5.flashSize {
            ui?.messageBoxError(String(format: "File runs into bootloader area (0x%04X)\n\nUpload cancelled", K5.flashSize))
            return
        }

        if verbose > 2 {
            add("")
            add("creating firmware hex dump ..")
            add("")
            hdump(loadfileData)
        }

        // upload the firmware to the radio

        add("")
        if !connect() { return }
        comboChange()

        add("")
        add("Uploading firmware to the radio ..")

        var r = k5WaitFlashMessage()
        if r <= 0 {
            // radio is either turned off or is not in firmware update mode
            r = helloWithRetries()
            add("")
            if r == 0 { fail("radio not detected"); return }
            if r > 0 { fail(K5Programmer.msgNotFlashMode); return }
        } else {
            add("")
        }

        // not in k5prog-win 0.1.26: never send a DP32G030 image to a PY32F071 bootloader
        if bootloaderVer.first == UInt8(ascii: "7") {
            fail("error: bootloader '" + bootloaderVer.latin1 + "' is a UV-K5 V3 / UV-K1 bootloader, this firmware file is for UV-K5 V1 / K6 - upload cancelled")
            return
        }

        // the bootloader will at times refuse the firmware version
        firmwareVer = FirmwareFile.versionForBootloader(firmware: firmwareVer, bootloader: bootloaderVer)

        // pass the firmware version to the bootloader, it will either allow the upload, or not
        r = k5SendFlashVersionMessage(firmwareVer)
        if r <= 0 {
            add("error: firmware upload refused")
            add("")
            disconnect()
            comboChange()
            return
        }

        add("")
        if verbose <= 0 { add("writing firmware ..") }

        let total = loadfileData.count
        gauge(total, 0, true)

        var i = 0
        while i < total {
            let len = min(total - i, K5.flashBlockSize)
            r = k5WriteFlash(loadfileData[i..<(i + len)], offset: i, firmwareSize: total)
            if r <= 0 {
                add("error: k5_write_flash() [\(r)]")
                add("")
                gauge(total, i, false)
                disconnect()
                comboChange()
                return
            }
            gauge(total, i + len, true)
            i += K5.flashBlockSize
        }

        add("write FLASH complete")
        gauge(total, total, false)

        k5Reboot()
        K5Programmer.sleepMs(300)   // give the serial port time to complete the data TX

        add("")
        disconnect()
        comboChange()
    }

    // MARK: - UV-K5 V3 / UV-K1 (PY32F071, bootloader 7.xx) — not part of k5prog-win 0.1.26
    //
    // Same packet framing/CRC/XOR as the V1. Protocol as in muzkr's serialtool _prog.py:
    //   0x0518 beacon:  uid[16] + bootloader version[16]
    //   0x0530:         first 4 chars of the bootloader version, once per beacon, 3 times
    //   0x0519 (268):   stamp LE32, page LE16, page count LE16, 4 x 00, 256 data (00 padded)
    //   0x051A (8):     stamp LE32, page LE16, error LE16
    // No 0x05DD at the end: the bootloader starts the new firmware by itself.

    /// Wait for 5 valid beacon intervals (5..1000 ms) in a row.
    private func py32WaitBeacons() -> Bool {
        var acc = 0
        var last = Date()   // k5WaitFlashMessage() has just consumed one beacon
        let r = waitLoop(5000) {
            let d = rx.queue[0]
            rxDebug(d)
            let beacon = d.count - 2 >= 36 && d[0] == 0x18 && d[1] == 0x05
            clearRxPacket0()
            guard beacon else { return nil }
            let now = Date()
            let dt = now.timeIntervalSince(last) * 1000
            last = now
            if dt >= 5 && dt <= 1000 {
                acc += 1
                if acc >= K5.py32BeaconsNeeded { return 1 }
            } else {
                acc = 0
            }
            return nil
        }
        return r == 1
    }

    /// Handshake: answer 3 beacons with 0x0530 + 4 version chars.
    private func py32Handshake() -> Bool {
        var v = Array(bootloaderVer.prefix(4))
        v += [UInt8](repeating: 0, count: 4 - v.count)
        let msg: [UInt8] = [0x30, 0x05, 0x04, 0x00] + v
        for _ in 0..<K5.py32HandshakeCount {
            let r = waitLoop(2000) {
                let d = rx.queue[0]
                rxDebug(d)
                let beacon = d.count >= 2 && d[0] == 0x18 && d[1] == 0x05
                clearRxPacket0()
                return beacon ? 1 : nil
            }
            if r != 1 { return false }
            if k5SendBuf(msg) <= 0 { return false }
            K5Programmer.sleepMs(50)
        }
        // "waiting for the beacons to stop", then drop whatever is left
        K5Programmer.sleepMs(200)
        clearRxPacketQueue()
        return true
    }

    /// One 0x0519 page. Returns 1 = ok, 0 = no answer, < 0 = bootloader error code.
    func py32WriteFlashPage(_ image: [UInt8], page: Int, pages: Int, stamp: UInt32) -> Int {
        guard port.connected else { return 0 }
        let off = page * K5.py32PageSize
        let len = min(K5.py32PageSize, image.count - off)
        if verbose > 0 {
            add(String(format: "write_flash  page %3d/%d  offset %05X  len %d", page + 1, pages, off, len))
        }

        var b = [UInt8](repeating: 0, count: 4 + 12 + K5.py32PageSize)
        b[0] = 0x19; b[1] = 0x05
        b[2] = UInt8((12 + 256) & 0xFF); b[3] = UInt8((12 + 256) >> 8)
        b[4] = UInt8(stamp & 0xFF); b[5] = UInt8((stamp >> 8) & 0xFF)
        b[6] = UInt8((stamp >> 16) & 0xFF); b[7] = UInt8(stamp >> 24)
        b[8] = UInt8(page & 0xFF); b[9] = UInt8(page >> 8)
        b[10] = UInt8(pages & 0xFF); b[11] = UInt8(pages >> 8)
        b.replaceSubrange(16..<(16 + len), with: image[off..<(off + len)])

        if k5SendBuf(b) <= 0 { return 0 }

        var err = 0
        if let r = waitLoop(3000, {
            let d = rx.queue[0]
            rxDebug(d)
            if d.count - 2 < 12 || d[0] != 0x1A || d[1] != 0x05 { clearRxPacket0(); return nil }
            let p = Int(d[8]) | (Int(d[9]) << 8)
            let e = Int(d[10]) | (Int(d[11]) << 8)
            clearRxPacket0()
            if p != page { return nil }   // answer for another page: keep waiting
            if e != 0 { err = e; return -1 }
            return 1
        }) { return r == 1 ? 1 : -err }
        return 0
    }

    /// Write Firmware for a UV-K5 V3 / UV-K1 image (called from WriteFirmwareButtonClick()).
    private func writeFirmwarePY32(_ py: FirmwareFile.PY32Result) {
        loadfileData = py.data
        if py.unpacked {
            add("")
            add("firmware file de-obfuscated")
        }
        if let v = py.version {
            firmwareVer = v
            add("")
            add("firmware file version '" + firmwareVer.latin1 + "'")
        }
        add("")
        add("firmware file is for UV-K5 V3 / UV-K1 (PY32F071, bootloader 7.xx)")

        if loadfileData.count > K5.py32FlashSize {
            ui?.messageBoxError(String(format: "File is to large for a UV-K5 V3 / UV-K1 firmware (max 0x%05X)", K5.py32FlashSize))
            return
        }

        if verbose > 2 {
            add("")
            add("creating firmware hex dump ..")
            add("")
            hdump(loadfileData)
        }

        add("")
        if !connect() { return }
        comboChange()

        add("")
        add("Uploading firmware to the radio ..")

        var r = k5WaitFlashMessage()
        if r <= 0 {
            r = helloWithRetries()
            add("")
            if r == 0 { fail("radio not detected"); return }
            if r > 0 { fail(K5Programmer.msgNotFlashMode); return }
        } else {
            add("")
        }

        let bl = bootloaderVer.latin1
        guard bootloaderVer.first == UInt8(ascii: "7") else {
            fail("error: bootloader '" + bl + "' is not a UV-K5 V3 / UV-K1 bootloader (7.xx), this firmware file is for UV-K5 V3 / UV-K1 - upload cancelled")
            return
        }
        guard FirmwareFile.bootloaderAtLeast(bl, K5.py32MinBootloader) else {
            fail("error: bootloader '" + bl + "' is too old, " + K5.py32MinBootloader + " or newer is needed - upload cancelled")
            return
        }

        if verbose > 0 { add("waiting for the bootloader ..") }
        guard py32WaitBeacons() else {
            fail("error: no steady bootloader messages - upload cancelled")
            return
        }
        if verbose > 0 { add("sending bootloader version '" + Array(bootloaderVer.prefix(4)).latin1 + "' ..") }
        guard py32Handshake() else {
            fail("error: handshake with the bootloader failed - upload cancelled")
            return
        }

        add("")
        if verbose <= 0 { add("writing firmware ..") }

        let image = loadfileData
        let total = image.count
        let pages = (total + K5.py32PageSize - 1) / K5.py32PageSize
        let stamp = UInt32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000))
        gauge(total, 0, true)

        var page = 0
        var retries = 0
        while page < pages {
            let w = py32WriteFlashPage(image, page: page, pages: pages, stamp: stamp)
            if w == 1 {
                retries = 0
                page += 1
                gauge(total, min(page * K5.py32PageSize, total), true)
                continue
            }
            if !port.connected || retries >= K5.py32MaxRetries {
                add("error: k5_write_flash() [\(w)]")
                add("")
                gauge(total, page * K5.py32PageSize, false)
                disconnect()
                comboChange()
                return
            }
            retries += 1
            if w == 0 {
                add(String(format: "error: no answer for page %d, retry %d/%d", page + 1, retries, K5.py32MaxRetries))
            } else {
                add(String(format: "error: page %d rejected [%d], retry %d/%d", page + 1, -w, retries, K5.py32MaxRetries))
            }
        }

        add("write FLASH complete")
        gauge(total, total, false)

        add("")
        disconnect()
        comboChange()
    }

    /// ReadADCButtonClick()
    public func readADCButtonClick() {
        if port.connected { return }
        add("")
        if !connect() { return }
        comboChange()
        add("")
        add("Reading ADC ..")
        let r = k5ReadADC()
        if r <= 0 {
            add("error: k5_readADC() [\(r)]")
            add("")
        }
        disconnect()
        comboChange()
    }

    /// ReadRSSIButtonClick()
    public func readRSSIButtonClick() {
        if port.connected { return }
        add("")
        if !connect() { return }
        comboChange()
        add("")
        add("Reading RSSI ..")
        let r = k5ReadRSSI()
        if r <= 0 {
            add("error: k5_readRSSI() [\(r)]")
            add("")
        }
        disconnect()
        comboChange()
    }

    /// SerialPortComboBoxSelect(): "get radio details" (also on start-up and on speed change).
    public func serialPortComboBoxSelect() {
        guard selectedPort != nil, !port.connected else { return }

        clearMemo()
        add("")
        if !connect() { return }
        comboChange()

        add("")
        add("Fetching radio details ..")

        var r = k5WaitFlashMessage()
        if r <= 0 {
            // radio is either turned off or is not in firmware update mode
            r = helloWithRetries()
            add("")
            if r == 0 { fail("radio not detected"); return }
            if r > 0 { fail("error: radio is in user mode"); return }
            // r < 0: hello saw the bootloader -> falls through to the final disconnect
        } else {
            disconnect()
            add("")
            add(r > 0 ? "radio is in firmware update mode" : "radio not detected")
            comboChange()
            return
        }

        disconnect()
        comboChange()
    }
}

extension String {
    var trimmingTrailingSpaces: String {
        var s = self
        while s.last == " " { s.removeLast() }
        return s
    }
}
