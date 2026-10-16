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

import AppKit
import UniformTypeIdentifiers
import K5Core

/// macOS replacement for TForm1 (Unit1.cpp/.dfm of k5prog-win v0.1.26).
final class MainWindowController: NSWindowController, NSWindowDelegate, K5UI {
    let prog = K5Programmer()
    private let worker = DispatchQueue(label: "k5prog.worker")
    private var busy = false   // a button handler is running on the worker thread

    // Panel2
    private let portLabel = NSTextField(labelWithString: "Serial port ")
    private let portPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let speedLabel = NSTextField(labelWithString: "Serial speed ")
    private let speedPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let verboseSlider = NSSlider(value: 1, minValue: 0, maxValue: 3, target: nil, action: nil)
    private let verboseLabel = NSTextField(labelWithString: "Verbose 1")
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let readConfigButton = NSButton(title: "Read Configuration", target: nil, action: nil)
    private let writeConfigButton = NSButton(title: "Write Configuration", target: nil, action: nil)
    private let readCalibButton = NSButton(title: "Read Calibration", target: nil, action: nil)
    private let writeCalibButton = NSButton(title: "Write Calibration", target: nil, action: nil)
    private let writeFirmwareButton = NSButton(title: "Write Firmware", target: nil, action: nil)
    private let memoryEditorButton = NSButton(title: "Memory Editor\u{2026}", target: nil, action: nil)

    // Memo1
    private let memoScroll = NSTextView.scrollableTextView()
    private var memo: NSTextView { memoScroll.documentView as! NSTextView }
    private let memoFont = NSFont(name: "Menlo", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    // StatusBar1 + CGauge1
    private let statusTime = NSTextField(labelWithString: "")
    /// 2.0: which radio is on the cable, found by a quiet check (not in the log)
    private let radioStatus = Pill(compact: false)
    private let statusSpacer = NSView()   // pushes the radio pill right while the bar is hidden
    private let gaugeBar = NSProgressIndicator()
    private let gaugeLabel = NSTextField(labelWithString: "")
    private var timer: Timer?

    // settings / dialogs
    private let settings: AppSettings            // the original's k5prog_win.ini
    private let exeDir: String
    private var savedPortName = ""               // m_serial.port_name as read from the settings
    private var dialogFileNames: [FileDialog: String] = [:]

    init() {
        let (store, dir) = MainWindowController.makeSettings()
        settings = store
        exeDir = dir
        let window = KeyWindow(contentRect: NSRect(x: 297, y: 139, width: 720, height: 480),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
        window.minSize = NSSize(width: 660, height: 470)
        window.isRestorable = false
        super.init(window: window)
        shouldCascadeWindows = false
        window.delegate = self
        window.title = "\(K5.appTitle) v\(K5.version)"
        window.escapeHandler = { [weak self] in self?.formKeyDownEscape() }
        prog.ui = self
        buildUI()
        formCreate()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - settings ("ChangeFileExt(Application->ExeName, \".ini\")" in the original)

    /// Settings live in UserDefaults (~/Library/Preferences/io.github.eruban.k5k1prog.plist).
    /// The K5K1Prog.ini of 1.0 / 1.1 (next to the .app, or in Application Support) is imported
    /// once and deleted. `K5PROG_SETTINGS_SUITE` gives dev / UI-test runs their own settings.
    /// File dialogs of the app bundle start in ~/Documents; a bare binary (swift run) keeps
    /// the original: the folder of the exe.
    static func makeSettings() -> (AppSettings, exeDir: String) {
        let fm = FileManager.default
        let bundle = Bundle.main.bundleURL
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let suite = ProcessInfo.processInfo.environment["K5PROG_SETTINGS_SUITE"].flatMap { $0.isEmpty ? nil : $0 }
        let store = AppSettings(defaults: suite.flatMap { UserDefaults(suiteName: $0) } ?? .standard)
        guard bundle.pathExtension == "app" else {
            return (store, exe.deletingLastPathComponent().path)
        }
        let iniName = exe.deletingPathExtension().lastPathComponent + ".ini"
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(K5.appTitle)
        if suite == nil && !bundle.path.contains("/AppTranslocation/") {
            store.importIni(candidates: [support.appendingPathComponent(iniName).path,
                                         bundle.deletingLastPathComponent().appendingPathComponent(iniName).path],
                            removeEmptyDir: support.path)
        }
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first?.path
        return (store, documents ?? NSHomeDirectory())
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        for b in [clearButton, readConfigButton, writeConfigButton, readCalibButton, writeCalibButton,
                  writeFirmwareButton, memoryEditorButton] {
            b.bezelStyle = .rounded
            b.target = self
        }
        clearButton.action = #selector(clearButtonClick)
        clearButton.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        readConfigButton.action = #selector(readConfigClick)
        writeConfigButton.action = #selector(writeConfigClick)
        readCalibButton.action = #selector(readCalibClick)
        writeCalibButton.action = #selector(writeCalibClick)
        writeFirmwareButton.action = #selector(writeFirmwareClick)
        memoryEditorButton.action = #selector(memoryEditorClick)
        memoryEditorButton.bezelColor = K5MainWindowStyle.accent
        memoryEditorButton.toolTip = "Edit channels and settings (2.0, work in progress)"

        clearButton.toolTip = "Clear the memo"
        readConfigButton.toolTip = "Download configuration data from radio"
        writeConfigButton.toolTip = "Upload configuration data to radio"
        readCalibButton.toolTip = "Read the radios calibration settings"
        writeCalibButton.toolTip = "Write the radios calibration settings"
        writeFirmwareButton.toolTip = "Upload firmware file to radio"
        verboseSlider.toolTip = "Verbose level (0..3)"

        portPopup.target = self
        portPopup.action = #selector(serialPortSelect)
        NotificationCenter.default.addObserver(self, selector: #selector(serialPortDropDown),
                                               name: NSPopUpButton.willPopUpNotification, object: portPopup)
        speedPopup.target = self
        speedPopup.action = #selector(serialSpeedSelect)

        verboseSlider.numberOfTickMarks = 4
        verboseSlider.allowsTickMarkValuesOnly = true
        verboseSlider.target = self
        verboseSlider.action = #selector(verboseChange)

        memo.isEditable = false
        memo.font = memoFont
        memo.isRichText = false
        memo.textContainerInset = NSSize(width: 4, height: 4)
        // 2.0: long lines wrap at the window edge (the original scrolled sideways). Hex dumps keep
        // their columns: a wrapped line continues under the first character.
        memoScroll.hasHorizontalScroller = false
        memo.isHorizontallyResizable = false
        memo.autoresizingMask = [.width]
        memo.textContainer?.widthTracksTextView = true
        memo.textContainer?.containerSize = NSSize(width: memoScroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)

        gaugeBar.style = .bar
        gaugeBar.isIndeterminate = false
        gaugeBar.minValue = 0
        gaugeBar.isHidden = true
        gaugeLabel.isHidden = true
        gaugeLabel.font = NSFont.boldSystemFont(ofSize: 11)
        statusTime.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)   // digits don't make the bar jump

        // 2.0 layout: port / speed / verbose on top, the log on the left, the buttons in a column
        // on the right (grouped: Clear | configuration | calibration | firmware | editor).
        let row1 = NSStackView(views: [portLabel, portPopup, speedLabel, speedPopup, NSView(), verboseLabel,
                                       verboseSlider])
        row1.spacing = 8
        func separator() -> NSView {
            let box = NSBox()
            box.boxType = .separator
            return box
        }
        let column = NSStackView(views: [clearButton, separator(),
                                         readConfigButton, writeConfigButton, separator(),
                                         readCalibButton, writeCalibButton, separator(),
                                         writeFirmwareButton, separator(),
                                         memoryEditorButton])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        for v in column.arrangedSubviews {
            v.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
            if let b = v as? NSButton { b.alignment = .left; b.controlSize = .large }
        }
        let status = NSStackView(views: [statusTime, gaugeBar, gaugeLabel, statusSpacer, radioStatus])
        status.alignment = .centerY
        status.spacing = 12
        // the bar takes all the room between the clock and the radio pill while it is shown
        gaugeBar.setContentHuggingPriority(.init(1), for: .horizontal)
        gaugeBar.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        gaugeBar.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        memoScroll.borderType = .bezelBorder
        for v in [row1, column, memoScroll, status] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        portPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        speedPopup.widthAnchor.constraint(equalToConstant: 130).isActive = true
        verboseSlider.widthAnchor.constraint(equalToConstant: 70).isActive = true
        // as wide as the longest clock text ("Wednesday 30 Sep 2026  00:00:00"), not more
        let longest = " Wednesday 30 Sep 2026  00:00:00" as NSString
        let clockWidth = ceil(longest.size(withAttributes: [.font: statusTime.font as Any]).width) + 8
        statusTime.widthAnchor.constraint(equalToConstant: clockWidth).isActive = true
        gaugeLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true

        NSLayoutConstraint.activate([
            row1.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            row1.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            row1.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            column.topAnchor.constraint(equalTo: row1.bottomAnchor, constant: 12),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            column.widthAnchor.constraint(equalToConstant: 180),
            column.bottomAnchor.constraint(lessThanOrEqualTo: status.topAnchor, constant: -8),
            memoScroll.topAnchor.constraint(equalTo: row1.bottomAnchor, constant: 12),
            memoScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            memoScroll.trailingAnchor.constraint(equalTo: column.leadingAnchor, constant: -14),
            memoScroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -6),
            status.heightAnchor.constraint(equalToConstant: 40),   // 2.0: room for the two-line radio pill
        ])
    }

    // MARK: - FormCreate / WMInitGUI / loadSettings / saveSettings

    private func formCreate() {
        updateSerialPortCombo()
        portPopup.selectItem(at: 0)

        speedPopup.removeAllItems()
        for (title, value) in K5.serialSpeeds {
            speedPopup.addItem(withTitle: title)
            speedPopup.lastItem?.tag = value
        }
        speedPopup.selectItem(withTag: K5.defaultSerialSpeed)

        restoreFrame()
        // WM_INIT_GUI
        DispatchQueue.main.async { [weak self] in self?.wmInitGUI() }
    }

    private func wmInitGUI() {
        loadSettings()
        // common modes: keep ticking while a message box / file dialog is open (like WM_TIMER on Windows)
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.timerTick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let p = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.probeRadio() }
        RunLoop.main.add(p, forMode: .default)
        probeTimer = p
        serialPortSelect()
        if ProcessInfo.processInfo.environment["K5PROG_UITEST"] != nil { DispatchQueue.main.async { self.uiTestStep() } }
    }

    // MARK: - UI test mode (env driven, used to exercise the real .app)
    //   K5PROG_UITEST="readconfig,readcalib,writecalib,writeconfig,firmware,quit"
    //   K5PROG_UITEST_OPEN=<path>  K5PROG_UITEST_SAVE=<path>  K5PROG_UITEST_MEMO=<file>

    private lazy var uiTestSteps: [String] = (ProcessInfo.processInfo.environment["K5PROG_UITEST"] ?? "")
        .split(separator: ",").map(String.init)
    private var uiTestIndex = 0
    private var uiTestWaits = 0

    private func uiTestStep() {
        // wait for the first radio check (the buttons follow it), at most ~5 s
        if busy || (radioState == nil && portPopup.indexOfSelectedItem > 0 && uiTestWaits < 25) {
            if !busy { uiTestWaits += 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.uiTestStep() }
            return
        }
        let env = ProcessInfo.processInfo.environment
        if let memoFile = env["K5PROG_UITEST_MEMO"], uiTestIndex > 0 {
            flushMemo()
            let text = "=== " + uiTestSteps[uiTestIndex - 1] + "\n" + memo.string + "\n"
            if let h = FileHandle(forWritingAtPath: memoFile) {
                h.seekToEndOfFile(); h.write(text.data(using: .utf8)!); try? h.close()
            } else {
                FileManager.default.createFile(atPath: memoFile, contents: text.data(using: .utf8))
            }
        }
        guard uiTestIndex < uiTestSteps.count else { return }
        let step = uiTestSteps[uiTestIndex]
        uiTestIndex += 1
        switch step {
        case "readconfig": readConfigButton.performClick(nil)
        case "writeconfig": writeConfigButton.performClick(nil)
        case "readcalib": readCalibButton.performClick(nil)
        case "writecalib": writeCalibButton.performClick(nil)
        case "firmware": writeFirmwareButton.performClick(nil)
        case "clear": clearButton.performClick(nil)
        case "editor": memoryEditorButton.performClick(nil)
        case "snap": uiTestSnap()
        case "wait":
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.uiTestStep() }
            return
        case "settings": (NSApp.delegate as? AppDelegate)?.showSettings(nil)
        case "gauge": gauge(max: 100, progress: 40, visible: true)   // the progress bar as during an operation
        case "quit": window?.performClose(nil); return
        case "probe-quit":   // close while the quiet radio check holds the port
            if let p = portPopup.titleOfSelectedItem { _ = runEditorProbe(port: p, blocks: []) { _ in } }
            func closeWhenOpen(_ n: Int) {
                if prog.connected || n > 200 { window?.performClose(nil); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { closeWhenOpen(n + 1) }
            }
            closeWhenOpen(0)
            return
        default:
            // editor steps: editor-import (K5PROG_UITEST_OPEN, a .bin is read as K5PROG_UITEST_BIN_PROFILE),
            // editor-write (no confirmation), editor-export (K5PROG_UITEST_SAVE)
            if step.hasPrefix("editor-"), let ed = MemoryEditorWindowController.open.values.first {
                ed.uiTest(String(step.dropFirst(7)))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.uiTestStep() }
    }

    /// Saves every window as PNG into K5PROG_UITEST_SNAP (drawn by the app itself, no screen
    /// recording permission needed).
    private func uiTestSnap() {
        guard let dir = ProcessInfo.processInfo.environment["K5PROG_UITEST_SNAP"] else { return }
        flushMemo()
        for (n, w) in NSApp.windows.filter(\.isVisible).enumerated() {
            guard let v = w.contentView?.superview ?? w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
            v.cacheDisplay(in: v.bounds, to: rep)
            let name = "\(uiTestIndex)-\(n)-" + w.title.replacingOccurrences(of: "/", with: "_") + ".png"
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
    }

    /// The saved window frame. Applied in init, before the window is first shown: on a
    /// second display the window used to flash at its default place on the main screen first.
    private func restoreFrame() {
        let ini = settings
        if let w = window, let screen = NSScreen.screens.first {
            let h0 = screen.frame.maxY
            let f = w.frame
            let curTop = Int(h0 - f.maxY), curLeft = Int(f.minX)
            let top = ini.readInteger("MainForm", "Top", curTop)
            let left = ini.readInteger("MainForm", "Left", curLeft)
            let width = max(ini.readInteger("MainForm", "Width", Int(f.width)), Int(w.minSize.width))
            let height = max(ini.readInteger("MainForm", "Height", Int(f.height)), Int(w.minSize.height))
            var nf = NSRect(x: CGFloat(left), y: h0 - CGFloat(top) - CGFloat(height),
                            width: CGFloat(width), height: CGFloat(height))
            // keep it on a screen (the original clamps in WMWindowPosChanging)
            let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(nf.insetBy(dx: 40, dy: 40)) }
            if !visible {
                let vf = screen.visibleFrame
                nf.size.width = min(nf.width, vf.width)
                nf.size.height = min(nf.height, vf.height)
                nf.origin = NSPoint(x: vf.midX - nf.width / 2, y: vf.midY - nf.height / 2)
            }
            w.setFrame(nf, display: false)
            if ProcessInfo.processInfo.environment["K5PROG_DEBUG"] != nil {
                FileHandle.standardError.write("restoreFrame \(nf) -> \(w.frame)\n".data(using: .utf8)!)
            }
        }
    }

    private func loadSettings() {
        let ini = settings

        let i = ini.readInteger("GUI", "Verbose", Int(verboseSlider.integerValue))
        let v = (i < 0) ? 1 : (i > 3) ? 1 : i
        prog.verbose = v
        verboseSlider.integerValue = v
        verboseLabel.stringValue = "Verbose \(v)"

        savedPortName = ini.readString("SerialPort", "Name", portPopup.titleOfSelectedItem ?? "None")
        if let idx = portIndex(of: savedPortName) { portPopup.selectItem(at: idx) }
        serialPortComboBoxChange()
        // [SerialPort] Speed is written but NOT read back by the original (#if 0) -> always 38400
    }

    private func saveSettings() {
        let ini = settings  // the original deletes and re-writes the ini; here every key is set
        if let w = window, let screen = NSScreen.screens.first {
            let f = w.frame
            if ProcessInfo.processInfo.environment["K5PROG_DEBUG"] != nil {
                FileHandle.standardError.write("saveSettings frame \(f)\n".data(using: .utf8)!)
            }
            ini.writeInteger("MainForm", "Top", Int((screen.frame.maxY - f.maxY).rounded()))
            ini.writeInteger("MainForm", "Left", Int(f.minX.rounded()))
            ini.writeInteger("MainForm", "Width", Int(f.width.rounded()))
            ini.writeInteger("MainForm", "Height", Int(f.height.rounded()))
        }
        ini.writeInteger("GUI", "Verbose", prog.verbose)
        ini.writeString("SerialPort", "Name", currentPortName())
        ini.writeInteger("SerialPort", "Speed", speedPopup.selectedItem?.tag ?? K5.defaultSerialSpeed)
    }

    /// m_serial.port_name: the last port that was opened, else what the settings said.
    private func currentPortName() -> String {
        prog.portName.isEmpty ? savedPortName : prog.portName
    }

    // MARK: - serial port combo

    private func portIndex(of name: String) -> Int? {
        let i = portPopup.indexOfItem(withTitle: name)
        return i >= 0 ? i : nil
    }

    private func updateSerialPortCombo() {
        let previous = currentPortName()
        portPopup.removeAllItems()
        portPopup.addItem(withTitle: "None")
        for p in SerialPort.listPorts() { portPopup.addItem(withTitle: p) }
        if !previous.isEmpty, let i = portIndex(of: previous) { portPopup.selectItem(at: i) } else { portPopup.selectItem(at: 0) }
        serialPortComboBoxChange()
    }

    @objc private func serialPortDropDown() {
        // OnDropDown -> updateSerialPortCombo(), but keep the current selection
        let current = portPopup.titleOfSelectedItem
        updateSerialPortCombo()
        if let c = current, let i = portIndex(of: c) { portPopup.selectItem(at: i) }
        serialPortComboBoxChange()
    }

    /// SerialPortComboBoxChange(). 2.0: the buttons also follow the radio on the cable (quiet
    /// check): normal mode enables configuration, calibration and the editor, firmware update mode
    /// only Write Firmware, no radio nothing. The original only looked at the port selection.
    private func serialPortComboBoxChange() {
        let connected = prog.connected
        let enabled = !connected && !busy && portPopup.indexOfSelectedItem > 0
        var normal = false, flash = false
        switch radioState {
        case .radio?: normal = true
        case .flashMode?: flash = true
        default: break
        }
        for b in [readConfigButton, writeConfigButton, readCalibButton, writeCalibButton, memoryEditorButton] {
            b.isEnabled = enabled && normal
        }
        writeFirmwareButton.isEnabled = enabled && flash
        portPopup.isEnabled = !connected && !busy
        speedPopup.isEnabled = !connected && !busy
    }

    /// The original fetched the radio details into the log on start-up and on every port /
    /// speed change ("radio not detected" when the radio was not plugged in yet). 2.0: a quiet
    /// check every 2 s instead; the result is shown in the status bar, the log is left alone.
    @objc private func serialPortSelect() {
        if portPopup.indexOfSelectedItem > 0, let t = portPopup.titleOfSelectedItem { savedPortName = t }
        radioState = nil
        missed = 0
        showRadioState()
        serialPortComboBoxChange()
        probeRadio()
    }

    private enum RadioOnCable: Equatable { case none, unplugged, flashMode(String), radio(String) }
    private var radioState: RadioOnCable?
    private var missed = 0
    private var probeTimer: Timer?

    private func probeRadio() {
        guard let w = window, w.isKeyWindow, NSApp.isActive, w.attachedSheet == nil,
              portPopup.indexOfSelectedItem > 0, let port = portPopup.titleOfSelectedItem else { return }
        _ = runEditorProbe(port: port, blocks: []) { [weak self] r in
            guard let self, self.portPopup.titleOfSelectedItem == port else { return }
            let s: RadioOnCable
            switch r {
            case .noPort: s = .unplugged
            case .noRadio: s = .none
            case .flashMode(let bl): s = .flashMode(bl)
            case .radio(let fw, _): s = .radio(fw)
            }
            // a radio in firmware update mode only beacons now and then: one miss is not "gone"
            if s == .none, let cur = self.radioState, cur != .none, cur != .unplugged {
                self.missed += 1
                if self.missed < 2 { return }
            }
            self.missed = 0
            if s != self.radioState { self.radioState = s; self.showRadioState(); self.serialPortComboBoxChange() }
        }
    }

    private func showRadioState() {
        guard portPopup.indexOfSelectedItem > 0 else { radioStatus.set("", tint: .systemGray); return }
        switch radioState {
        case nil:
            radioStatus.set("Checking\u{2026}", "hello: —", tint: .systemGray)
            radioStatus.setToolTip(nil)
        case .none?:
            radioStatus.set("No radio", "turn it on, check the cable", tint: .systemGray)
            radioStatus.setToolTip("No answer: turn the radio on and check the cable")
        case .unplugged?:
            radioStatus.set("Cable unplugged", "no serial port", tint: .systemGray)
            radioStatus.setToolTip(nil)
        case .flashMode(let bl)?:
            let model = Self.modelForBootloader(bl)
            radioStatus.set("Firmware update mode", (bl.isEmpty ? "bootloader ?" : "bootloader " + bl) + (model.map { " · " + $0 } ?? ""),
                            tint: bl.hasPrefix("1.") ? .systemRed : .systemOrange)
            radioStatus.setToolTip("Radio started with PTT held: ready for Write Firmware")
        case .radio(let fw)?:
            radioStatus.set("Normal mode", "hello: " + fw, tint: .systemGreen)
            radioStatus.setToolTip("Radio on the cable and its answer to hello (firmware string)")
        }
    }

    static func modelForBootloader(_ bl: String) -> String? {
        if bl.hasPrefix("1.") { return "UV-K5 V2 (not supported)" }
        if bl.hasPrefix("2.") { return "UV-K5 V1" }
        if bl.hasPrefix("7.") { return "UV-K1 / K5 V3" }
        return nil
    }

    func windowDidBecomeKey(_ notification: Notification) { probeRadio() }

    @objc private func serialSpeedSelect() { serialPortSelect() }

    @objc private func verboseChange() {
        prog.verbose = verboseSlider.integerValue
        verboseLabel.stringValue = "Verbose \(verboseSlider.integerValue)"
    }

    // MARK: - buttons

    @objc private func clearButtonClick() {
        memo.string = ""
        memoLineCount = 0
    }
    @objc private func readConfigClick() { run { $0.readConfigButtonClick() } }
    @objc private func writeConfigClick() { run { $0.writeConfigButtonClick() } }
    @objc private func readCalibClick() { run { $0.readCalibrationButtonClick() } }
    @objc private func writeCalibClick() { run { $0.writeCalibrationButtonClick() } }
    @objc private func writeFirmwareClick() { run { $0.writeFirmwareButtonClick() } }
    /// Memory Editor (2.0): reads the radio on the selected port, then opens its editor window
    /// (one window per port; an open one is brought to the front).
    @objc func memoryEditorClick() {
        guard portPopup.indexOfSelectedItem > 0, let port = portPopup.titleOfSelectedItem else {
            NSSound.beep()
            memoAdd("")
            memoAdd("select the serial port of the radio first")
            return
        }
        if let w = MemoryEditorWindowController.open[port] { w.showWindow(nil); return }
        guard memoryEditorButton.isEnabled else { NSSound.beep(); return }   // ⌘E: same rule as the button
        _ = runEditorRead(port: port) { [weak self] r in
            guard let self else { return }
            guard let r else { return }   // the reason is in the log
            MemoryEditorWindowController.show(host: self, port: port, memory: r.memory, firmware: r.firmware)
        }
    }

    var defaults: UserDefaults { settings.defaults }

    /// The Memory Editor's quiet radio check. Skipped (false) while anything else runs; the
    /// main window's controls are not touched and nothing goes to the log.
    private(set) var probing = false
    private var closing = false   // the app is closing: no new radio checks
    var isIdle: Bool { !busy && !probing && !prog.connected }

    func runEditorProbe(port: String, blocks: [Int], done: @escaping (K5Programmer.ProbeResult) -> Void) -> Bool {
        guard isIdle, !closing else { return false }
        probing = true
        prog.selectedSpeed = speedPopup.selectedItem?.tag ?? K5.defaultSerialSpeed
        worker.async { [weak self] in
            guard let self else { return }
            let r = self.prog.editorProbe(port: port, blocks: blocks)
            DispatchQueue.main.async {
                self.probing = false
                done(r)
            }
        }
        return true
    }

    /// Editor operations: like `run`, on the worker thread and one at a time, but on the
    /// editor's own port. `done` is called on the main thread. False when busy.
    @discardableResult
    func runEditorRead(port: String, done: @escaping ((memory: [UInt8], firmware: String)?) -> Void) -> Bool {
        runOnPort(port, onBusy: { done(nil) }) { p in
            let r = p.editorRead()
            DispatchQueue.main.async { done(r) }
        }
    }

    @discardableResult
    func runEditorWrite(port: String, snapshot: [UInt8], edited: [UInt8], firmware: String, backupPath: String,
                        done: @escaping (K5Programmer.EditorResult) -> Void) -> Bool {
        runOnPort(port, onBusy: { done(.failed("Another operation is running. Nothing was written; try again.")) }) { p in
            let r = p.editorWrite(snapshot: snapshot, edited: edited, firmware: firmware, backupPath: backupPath)
            DispatchQueue.main.async { done(r) }
        }
    }

    /// Like `run` on the editor's port. When something else runs, `onBusy` is called (also when
    /// that is found only after waiting for the quiet radio check), so the caller never waits forever.
    private func runOnPort(_ port: String, onBusy: @escaping () -> Void, _ handler: @escaping (K5Programmer) -> Void) -> Bool {
        if probing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in _ = self?.runOnPort(port, onBusy: onBusy, handler) }
            return true
        }
        if busy || prog.connected {
            NSSound.beep()
            memoAdd("")
            memoAdd("busy: another operation is running, try again when it has finished")
            DispatchQueue.main.async(execute: onBusy)
            return false
        }
        prog.selectedPort = port
        prog.selectedSpeed = speedPopup.selectedItem?.tag ?? K5.defaultSerialSpeed
        busy = true
        serialPortComboBoxChange()
        if NSApp.isActive { window?.orderFront(nil) }   // the log shows what happens; never steal focus
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.worker.async {
                handler(self.prog)
                DispatchQueue.main.async {
                    self.busy = false
                    self.serialPortComboBoxChange()
                }
            }
        }
        return true
    }


    /// Runs a button handler on the worker thread (the original ran them on the GUI
    /// thread pumping ProcessMessages; one at a time, exactly like there).
    private func run(_ handler: @escaping (K5Programmer) -> Void) {
        if probing {   // the editor's quiet radio check takes < 0.5 s: run right after it
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.run(handler) }
            return
        }
        if busy || prog.connected { return }
        let idx = portPopup.indexOfSelectedItem
        prog.selectedPort = idx > 0 ? portPopup.titleOfSelectedItem : nil
        prog.selectedSpeed = speedPopup.selectedItem?.tag ?? K5.defaultSerialSpeed
        busy = true
        serialPortComboBoxChange()
        // Start the worker only after the button's action has fully returned:
        // NSButtonCell.performClick (keyboard / accessibility press) spins a private
        // run loop mode in which the main queue is not serviced, so a worker that
        // immediately needs the main thread (file dialog) would deadlock.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.worker.async {
                handler(self.prog)
                DispatchQueue.main.async {
                    self.busy = false
                    self.serialPortComboBoxChange()
                }
            }
        }
    }

    // MARK: - Timer1Timer

    private lazy var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = " EEEE dd MMM yyyy  HH:mm:ss"
        return f
    }()

    private func timerTick() {
        let s = dateFormatter.string(from: Date())
        if statusTime.stringValue != s { statusTime.stringValue = s }
    }

    // MARK: - FormKeyDown (Esc) / FormClose

    private func formKeyDownEscape() {
        if prog.connected {
            prog.port.requestAbort()     // m_serial.port.Disconnect()
        } else {
            window?.performClose(nil)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { formCloseQuery() }

    private(set) var closeConfirmed = false

    /// FormClose(): ask when busy, then disconnect + saveSettings.
    func formCloseQuery() -> Bool {
        if closeConfirmed { return true }
        // the quiet radio check (read only, at most ~2 s) is not "busy": let it end, don't ask
        closing = true
        let probeDeadline = Date().addingTimeInterval(2.5)
        while probing && !busy && Date() < probeDeadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if prog.connected || busy {
            let yes = alertYesNo("Busy readin/writing from/to the radio.\n\nStill close ?")
            if !yes { closing = false; return false }
            prog.port.requestAbort()
            // let the worker notice and release the port
            let deadline = Date().addingTimeInterval(4)
            while busy && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
        }
        timer?.invalidate()
        saveSettings()
        closeConfirmed = true
        return true
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    // MARK: - K5UI (called from the worker thread)

    private var pendingLines: [String] = []
    private var pendingClear = false
    private let pendingLock = NSLock()
    private var flushScheduled = false
    private var memoLineCount = 0

    func memoAdd(_ line: String) {
        pendingLock.lock()
        pendingLines.append(line)
        let schedule = !flushScheduled
        flushScheduled = true
        pendingLock.unlock()
        if schedule { DispatchQueue.main.async { [weak self] in self?.flushMemo() } }
    }

    func memoClear() {
        pendingLock.lock()
        pendingLines.removeAll()
        pendingClear = true
        let schedule = !flushScheduled
        flushScheduled = true
        pendingLock.unlock()
        if schedule { DispatchQueue.main.async { [weak self] in self?.flushMemo() } }
    }

    private func flushMemo() {
        pendingLock.lock()
        let lines = pendingLines
        let clear = pendingClear
        pendingLines.removeAll()
        pendingClear = false
        flushScheduled = false
        pendingLock.unlock()

        guard let storage = memo.textStorage else { return }
        if clear {
            storage.setAttributedString(NSAttributedString(string: ""))
            memoLineCount = 0
        }
        if lines.isEmpty { return }
        var text = ""
        for l in lines {
            if memoLineCount > 0 { text += "\n" }
            text += l
            memoLineCount += 1
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: memoFont, .foregroundColor: NSColor.textColor]
        storage.append(NSAttributedString(string: text, attributes: attrs))
        memo.scrollToEndOfDocument(nil)
    }

    func gauge(max: Int, progress: Int, visible: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.gaugeBar.maxValue = Double(Swift.max(max, 1))
            self.gaugeBar.doubleValue = Double(progress)
            self.gaugeBar.isHidden = !visible
            self.gaugeLabel.isHidden = !visible
            self.statusSpacer.isHidden = visible
            let pct = max > 0 ? Int((Double(progress) * 100 / Double(max)).rounded(.down)) : 0
            self.gaugeLabel.stringValue = "\(Swift.min(pct, 100))%"
        }
    }

    func connectionStateChanged() {
        DispatchQueue.main.async { [weak self] in self?.serialPortComboBoxChange() }
    }

    func messageBoxError(_ text: String) {
        onMain {
            let a = NSAlert()
            a.alertStyle = .critical
            a.messageText = K5.appTitle
            a.informativeText = text
            a.addButton(withTitle: "OK")
            a.runModal()
        }
    }

    func messageBoxYesNo(_ text: String) -> Bool {
        onMain { self.alertYesNo(text) }
    }

    private func alertYesNo(_ text: String) -> Bool {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = K5.appTitle
        a.informativeText = text
        let yes = a.addButton(withTitle: "Yes")
        let no = a.addButton(withTitle: "No")
        // MB_DEFBUTTON2: "No" is the default button
        yes.keyEquivalent = ""
        no.keyEquivalent = "\r"
        return a.runModal() == .alertFirstButtonReturn
    }

    private static let filters: [(title: String, exts: [String])] = [
        ("All files", []),
        ("Supported files *.bin *.raw", ["bin", "raw"]),
        ("BIN files", ["bin"]),
        ("RAW files", ["raw"]),
    ]

    private func initialURL(for dialog: FileDialog) -> (dir: URL, name: String) {
        if let last = dialogFileNames[dialog] {
            let u = URL(fileURLWithPath: last)
            return (u.deletingLastPathComponent(), u.lastPathComponent)
        }
        return (URL(fileURLWithPath: exeDir), dialog.defaultFileName)
    }

    func openDialog(_ dialog: FileDialog, title: String) -> String? {
        if let p = ProcessInfo.processInfo.environment["K5PROG_UITEST_OPEN"] { return p }
        return onMain {
            let panel = NSOpenPanel()
            panel.title = title
            panel.message = title
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            let (dir, _) = self.initialURL(for: dialog)
            panel.directoryURL = dir

            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
            for f in MainWindowController.filters { popup.addItem(withTitle: f.title) }
            popup.selectItem(at: 1)   // FilterIndex = 2
            let apply = { (i: Int) in
                let exts = MainWindowController.filters[i].exts
                panel.allowedContentTypes = exts.isEmpty ? [] : exts.compactMap { UTType(filenameExtension: $0) }
            }
            apply(1)
            let handler = PopupHandler { apply(popup.indexOfSelectedItem) }
            popup.target = handler
            popup.action = #selector(PopupHandler.changed)
            let label = NSTextField(labelWithString: "Files of type:")
            let acc = NSStackView(views: [label, popup])
            acc.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
            panel.accessoryView = acc
            panel.isAccessoryViewDisclosed = true

            let ok = panel.runModal() == .OK
            withExtendedLifetime(handler) {}
            guard ok, let url = panel.url else { return nil }
            self.dialogFileNames[dialog] = url.path
            return url.path
        }
    }

    func saveDialog(_ dialog: FileDialog, title: String) -> String? {
        if let p = ProcessInfo.processInfo.environment["K5PROG_UITEST_SAVE"] { return p }
        return onMain {
            let panel = NSSavePanel()
            panel.title = title
            panel.message = title
            let (dir, name) = self.initialURL(for: dialog)
            panel.directoryURL = dir
            panel.nameFieldStringValue = name
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            // DefaultExt = '.bin': the panel appends it (and asks before overwriting)
            if let bin = UTType(filenameExtension: "bin") { panel.allowedContentTypes = [bin] }
            panel.allowsOtherFileTypes = true
            guard panel.runModal() == .OK, let url = panel.url else { return nil }
            self.dialogFileNames[dialog] = url.path
            return url.path
        }
    }

    private func onMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
    }
}

private final class PopupHandler: NSObject {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func changed() { block() }
}

/// Window that forwards Esc (VK_ESCAPE in FormKeyDown, KeyPreview = True).
final class KeyWindow: NSWindow {
    var escapeHandler: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { escapeHandler?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { escapeHandler?(); return }
        super.keyDown(with: event)
    }
}

/// Colours of the 2.0 main window.
enum K5MainWindowStyle {
    /// orange of the app logo (#ff8a3d)
    static let accent = NSColor(srgbRed: 1.0, green: 0x8a / 255.0, blue: 0x3d / 255.0, alpha: 1)
}
