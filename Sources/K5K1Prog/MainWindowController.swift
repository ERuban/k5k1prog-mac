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
    private let readADCButton = NSButton(title: "Read ADC", target: nil, action: nil)
    private let readRSSIButton = NSButton(title: "Read RSSI", target: nil, action: nil)

    // Memo1
    private let memoScroll = NSTextView.scrollableTextView()
    private var memo: NSTextView { memoScroll.documentView as! NSTextView }
    private let memoFont = NSFont(name: "Menlo", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    // StatusBar1 + CGauge1
    private let statusTime = NSTextField(labelWithString: "")
    private let statusBreak = NSTextField(labelWithString: "")
    private let gaugeBar = NSProgressIndicator()
    private let gaugeLabel = NSTextField(labelWithString: "")
    private var timer: Timer?

    // settings / dialogs
    private let iniPath: String
    private let exeDir: String
    private var savedPortName = ""               // m_serial.port_name as read from the ini
    private var dialogFileNames: [FileDialog: String] = [:]

    init() {
        let (ini, dir) = MainWindowController.locateIni()
        iniPath = ini
        exeDir = dir
        let window = KeyWindow(contentRect: NSRect(x: 297, y: 139, width: 900, height: 420),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable],
                               backing: .buffered, defer: false)
        window.minSize = NSSize(width: 900, height: 300)
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

    // MARK: - ini location ("ChangeFileExt(Application->ExeName, \".ini\")")

    /// <dir containing "K5K1 Prog.app">/K5K1Prog.ini (or next to a bare binary); when that
    /// folder is not writable, ~/Library/Application Support/K5K1 Prog/K5K1Prog.ini.
    static func locateIni() -> (ini: String, exeDir: String) {
        let bundle = Bundle.main.bundleURL
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let base = exe.deletingPathExtension().lastPathComponent
        let dir = bundle.pathExtension == "app" ? bundle.deletingLastPathComponent() : exe.deletingLastPathComponent()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(K5.appTitle)
        let ini = IniFile.location(appDir: dir.path, name: base + ".ini", supportDir: support.path)
        let translocated = dir.path.contains("/AppTranslocation/")
        return (ini, translocated ? NSHomeDirectory() : dir.path)
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        for b in [clearButton, readConfigButton, writeConfigButton, readCalibButton, writeCalibButton,
                  writeFirmwareButton, readADCButton, readRSSIButton] {
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
        readADCButton.action = #selector(readADCClick)
        readRSSIButton.action = #selector(readRSSIClick)

        clearButton.toolTip = "Clear the memo"
        readConfigButton.toolTip = "Download configuration data from radio"
        writeConfigButton.toolTip = "Upload configuration data to radio"
        readCalibButton.toolTip = "Read the radios calibration settings"
        writeCalibButton.toolTip = "Write the radios calibration settings"
        writeFirmwareButton.toolTip = "Upload firmware file to radio"
        readADCButton.toolTip = "Test only"
        readRSSIButton.toolTip = "Test only"
        verboseSlider.toolTip = "Verbose level (0..3)"
        // Visible = False in the original Unit1.dfm
        readADCButton.isHidden = true
        readRSSIButton.isHidden = true

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
        memoScroll.hasHorizontalScroller = true
        memo.isHorizontallyResizable = true
        memo.textContainer?.widthTracksTextView = false
        memo.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        gaugeBar.style = .bar
        gaugeBar.isIndeterminate = false
        gaugeBar.minValue = 0
        gaugeBar.isHidden = true
        gaugeLabel.isHidden = true
        gaugeLabel.font = NSFont.boldSystemFont(ofSize: 11)
        statusTime.font = NSFont.systemFont(ofSize: 12)
        statusBreak.font = NSFont.systemFont(ofSize: 12)

        let row1 = NSStackView(views: [portLabel, portPopup, speedLabel, speedPopup, NSView(), verboseLabel,
                                       verboseSlider, clearButton, readADCButton])
        row1.spacing = 8
        let row2 = NSStackView(views: [readConfigButton, writeConfigButton, readCalibButton, writeCalibButton,
                                       writeFirmwareButton, NSView(), readRSSIButton])
        row2.spacing = 8
        let status = NSStackView(views: [statusTime, statusBreak, gaugeBar, gaugeLabel])
        status.spacing = 12

        for v in [row1, row2, memoScroll, status] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        portPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        speedPopup.widthAnchor.constraint(equalToConstant: 140).isActive = true
        verboseSlider.widthAnchor.constraint(equalToConstant: 90).isActive = true
        statusTime.widthAnchor.constraint(equalToConstant: 260).isActive = true
        statusBreak.widthAnchor.constraint(equalToConstant: 80).isActive = true
        gaugeLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true

        NSLayoutConstraint.activate([
            row1.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            row1.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            row1.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            row2.topAnchor.constraint(equalTo: row1.bottomAnchor, constant: 10),
            row2.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            row2.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            memoScroll.topAnchor.constraint(equalTo: row2.bottomAnchor, constant: 10),
            memoScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            memoScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            memoScroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -4),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -4),
            status.heightAnchor.constraint(equalToConstant: 22),
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

        // WM_INIT_GUI
        DispatchQueue.main.async { [weak self] in self?.wmInitGUI() }
    }

    private func wmInitGUI() {
        loadSettings()
        // common modes: keep ticking while a message box / file dialog is open (like WM_TIMER on Windows)
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.timerTick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        serialPortSelect()
        if ProcessInfo.processInfo.environment["K5PROG_UITEST"] != nil { DispatchQueue.main.async { self.uiTestStep() } }
    }

    // MARK: - UI test mode (env driven, used to exercise the real .app)
    //   K5PROG_UITEST="readconfig,readcalib,writecalib,writeconfig,firmware,quit"
    //   K5PROG_UITEST_OPEN=<path>  K5PROG_UITEST_SAVE=<path>  K5PROG_UITEST_MEMO=<file>

    private lazy var uiTestSteps: [String] = (ProcessInfo.processInfo.environment["K5PROG_UITEST"] ?? "")
        .split(separator: ",").map(String.init)
    private var uiTestIndex = 0

    private func uiTestStep() {
        if busy {
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
        case "quit": window?.performClose(nil); return
        default: break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.uiTestStep() }
    }

    private func loadSettings() {
        let ini = IniFile(path: iniPath)

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
            w.setFrame(nf, display: true)
            if ProcessInfo.processInfo.environment["K5PROG_DEBUG"] != nil {
                FileHandle.standardError.write("loadSettings frame \(nf) -> \(w.frame)\n".data(using: .utf8)!)
            }
        }

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
        let ini = IniFile.fresh(path: iniPath)
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
        ini.save()
    }

    /// m_serial.port_name: the last port that was opened, else what the ini said.
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

    /// SerialPortComboBoxChange()
    private func serialPortComboBoxChange() {
        let connected = prog.connected
        let enabled = !connected && !busy && portPopup.indexOfSelectedItem > 0
        for b in [readConfigButton, writeConfigButton, readCalibButton, writeCalibButton,
                  writeFirmwareButton, readADCButton, readRSSIButton] {
            b.isEnabled = enabled
        }
        portPopup.isEnabled = !connected && !busy
        speedPopup.isEnabled = !connected && !busy
    }

    @objc private func serialPortSelect() {
        if portPopup.indexOfSelectedItem > 0, let t = portPopup.titleOfSelectedItem { savedPortName = t }
        run { $0.serialPortComboBoxSelect() }
    }

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
    @objc private func readADCClick() { run { $0.readADCButtonClick() } }
    @objc private func readRSSIClick() { run { $0.readRSSIButtonClick() } }

    /// Runs a button handler on the worker thread (the original ran them on the GUI
    /// thread pumping ProcessMessages; one at a time, exactly like there).
    private func run(_ handler: @escaping (K5Programmer) -> Void) {
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
        if prog.connected || busy {
            let yes = alertYesNo("Busy readin/writing from/to the radio.\n\nStill close ?")
            if !yes { return false }
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
