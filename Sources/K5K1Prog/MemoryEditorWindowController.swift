// K5K1 Prog - macOS programmer for Quansheng UV-K5 / UV-K5 V3 / UV-K1 radios.
//
// Memory Editor (2.0, not in k5prog-win): edit the radio's channels, copy them between radios,
// import / export CHIRP CSV and .img, power-on text where the firmware shows it.
// Channel layout and value lists: see K5Core/Channels.swift (CHIRP drivers, GPLv2+).
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
import K5Core
import UniformTypeIdentifiers

/// Channels on the pasteboard (copy / paste and drag between editor windows).
struct ChannelClip: Codable {
    var profile: FirmwareProfile?
    var channels: [Channel]
    static let type = NSPasteboard.PasteboardType("io.github.eruban.k5k1prog.channels")
}

final class MemoryEditorWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource,
                                          NSTableViewDelegate, NSTextFieldDelegate, NSMenuItemValidation {
    /// One editor per serial port.
    static var open: [String: MemoryEditorWindowController] = [:]

    private weak var host: MainWindowController?
    let port: String
    private var firmware: String
    private var snapshot: [UInt8]            // the radio's memory as read (8 KB)
    private var mem: ChannelMemory           // the same with the user's edits
    private var confirmed = false            // profile confirmed by the user / a known firmware string
    private var page = 0                     // 0 channels, 1 power-on text
    private var filter = ""

    private var profile: FirmwareProfile { mem.profile }
    private var editable: Bool { confirmed }
    var hasUnwrittenChanges: Bool { dirty }
    private var dirty: Bool { mem.bytes.prefix(K5.configSize) != snapshot.prefix(K5.configSize) }

    // UI
    private let table = NSTableView()
    private lazy var channelsItem = SideItem("Channels") { [weak self] in self?.showPage(0) }
    private lazy var textItem = SideItem("Power-on Text") { [weak self] in self?.showPage(1) }
    private let firmwarePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let radioPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let badge = Pill(compact: false)                       // profile + state, hello below
    private let info = NSTextField(wrappingLabelWithString: "")
    private let footer = NSTextField(labelWithString: "")
    private let search = NSSearchField()
    private let readButton = NSButton(title: "Read from Radio", target: nil, action: nil)
    private let writeButton = NSButton(title: "Write to Radio\u{2026}", target: nil, action: nil)
    private let importButton = NSButton(title: "Import Channels\u{2026}", target: nil, action: nil)
    private let exportButton = NSButton(title: "Export Channels\u{2026}", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let pasteButton = NSButton(title: "Paste", target: nil, action: nil)
    private let powerPopup = NSPopUpButton(frame: .zero, pullsDown: true)
    private let channelPane = NSView()
    private let textPane = NSView()
    private let line1 = NSTextField(string: "")
    private let line2 = NSTextField(string: "")
    private let lcd = NSTextField(labelWithString: "")
    private var visibleRows: [Int] = []
    // decoded once per change instead of once per drawn cell (12 cells a row)
    private var rows: [Channel?] = Array(repeating: nil, count: Channels.count)
    private var changedRows = Set<Int>()

    // quiet check which radio is on the cable (every 2 s while this window is active)
    private enum RadioState: Equatable { case same, changed, noRadio, noPort, flashMode }
    private var radioState = RadioState.same
    private static let probeBlocks = [0x0000, 0x0D80]   // channels 1-8, channel attributes 32-159
    private var probeTimer: Timer?
    private var reading = false
    private var probeQuietUntil = Date.distantPast   // the radio restarts after a write
    private let banner = NSView()
    private let bannerText = NSTextField(wrappingLabelWithString: "")
    private let bannerRead = NSButton(title: "Discard Edits & Read", target: nil, action: nil)
    private let bannerExport = NSButton(title: "Export Channels\u{2026}", target: nil, action: nil)
    private let bannerFix = NSButton(title: "", target: nil, action: nil)
    private var bannerHeight: NSLayoutConstraint!

    private static let toneItems: [ChannelTone] = [.none] + Channels.ctcssTones.map { .ctcss($0) }
        + Channels.dcsCodes.map { .dcs($0, inverted: false) } + Channels.dcsCodes.map { .dcs($0, inverted: true) }

    private enum Col: String, CaseIterable {
        case n, name, freq, duplex, offset, rx, tx, mode, power, step, scr, scan
        var title: String {
            ["#", "Name", "Frequency", "Duplex", "Offset", "RX tone", "TX tone", "Mode", "Power", "Step", "Scrambler", "Scan"][Col.allCases.firstIndex(of: self)!]
        }
        var width: CGFloat { [34, 88, 84, 48, 64, 64, 64, 50, 50, 68, 76, 40][Col.allCases.firstIndex(of: self)!] }
    }

    // MARK: - open

    static func show(host: MainWindowController, port: String, memory: [UInt8], firmware: String) {
        if let w = open[port] {
            w.showWindow(nil)
            return
        }
        let c = MemoryEditorWindowController(host: host, port: port, memory: memory, firmware: firmware)
        open[port] = c
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        c.askProfileIfNeeded()
        c.startProbing()
    }

    private init(host: MainWindowController, port: String, memory: [UInt8], firmware: String) {
        self.host = host
        self.port = port
        self.firmware = firmware
        self.snapshot = memory
        let (p, ok) = MemoryEditorWindowController.profile(for: firmware, defaults: host.defaults)
        self.mem = ChannelMemory(bytes: memory, profile: p)
        self.confirmed = ok
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 600),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.minSize = NSSize(width: 860, height: 420)
        super.init(window: w)
        w.delegate = self
        w.setFrameAutosaveName("MemoryEditor")
        if !w.setFrameUsingName("MemoryEditor") { w.center() }
        buildUI()
        reloadAll()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Profile for a firmware string: stock is recognised from the version number, Karina from
    /// her codename (radio type remembered per firmware string), anything else: the last manual
    /// pick for that string, or nothing (read-only until the user picks).
    static func profile(for firmware: String, defaults: UserDefaults) -> (FirmwareProfile, Bool) {
        let stored = defaults.string(forKey: "Editor.Profile." + firmware).flatMap(FirmwareProfile.init(key:))
        let (fam, radio) = FirmwareProfile.suggest(firmwareString: firmware)
        if let fam = fam, let radio = radio { return (FirmwareProfile(fam, radio), true) }
        if let s = stored, fam == nil || s.firmware == fam { return (s, true) }
        if let fam = fam { return (FirmwareProfile(fam, .k1), false) }   // Karina: ask the radio type
        return (FirmwareProfile(.stock, .v1), false)
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        for b in [readButton, writeButton, importButton, exportButton, deleteButton] { b.bezelStyle = .rounded; b.target = self }
        readButton.action = #selector(readFromRadio)
        writeButton.action = #selector(writeToRadio)
        writeButton.keyEquivalent = ""
        importButton.action = #selector(importChannels(_:))
        exportButton.action = #selector(exportChannels(_:))
        deleteButton.action = #selector(delete(_:))
        writeButton.bezelColor = .controlAccentColor

        firmwarePopup.addItems(withTitles: FirmwareFamily.allCases.map(\.rawValue))
        radioPopup.addItems(withTitles: RadioType.allCases.map(\.rawValue))
        for p in [firmwarePopup, radioPopup] { p.target = self; p.action = #selector(profileChanged(_:)) }
        for p in [firmwarePopup, radioPopup] { p.controlSize = .small; p.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize) }

        // the two selectors on top of each other, the pill to their right
        let fwLabel = NSTextField(labelWithString: "Firmware")
        let rLabel = NSTextField(labelWithString: "Radio")
        for l in [fwLabel, rLabel] { l.textColor = .secondaryLabelColor; l.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize); l.alignment = .right }
        let selectors = NSGridView(views: [[fwLabel, firmwarePopup], [rLabel, radioPopup]])
        selectors.rowSpacing = 4
        selectors.columnSpacing = 6
        selectors.rowAlignment = .firstBaseline
        firmwarePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true
        radioPopup.widthAnchor.constraint(equalToConstant: 150).isActive = true

        badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        badge.setToolTip("Second line: the radio's answer to hello (firmware string)")

        let toolbar = NSStackView(views: [readButton, writeButton, spacer(12), importButton, exportButton, NSView(),
                                          selectors, badge])
        toolbar.spacing = 8
        toolbar.alignment = .centerY
        toolbar.setCustomSpacing(12, after: selectors)

        // sidebar: pages on top, then where the data came from
        let sideSep = NSBox()
        sideSep.boxType = .separator
        let side = NSStackView(views: [channelsItem, textItem, sideSep, info])
        side.orientation = .vertical
        side.alignment = .leading
        side.spacing = 4
        side.setCustomSpacing(12, after: textItem)
        side.setCustomSpacing(12, after: sideSep)
        side.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)
        for v in [channelsItem, textItem, sideSep, info] as [NSView] {
            v.widthAnchor.constraint(equalTo: side.widthAnchor, constant: -16).isActive = true
        }

        // channel table
        for col in Col.allCases {
            let c = NSTableColumn(identifier: .init(col.rawValue))
            c.title = col.title
            c.width = col.width
            c.minWidth = 30
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22
        table.target = self
        table.doubleAction = #selector(tableDoubleClick)
        table.registerForDraggedTypes([ChannelClip.type])
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = true

        powerPopup.addItem(withTitle: "Set Power")
        for p in ChannelPower.allCases { powerPopup.addItem(withTitle: p.label); powerPopup.lastItem?.tag = p.rawValue }
        powerPopup.target = self
        powerPopup.action = #selector(setPower(_:))
        search.placeholderString = "Search name or MHz"
        search.target = self
        search.action = #selector(searchChanged)
        let copyButton = NSButton(title: "Copy", target: self, action: #selector(copy(_:)))
        pasteButton.target = self
        pasteButton.action = #selector(paste(_:))
        let actions = NSStackView(views: [copyButton, pasteButton, deleteButton, powerPopup, NSView(), search])
        actions.spacing = 6
        search.widthAnchor.constraint(equalToConstant: 190).isActive = true
        footer.textColor = .secondaryLabelColor
        footer.font = NSFont.systemFont(ofSize: 11)

        for v in [actions, tableScroll, footer] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; channelPane.addSubview(v) }
        NSLayoutConstraint.activate([
            actions.topAnchor.constraint(equalTo: channelPane.topAnchor),
            actions.leadingAnchor.constraint(equalTo: channelPane.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: channelPane.trailingAnchor),
            tableScroll.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: 8),
            tableScroll.leadingAnchor.constraint(equalTo: channelPane.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: channelPane.trailingAnchor),
            tableScroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -6),
            footer.leadingAnchor.constraint(equalTo: channelPane.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: channelPane.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: channelPane.bottomAnchor),
        ])

        // power-on text page
        for f in [line1, line2] {
            f.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            f.delegate = self
            f.placeholderString = "up to 12 characters"
            f.widthAnchor.constraint(equalToConstant: 200).isActive = true
        }
        lcd.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .bold)
        lcd.alignment = .center
        lcd.textColor = NSColor(srgbRed: 0.11, green: 0.14, blue: 0.06, alpha: 1)
        lcd.drawsBackground = true
        lcd.backgroundColor = NSColor(srgbRed: 0.62, green: 0.69, blue: 0.48, alpha: 1)
        lcd.maximumNumberOfLines = 2
        let note = NSTextField(wrappingLabelWithString: "Up to 12 characters per line (Latin letters, digits, symbols). The radio shows them at power-on when its POnMsg menu is set to MESSAGE (or ALL). They are written together with the channels.")
        note.textColor = .secondaryLabelColor
        let grid = NSGridView(views: [[NSTextField(labelWithString: "Line 1"), line1], [NSTextField(labelWithString: "Line 2"), line2]])
        grid.rowSpacing = 8
        let textStack = NSStackView(views: [grid, lcd, note])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 14
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textPane.addSubview(textStack)
        NSLayoutConstraint.activate([
            textStack.topAnchor.constraint(equalTo: textPane.topAnchor, constant: 12),
            textStack.leadingAnchor.constraint(equalTo: textPane.leadingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: textPane.trailingAnchor, constant: -12),
            lcd.widthAnchor.constraint(equalToConstant: 256),
            lcd.heightAnchor.constraint(equalToConstant: 96),
            note.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
        ])

        banner.wantsLayer = true
        banner.layer?.cornerRadius = 6
        bannerText.font = NSFont.systemFont(ofSize: 12)
        bannerRead.target = self
        bannerRead.action = #selector(bannerReadClick)
        bannerExport.target = self
        bannerExport.action = #selector(exportChannels(_:))
        bannerFix.target = self
        bannerFix.action = #selector(bannerFixClick)
        for b in [bannerRead, bannerExport, bannerFix] { b.controlSize = .small; b.bezelStyle = .rounded }
        let bannerStack = NSStackView(views: [bannerText, bannerRead, bannerExport, bannerFix])
        bannerStack.spacing = 8
        bannerStack.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(bannerStack)
        bannerText.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bannerText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            bannerStack.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 10),
            bannerStack.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -10),
            bannerStack.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
        ])
        banner.isHidden = true
        for v in [toolbar, banner, side, channelPane, textPane] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        bannerHeight = banner.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            banner.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            banner.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bannerHeight,
        ])
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            side.topAnchor.constraint(equalTo: banner.bottomAnchor, constant: 4),
            side.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 4),
            side.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -4),
            side.widthAnchor.constraint(equalToConstant: 170),
            channelPane.topAnchor.constraint(equalTo: banner.bottomAnchor, constant: 4),
            channelPane.leadingAnchor.constraint(equalTo: side.trailingAnchor, constant: 8),
            channelPane.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            channelPane.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            textPane.topAnchor.constraint(equalTo: channelPane.topAnchor),
            textPane.leadingAnchor.constraint(equalTo: channelPane.leadingAnchor),
            textPane.trailingAnchor.constraint(equalTo: channelPane.trailingAnchor),
            textPane.bottomAnchor.constraint(equalTo: channelPane.bottomAnchor),
        ])
    }

    private func spacer(_ w: CGFloat) -> NSView {
        let v = NSView()
        v.widthAnchor.constraint(equalToConstant: w).isActive = true
        return v
    }

    private func reloadAll() {
        firmwarePopup.selectItem(withTitle: profile.firmware.rawValue)
        radioPopup.selectItem(withTitle: profile.radio.rawValue)
        // the pill follows the radio on the cable too (same quiet check as the banner)
        let who = "\(profile.radio.short) · \(profile.firmware.rawValue)"
        let hello = "hello: \(firmware.isEmpty ? "—" : firmware)"
        switch radioState {
        case .noRadio: badge.set(who + " · no radio", "turn it on, check the cable", tint: .systemGray)
        case .noPort: badge.set(who + " · cable unplugged", "no serial port", tint: .systemGray)
        case .flashMode: badge.set(who + " · firmware update mode", "restart without PTT", tint: .systemGray)
        case .changed: badge.set("another radio connected", "read before: " + (firmware.isEmpty ? "—" : firmware), tint: .systemOrange)
        case .same:
            if mismatch != nil {
                badge.set(who + " · mismatch", hello, tint: .systemRed)
            } else {
                badge.set(confirmed ? who + " · editable" : "read-only · choose firmware and radio", hello,
                          tint: confirmed ? .systemGreen : .systemOrange)
            }
        }
        if !profile.hasPowerOnText { page = 0 }
        textItem.isHidden = !profile.hasPowerOnText
        channelsItem.selected = page == 0
        textItem.selected = page == 1
        channelPane.isHidden = page != 0
        textPane.isHidden = page != 1
        line1.stringValue = mem.powerOnText(0)
        line2.stringValue = mem.powerOnText(1)
        updateLCD()
        for f in [line1, line2] { f.isEditable = editable }
        // radio operations need the radio; editing the channels already read does not
        let radioThere = radioState == .same || radioState == .changed
        writeButton.isEnabled = editable && radioState == .same
        readButton.isEnabled = radioThere
        importButton.isEnabled = editable
        pasteButton.isEnabled = editable
        deleteButton.isEnabled = editable
        powerPopup.isEnabled = editable
        info.attributedStringValue = sideInfo()
        updateBanner()
        reloadTable()
    }

    private func refreshCache() {
        rows = mem.channels
        let old = ChannelMemory(bytes: snapshot, profile: profile)
        changedRows = Set((0..<Channels.count).filter { old.channel($0) != rows[$0] })
    }

    private func reloadTable() {
        refreshCache()
        let f = filter.lowercased()
        visibleRows = (0..<Channels.count).filter { i in
            guard !f.isEmpty else { return true }
            guard let c = rows[i] else { return false }
            return c.name.lowercased().contains(f) || fmtMHz(c.freq).contains(f)
        }
        table.reloadData()
        updateTitle()
    }

    /// After an edit of `channels`: redraw only their rows (all rows while a search is on,
    /// the edit may show or hide rows).
    private func refreshRows(_ channels: Set<Int>) {
        guard filter.isEmpty else { reloadTable(); return }
        refreshCache()
        table.reloadData(forRowIndexes: IndexSet(channels), columnIndexes: IndexSet(0..<table.numberOfColumns))
        updateTitle()
    }

    private func updateTitle() {
        let used = rows.filter { $0 != nil }.count
        window?.title = "Memory Editor — \(profile.radio.rawValue) on \(port)"
        window?.isDocumentEdited = dirty
        let changed = changedRows.count
        footer.stringValue = "\(used) of \(Channels.count) channels · \(changed) changed"
            + (table.selectedRowIndexes.count > 1 ? " · \(table.selectedRowIndexes.count) selected" : "")
            + "   —   double-click to edit, drag rows to another window to copy"
        channelsItem.setCount("\(used)/\(Channels.count)")
    }

    private func updateLCD() {
        lcd.stringValue = mem.powerOnText(0) + "\n" + mem.powerOnText(1)
    }

    private func fmtMHz(_ hz: Int) -> String { String(format: "%.5f", Double(hz) / 1e6) }

    private func changedChannels() -> [Int] {
        let old = ChannelMemory(bytes: snapshot, profile: profile)
        return (0..<Channels.count).filter { old.channel($0) != mem.channel($0) }
    }

    // MARK: - profile

    private func askProfileIfNeeded() {
        guard !confirmed, let w = window, !Self.uiTesting else { return }   // UI tests pick it with editor-profile=
        let (fam, _) = FirmwareProfile.suggest(firmwareString: firmware)
        guard fam == .karina else { return }   // unknown firmware: the banner says what to do
        let a = NSAlert()
        a.messageText = "Which radio is this?"
        a.informativeText = "The radio reports Karina's firmware ('\(firmware)'). It is the same on the UV-K5 V1 and the UV-K1 / UV-K5 V3, and a few channel values differ between them. K5K1 Prog remembers the answer for this firmware."
        a.addButton(withTitle: RadioType.k1.rawValue)
        a.addButton(withTitle: RadioType.v1.rawValue)
        a.addButton(withTitle: "Not Now")
        a.beginSheetModal(for: w) { r in
            guard r != .alertThirdButtonReturn else { return }
            self.setProfile(FirmwareProfile(.karina, r == .alertFirstButtonReturn ? .k1 : .v1), confirm: true)
        }
    }

    private func setProfile(_ p: FirmwareProfile, confirm: Bool) {
        mem = ChannelMemory(bytes: mem.bytes, profile: p)
        confirmed = confirm
        if confirm { host?.defaults.set(p.key, forKey: "Editor.Profile." + firmware) }
        undoManager?.removeAllActions()
        reloadAll()
    }

    @objc private func profileChanged(_ sender: NSPopUpButton) {
        let fam = FirmwareFamily.allCases[firmwarePopup.indexOfSelectedItem]
        let radio = RadioType.allCases[radioPopup.indexOfSelectedItem]
        let p = FirmwareProfile(fam, radio)
        guard let w = window, p != profile || !confirmed else { return }
        if dirty {
            NSSound.beep()
            reloadAll()
            alert("Write or discard your changes first", "The profile decides how the radio's bytes are read. It can't change while there are unwritten edits.")
            return
        }
        let (sFam, sRadio) = FirmwareProfile.suggest(firmwareString: firmware)
        let looksOther = (sFam != nil && sFam != fam) || (sRadio != nil && sRadio != radio)
        let a = NSAlert()
        a.messageText = "Use \(p.label)?"
        a.informativeText = looksOther
            ? "The radio reports '\(firmware)', which looks like \(sFam?.rawValue ?? "")\(sRadio.map { " · " + $0.rawValue } ?? ""). With the wrong profile some channel values (mode, step, scrambler) are read and written wrongly. Continue at your own risk."
            : "The radio reports '\(firmware)'. K5K1 Prog remembers this choice for that firmware."
        a.addButton(withTitle: "Use \(p.label)")
        a.addButton(withTitle: "Cancel")
        if looksOther { a.alertStyle = .critical }
        a.beginSheetModal(for: w) { r in
            if r == .alertFirstButtonReturn { self.setProfile(p, confirm: true) } else { self.reloadAll() }
        }
    }

    // MARK: - sidebar + table data

    func numberOfRows(in tableView: NSTableView) -> Int { visibleRows.count }

    private func showPage(_ p: Int) {
        page = p
        channelsItem.selected = p == 0
        textItem.selected = p == 1
        channelPane.isHidden = p != 0
        textPane.isHidden = p != 1
    }

    private func sideInfo() -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para]
        var bold = base
        bold[.font] = NSFont.boldSystemFont(ofSize: 12)
        bold[.foregroundColor] = NSColor.labelColor
        var mono = base
        mono[.font] = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        let s = NSMutableAttributedString(string: "Read from\n", attributes: base)
        s.append(NSAttributedString(string: port + "\n", attributes: bold))
        s.append(NSAttributedString(string: "hello: '\(firmware)'\n\n", attributes: mono))
        s.append(NSAttributedString(string: confirmed ? "Channels only. Settings and calibration are never written by the editor."
                                                      : "Choose the firmware and the radio above to edit. Until then: view, copy and export only.",
                                    attributes: base))
        return s
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue, let col = Col(rawValue: id) else { return nil }
        let i = visibleRows[row]
        let c = rows[i]
        let changed = changedRows.contains(i)
        let label = NSTextField(labelWithString: text(col, c, i))
        label.lineBreakMode = .byTruncatingTail
        if [.n, .freq, .offset, .step].contains(col) { label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular) }
        if c == nil && col != .n { label.textColor = .tertiaryLabelColor }
        if col == .n && changed { label.textColor = .systemOrange; label.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold) }
        if c != nil, valueUnknown(col, c!) { label.textColor = .systemRed }
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateTitle()
    }

    private func valueUnknown(_ col: Col, _ c: Channel) -> Bool {
        (col == .mode && c.mode == nil) || (col == .step && c.step == nil) || (col == .scr && c.scrambler == nil)
    }

    private func text(_ col: Col, _ c: Channel?, _ i: Int) -> String {
        if col == .n { return String(i + 1) }
        guard let c = c else { return col == .name ? "—" : "" }
        switch col {
        case .n: return ""
        case .name: return c.name
        case .freq: return fmtMHz(c.freq)
        case .duplex: return c.duplex == .none ? "" : c.duplex.rawValue
        case .offset: return c.duplex == .plus || c.duplex == .minus ? String(format: "%.4f", Double(c.offset) / 1e6) : ""
        case .rx: return c.rxTone.label
        case .tx: return c.txTone.label
        case .mode: return c.mode?.rawValue ?? "?"
        case .power: return c.power.label
        case .step: return c.step.map { stepLabel($0) } ?? "?"
        case .scr: return c.scrambler ?? "?"
        case .scan: return [c.scanList1 ? "1" : nil, c.scanList2 ? "2" : nil].compactMap { $0 }.joined(separator: "+")
        }
    }

    private func stepLabel(_ s: Double) -> String { (s == s.rounded() ? String(Int(s)) : String(format: "%g", s)) + " kHz" }

    // MARK: - editing

    @objc private func tableDoubleClick() {
        let row = table.clickedRow, colIdx = table.clickedColumn
        guard row >= 0, colIdx >= 0, let col = Col(rawValue: table.tableColumns[colIdx].identifier.rawValue) else { return }
        guard editable else { NSSound.beep(); return }
        let i = visibleRows[row]
        let c = mem.channel(i)
        if c == nil && col != .freq && col != .name { editText(.freq, i, row: row, colIdx: table.column(withIdentifier: .init(Col.freq.rawValue))); return }
        switch col {
        case .n: return
        case .name, .freq, .offset: editText(col, i, row: row, colIdx: colIdx)
        default: editPopup(col, i, row: row, colIdx: colIdx)
        }
    }

    private func editText(_ col: Col, _ i: Int, row: Int, colIdx: Int) {
        let c = mem.channel(i)
        if c == nil && col == .name { editText(.freq, i, row: row, colIdx: table.column(withIdentifier: .init(Col.freq.rawValue))); return }
        // edit in the cell's own label: same font and text position, nothing drawn on top of it
        table.scrollRowToVisible(row)
        guard let field = table.view(atColumn: colIdx, row: row, makeIfNecessary: true) as? NSTextField else { return }
        field.stringValue = c.map { col == .name ? $0.name : (col == .freq ? fmtMHz($0.freq) : String(format: "%.4f", Double($0.offset) / 1e6)) } ?? ""
        field.textColor = .labelColor   // the cell's own font stays: the text does not move
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.isEditable = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.identifier = NSUserInterfaceItemIdentifier("edit.\(col.rawValue).\(i)")
        field.delegate = self
        field.target = self
        field.action = #selector(textCommitted(_:))
        window?.makeFirstResponder(field)
        hideCaretWhileSelected(field)
    }

    // The text is selected when a cell edit starts; macOS 26 still draws the caret at the start of
    // the selection (a bar left of the text). Hide it while something is selected.
    private var caretObserver: NSObjectProtocol?
    private var caretColor: NSColor?

    private func hideCaretWhileSelected(_ field: NSTextField) {
        guard let tv = field.currentEditor() as? NSTextView else { return }
        let normal = tv.insertionPointColor
        caretColor = normal
        let update = { [weak tv] in
            guard let tv else { return }
            tv.insertionPointColor = tv.selectedRange().length > 0 ? .clear : normal
        }
        update()
        caretObserver = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification,
                                                               object: tv, queue: .main) { _ in update() }
    }

    /// The field editor is shared by the window's fields (search, power-on text): give its caret back.
    private func restoreCaret(_ field: NSTextField) {
        if let o = caretObserver { NotificationCenter.default.removeObserver(o) }
        caretObserver = nil
        if let c = caretColor, let tv = field.currentEditor() as? NSTextView ?? window?.fieldEditor(false, for: field) as? NSTextView {
            tv.insertionPointColor = c
        }
        caretColor = nil
    }

    /// Ends an in-cell edit and redraws the cell from the memory.
    private func endCellEdit(_ field: NSTextField) {
        field.identifier = nil
        restoreCaret(field)
        field.isEditable = false
        field.drawsBackground = false
        window?.makeFirstResponder(table)
        let row = table.row(for: field), col = table.column(for: field)
        if row >= 0, col >= 0 { table.reloadData(forRowIndexes: [row], columnIndexes: [col]) }
    }

    @objc private func textCommitted(_ field: NSTextField) {
        guard let id = field.identifier?.rawValue, id.hasPrefix("edit.") else { return }
        let parts = id.split(separator: ".")
        let col = Col(rawValue: String(parts[1]))!, i = Int(parts[2])!
        let v = field.stringValue.trimmingCharacters(in: .whitespaces)
        endCellEdit(field)
        var c = mem.channel(i)
        switch col {
        case .name:
            guard c != nil else { return }
            c!.name = ChannelMemory.sanitizedName(v.uppercased())
        case .freq:
            guard let hz = parseMHz(v), profile.isValidFrequency(hz) else {
                if !v.isEmpty { alert("\(v) MHz can't be used", "The frequency must be in a range \(profile.label) receives.") }
                return
            }
            if c == nil {
                var n = Channel()
                n.freq = hz
                n.step = profile.steps.contains(12.5) ? 12.5 : profile.steps[0]
                c = n
            } else { c!.freq = hz }
        case .offset:
            guard c != nil else { return }
            guard let hz = parseMHz(v) else {
                if !v.isEmpty { alert("\(v) MHz can't be used as the offset", "Type the offset in MHz, for example 0.6 or 5; the direction is set in Duplex.") }
                return
            }
            c!.offset = hz
            if hz == 0 { c!.duplex = .none } else if c!.duplex == .none || c!.duplex == .off { c!.duplex = .plus }
        default: return
        }
        if let ch = c, let tx = ch.txFreq, tx != mem.channel(i)?.txFreq, !profile.isValidFrequency(tx) {
            alert(String(format: "Transmit frequency %.5f MHz can't be used", Double(tx) / 1e6), "Check the duplex and the offset.")
            return
        }
        apply([i: c], actionName: "Edit \(col.title)")
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)), let f = control as? NSTextField, f.identifier?.rawValue.hasPrefix("edit.") == true {
            endCellEdit(f)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        if f.identifier?.rawValue.hasPrefix("edit.") == true { textCommitted(f); return }
        if f === line1 || f === line2 { powerOnTextChanged() }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField, f === line1 || f === line2 else { return }
        let clean = String(f.stringValue.unicodeScalars.filter { $0.value >= 0x20 && $0.value < 0x7F }.map(Character.init).prefix(Channels.powerOnTextLength))
        if clean != f.stringValue { f.stringValue = clean; NSSound.beep() }
        lcd.stringValue = line1.stringValue + "\n" + line2.stringValue
    }

    private func powerOnTextChanged() {
        guard editable else { return }
        let (a, b) = (line1.stringValue, line2.stringValue)
        guard a != mem.powerOnText(0) || b != mem.powerOnText(1) else { return }
        let before = mem.bytes
        mem.setPowerOnText(0, a)
        mem.setPowerOnText(1, b)
        registerUndo(before, name: "Edit Power-on Text")
        updateTitle()
    }

    /// "433.125" / "433,125" in MHz to Hz; nil for anything that is not a plain non-negative number.
    private func parseMHz(_ s: String) -> Int? {
        ChannelFiles.parseFreq(s.replacingOccurrences(of: ",", with: "."))
    }

    private func editPopup(_ col: Col, _ i: Int, row: Int, colIdx: Int) {
        guard let c = mem.channel(i) else { return }
        let menu = NSMenu()
        func item(_ title: String, _ apply: @escaping (inout Channel) -> Void, on: Bool) {
            let it = NSMenuItem(title: title, action: #selector(popupPicked(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = PopupChoice(index: i, apply: apply)
            it.state = on ? .on : .off
            menu.addItem(it)
        }
        switch col {
        case .duplex:
            for d in Duplex.allCases { item(d == .none ? "none" : d.rawValue, { $0.duplex = d; if d == .none { $0.offset = 0 } }, on: c.duplex == d) }
        case .rx, .tx:
            let cur = col == .rx ? c.rxTone : c.txTone
            let ctcss = NSMenu(), dcsN = NSMenu(), dcsI = NSMenu()
            item("none", { if col == .rx { $0.rxTone = .none } else { $0.txTone = .none } }, on: cur == .none)
            for t in Self.toneItems where t != .none {
                let it = NSMenuItem(title: t.label, action: #selector(popupPicked(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = PopupChoice(index: i) { if col == .rx { $0.rxTone = t } else { $0.txTone = t } }
                it.state = cur == t ? .on : .off
                if case .ctcss = t { ctcss.addItem(it) } else if case .dcs(_, let inv) = t { (inv ? dcsI : dcsN).addItem(it) }
            }
            for (title, sub) in [("CTCSS", ctcss), ("DCS normal", dcsN), ("DCS inverted", dcsI)] {
                let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                it.submenu = sub
                menu.addItem(it)
            }
        case .mode:
            for m in profile.modes { item(m.rawValue, { $0.mode = m }, on: c.mode == m) }
        case .power:
            for p in ChannelPower.allCases { item(p.label, { $0.power = p }, on: c.power == p) }
        case .step:
            for s in profile.steps { item(stepLabel(s), { $0.step = s }, on: c.step == s) }
        case .scr:
            for s in profile.scramblers { item(s, { $0.scrambler = s }, on: c.scrambler == s) }
        case .scan:
            for (t, a, b) in [("none", false, false), ("1", true, false), ("2", false, true), ("1+2", true, true)] {
                item(t, { $0.scanList1 = a; $0.scanList2 = b }, on: c.scanList1 == a && c.scanList2 == b)
            }
        default: return
        }
        let rect = table.frameOfCell(atColumn: colIdx, row: row)
        menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.maxY), in: table)
    }

    private final class PopupChoice {
        let index: Int
        let apply: (inout Channel) -> Void
        init(index: Int, apply: @escaping (inout Channel) -> Void) { self.index = index; self.apply = apply }
    }

    @objc private func popupPicked(_ item: NSMenuItem) {
        guard let ch = item.representedObject as? PopupChoice, var c = mem.channel(ch.index) else { return }
        ch.apply(&c)
        // apply to every selected channel when the clicked one is part of a multi-selection
        let rows = table.selectedRowIndexes.map { visibleRows[$0] }
        var changes: [Int: Channel] = [ch.index: c]
        if rows.count > 1 && rows.contains(ch.index) {
            for i in rows where i != ch.index { if var o = mem.channel(i) { ch.apply(&o); changes[i] = o } }
        }
        // every channel whose transmit frequency changes must still transmit where the radio allows
        let bad = changes.filter { i, x in
            guard let tx = x.txFreq, tx != mem.channel(i)?.txFreq else { return false }
            return !profile.isValidFrequency(tx)
        }.keys.sorted()
        if let first = bad.first, let tx = changes[first]?.txFreq {
            let which = bad.count == 1 ? "channel \(first + 1)" : "\(bad.count) channels (first: \(first + 1))"
            alert(String(format: "Transmit frequency %.5f MHz can't be used", Double(tx) / 1e6),
                  "Nothing changed: \(which) would transmit outside the radio's ranges. Check the duplex and the offset.")
            return
        }
        apply(changes.mapValues { Optional($0) }, actionName: "Edit")
    }

    @objc private func setPower(_ sender: NSPopUpButton) {
        guard editable, let p = ChannelPower(rawValue: sender.selectedItem?.tag ?? -1) else { return }
        var changes: [Int: Channel?] = [:]
        for r in table.selectedRowIndexes { let i = visibleRows[r]; if var c = mem.channel(i) { c.power = p; changes[i] = c } }
        if !changes.isEmpty { apply(changes, actionName: "Set Power") }
    }

    @objc private func searchChanged() {
        filter = search.stringValue.trimmingCharacters(in: .whitespaces)
        reloadTable()
    }

    // MARK: - model changes + undo

    private func apply(_ changes: [Int: Channel?], actionName: String) {
        guard editable else { return }
        // only what really changes (Enter without an edit, the same value picked again: no undo step)
        let real = changes.filter { mem.channel($0.key) != $0.value }
        guard !real.isEmpty else { return }
        let before = mem.bytes
        for (i, c) in real { mem.setChannel(i, c) }
        registerUndo(before, name: actionName)
        refreshRows(Set(real.keys))
    }

    private func registerUndo(_ before: [UInt8], name: String) {
        undoManager?.registerUndo(withTarget: self) { t in
            let redo = t.mem.bytes
            t.mem.bytes = before
            t.registerUndo(redo, name: name)
            t.reloadAll()
        }
        undoManager?.setActionName(name)
    }

    @objc func delete(_ sender: Any?) {
        guard editable else { return }
        var changes: [Int: Channel?] = [:]
        for r in table.selectedRowIndexes { let i = visibleRows[r]; if mem.channel(i) != nil { changes[i] = .some(nil) } }
        apply(changes, actionName: "Delete")
    }

    // MARK: - copy / paste / drag

    private func selectedChannels() -> [Channel] {
        table.selectedRowIndexes.compactMap { mem.channel(visibleRows[$0]) }
    }

    @objc func copy(_ sender: Any?) {
        let chans = selectedChannels()
        guard !chans.isEmpty else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        let clip = ChannelClip(profile: confirmed ? profile : nil, channels: chans)
        if let d = try? JSONEncoder().encode(clip) { pb.setData(d, forType: ChannelClip.type) }
        pb.setString(ChannelFiles.csv(table.selectedRowIndexes.compactMap { r in mem.channel(visibleRows[r]).map { (visibleRows[r], $0) } }), forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        guard let data = NSPasteboard.general.data(forType: ChannelClip.type),
              let clip = try? JSONDecoder().decode(ChannelClip.self, from: data) else { NSSound.beep(); return }
        insert(clip.channels, from: clip.profile, at: nil, what: "pasted")
    }

    /// Converts `chans` (from `source`) for this radio and stores them from `at` (the selected
    /// row, or the first free row) on. With `slots` (import) the source's row layout is kept:
    /// gaps stay gaps, and without a selection the channels keep their own row numbers.
    /// Asks before replacing channels, reports adjusted values.
    private func insert(_ chans: [Channel], slots: [Int]? = nil, from source: FirmwareProfile?, at: Int?, what: String,
                        notes fileNotes: [String] = []) {
        guard let w = window else { return }
        guard editable else { alert("This radio is read-only", "Choose the firmware and the radio first."); return }
        let selected = at ?? table.selectedRowIndexes.first.map { visibleRows[$0] }
        let first = slots?.min() ?? 0
        let start = selected ?? (slots != nil ? first : (0..<Channels.count).first { mem.channel($0) == nil } ?? 0)
        let rel = slots.map { $0.map { $0 - first } } ?? Array(0..<chans.count)
        var notes: [String] = fileNotes
        var placed: [(Int, Channel)] = []
        var dropped = 0
        for (k, c) in chans.enumerated() {
            guard let r = ChannelConverter.convert(c, from: source, to: profile, notes: &notes) else { continue }
            let row = start + rel[k]
            if row < Channels.count { placed.append((row, r)) } else { dropped += 1 }
        }
        if dropped > 0 { notes.append("\(dropped) channel(s) didn't fit after row \(Channels.count)") }
        guard !placed.isEmpty else { alert("Nothing \(what)", notes.joined(separator: "\n")); return }
        let rows = placed.map(\.0)
        let replaced = rows.filter { mem.channel($0) != nil }.count
        let range = "rows \(rows.min()! + 1)–\(rows.max()! + 1)"
        let doIt = {
            var changes: [Int: Channel?] = [:]
            for (row, c) in placed { changes[row] = c }
            self.apply(changes, actionName: what == "pasted" ? "Paste" : "Import")
            self.table.selectRowIndexes(IndexSet(rows.compactMap { self.visibleRows.firstIndex(of: $0) }), byExtendingSelection: false)
            self.table.scrollRowToVisible(self.visibleRows.firstIndex(of: rows.min()!) ?? 0)
            let head = "\(placed.count) channel(s) \(what) into \(range)"
                + (source.map { $0 != self.profile ? " (from \($0.label), converted value by value)" : "" } ?? "")
            if notes.isEmpty {
                self.footer.stringValue = head + ". Nothing had to be adjusted."
            } else {
                self.alert(head + ".", "\(notes.count) value(s) adjusted:\n" + notes.prefix(25).joined(separator: "\n") + (notes.count > 25 ? "\n…" : ""))
            }
        }
        if replaced == 0 || Self.uiTesting { doIt(); return }
        let a = NSAlert()
        a.messageText = "Replace \(replaced) channel(s)?"
        a.informativeText = "\(placed.count) channel(s) go to \(range); \(replaced) of these rows are not empty. (Undo with ⌘Z.)"
        a.addButton(withTitle: "Replace")
        a.addButton(withTitle: "Cancel")
        a.beginSheetModal(for: w) { if $0 == .alertFirstButtonReturn { doIt() } }
    }

    private var draggedRows: [Int] = []

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard tableView === table, let c = mem.channel(visibleRows[row]) else { return nil }
        let item = NSPasteboardItem()
        guard let d = try? JSONEncoder().encode(ChannelClip(profile: confirmed ? profile : nil, channels: [c])) else { return nil }
        item.setData(d, forType: ChannelClip.type)
        return item
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        draggedRows = rowIndexes.map { visibleRows[$0] }
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        guard tableView === table, editable, filter.isEmpty else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return (info.draggingSource as? NSTableView) === table ? .move : .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let items = info.draggingPasteboard.pasteboardItems ?? []
        let clips = items.compactMap { $0.data(forType: ChannelClip.type).flatMap { try? JSONDecoder().decode(ChannelClip.self, from: $0) } }
        guard !clips.isEmpty else { return false }
        let chans = clips.flatMap(\.channels)
        let dest = min(row, Channels.count - 1)
        if (info.draggingSource as? NSTableView) === table {
            // move inside this radio: free the old rows, then place them from the drop row
            let before = mem.bytes
            let count = draggedRows.filter { mem.channel($0) != nil }.count
            switch mem.moveChannels(draggedRows, to: dest) {
            case .moved:
                registerUndo(before, name: "Move")
                reloadTable()
                return true
            case .targetsNotEmpty:
                alert("Rows \(dest + 1)–\(dest + count) are not empty", "Move the channels to free rows, or copy and paste to replace channels.")
            case .noRoom:
                alert("Not enough rows after row \(dest + 1)", "\(count) channel(s) need rows \(dest + 1)–\(dest + count); the radio has \(Channels.count). Nothing was moved.")
            }
            return false
        }
        insert(chans, from: clips.first?.profile, at: dest, what: "copied")
        return true
    }

    // MARK: - radio

    @objc private func readFromRadio() {
        guard readButton.isEnabled else { NSSound.beep(); return }
        if !dirty { readRadio(anotherRadio: false); return }
        confirm("Discard your changes?", "The channels are read from the radio again; your unwritten edits are lost.", "Discard and Read") {
            self.readRadio(anotherRadio: false)
        }
    }

    @objc private func bannerReadClick() {
        confirm("Discard your changes?", "Your unwritten edits are lost; the radio on the cable is read.", "Discard and Read") {
            self.readRadio(anotherRadio: true)
        }
    }

    /// `anotherRadio`: a different radio was found on the cable. Karina's firmware string is the
    /// same on the UV-K5 V1 and the UV-K1, so the radio type is asked again instead of reused.
    private func readRadio(anotherRadio: Bool) {
        reading = true
        let started = host?.runEditorRead(port: port) { r in
            self.reading = false
            guard let r = r else { self.alert("Read failed", "See the log in the main window."); return }
            self.snapshot = r.memory
            self.firmware = r.firmware
            var (p, ok) = Self.profile(for: r.firmware, defaults: self.host?.defaults ?? .standard)
            if anotherRadio && FirmwareProfile.suggest(firmwareString: r.firmware).1 == nil { ok = false }
            self.mem = ChannelMemory(bytes: r.memory, profile: p)
            self.confirmed = ok
            self.radioState = .same
            self.undoManager?.removeAllActions()
            self.reloadAll()
            self.updateBanner()
            if anotherRadio { self.footer.stringValue = "Another radio connected: read again." }
            self.askProfileIfNeeded()
        } ?? false
        if !started { reading = false }
    }

    // MARK: - which radio is on the cable

    func startProbing() {
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.probe() }
        RunLoop.main.add(t, forMode: .default)   // not while a menu is open or the window is dragged
        probeTimer = t
    }

    /// A channel cell or a power-on text line is being typed in: the radio check must not
    /// redraw the table or the fields now (it would throw the typed text away).
    private var isTyping: Bool {
        guard let tv = window?.firstResponder as? NSTextView, let f = tv.delegate as? NSTextField else { return false }
        return f.identifier?.rawValue.hasPrefix("edit.") == true || f === line1 || f === line2
    }

    private func probe() {
        guard let w = window, w.isKeyWindow, NSApp.isActive, w.attachedSheet == nil, !reading, !isTyping,
              host?.isIdle == true else { return }
        _ = host?.runEditorProbe(port: port, blocks: Self.probeBlocks) { [weak self] r in self?.probed(r) }
    }

    private func probed(_ r: K5Programmer.ProbeResult) {
        guard !reading, window?.attachedSheet == nil, !isTyping else { return }   // checked again in 2 s
        if (r == .noRadio || r == .noPort) && Date() < probeQuietUntil { return }
        let state: RadioState
        switch r {
        case .noPort: state = .noPort
        case .noRadio: state = .noRadio
        case .flashMode: state = .flashMode
        case .radio(let fw, let blocks):
            let same = fw == firmware && blocks.allSatisfy { b, d in Array(snapshot[b..<(b + d.count)]) == d }
            state = same ? .same : .changed
        }
        if state == .changed && !dirty {
            readRadio(anotherRadio: true)   // nothing to lose: show the radio that is there now
            return
        }
        if state != radioState {
            radioState = state
            updateBanner()
            reloadAll()
        }
    }

    /// What the radio's firmware string clearly says, when it contradicts the selectors
    /// (stock version numbers give firmware and radio, Karina's codename only the firmware).
    private var mismatch: FirmwareProfile? {
        let (f, r) = FirmwareProfile.suggest(firmwareString: firmware)
        guard confirmed, (f != nil && f != profile.firmware) || (r != nil && r != profile.radio) else { return nil }
        return FirmwareProfile(f ?? profile.firmware, r ?? profile.radio)
    }

    @objc private func bannerFixClick() {
        guard let p = mismatch else { return }
        if dirty {
            alert("Write or discard your changes first", "The profile decides how the radio's bytes are read. It can't change while there are unwritten edits.")
            return
        }
        setProfile(p, confirm: true)
    }

    private func updateBanner() {
        var text = "", color = NSColor.systemOrange, actions = false
        bannerFix.isHidden = true
        switch radioState {
        case .same:
            if let m = mismatch {
                text = "The radio reports '\(firmware)', which looks like \(m.label), not \(profile.label). Channels may be read and written wrongly: at your own risk."
                color = .systemRed
                bannerFix.title = "Use \(m.label)"
                bannerFix.isHidden = false
            }
        case .changed:
            text = "Another radio connected. Your edits are for the previous one and won't be written here."
            actions = true
        case .noRadio:
            text = "No answer from the radio. Turn it on and check the cable."
            color = .systemGray
        case .noPort:
            text = "Cable unplugged."
            color = .systemGray
        case .flashMode:
            text = "Radio in firmware update mode. Turn it off and on again without PTT."
            color = .systemGray
        }
        banner.isHidden = text.isEmpty
        bannerHeight.constant = text.isEmpty ? 0 : 34
        banner.layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
        bannerText.stringValue = text
        bannerText.maximumNumberOfLines = 2
        bannerHeight.constant = text.isEmpty ? 0 : (text.count > 110 ? 44 : 34)
        bannerRead.isHidden = !actions
        bannerExport.isHidden = !actions
    }

    @objc private func writeToRadio() {
        guard let w = window, editable else { return }
        window?.makeFirstResponder(table)   // commit a field being edited
        powerOnTextChanged()
        let changed = changedChannels()
        let textChanged = mem.bytes[Channels.powerOnText1..<(Channels.powerOnText2 + 16)] != snapshot[Channels.powerOnText1..<(Channels.powerOnText2 + 16)]
        guard !changed.isEmpty || textChanged else { alert("Nothing to write", "No channel was changed."); return }
        let blocks = mem.changedBlocks(from: ChannelMemory(bytes: snapshot, profile: profile))
        let list = changed.prefix(12).map { i -> String in
            if let c = mem.channel(i) { return "#\(i + 1)  \(c.name.isEmpty ? "(no name)" : c.name)  \(fmtMHz(c.freq))" }
            return "#\(i + 1)  deleted"
        }
        let backup = Self.backupPath(profile, defaults: host?.defaults ?? .standard)
        let a = NSAlert()
        a.messageText = "Write to \(profile.label) on \(port)?"
        a.informativeText = list.joined(separator: "\n") + (changed.count > 12 ? "\n… and \(changed.count - 12) more" : "")
            + (textChanged ? "\nPower-on text: “\(mem.powerOnText(0))” / “\(mem.powerOnText(1))”" : "")
            + "\n\n\(blocks.count) of \(K5.configSize / K5.configBlockSize) configuration blocks will be written. Calibration and settings are not touched."
            + "\n\nFirst the radio is read again and saved as a backup:\n" + backup
            + "\nThen the changed blocks are written, read back and compared, and the radio restarts."
        a.addButton(withTitle: "Back Up & Write")
        a.addButton(withTitle: "Cancel")
        let go: (NSApplication.ModalResponse) -> Void = { r in
            guard r == .alertFirstButtonReturn else { return }
            let edited = self.mem.bytes
            _ = self.host?.runEditorWrite(port: self.port, snapshot: self.snapshot, edited: edited, firmware: self.firmware, backupPath: backup) { res in
                switch res {
                case .ok:
                    self.probeQuietUntil = Date().addingTimeInterval(8)
                    for b in blocks { self.snapshot.replaceSubrange(b..<(b + K5.configBlockSize), with: edited[b..<(b + K5.configBlockSize)]) }
                    self.undoManager?.removeAllActions()
                    self.reloadAll()
                    self.alert("Written and verified", "\(changed.count) channel(s) written. Backup of the radio before the write:\n\(backup)\n\nRestore it with Write Configuration if needed.")
                case .failed(let msg):
                    self.alert("Not written", msg)
                }
            }
        }
        if Self.uiTesting { host?.memoAdd("[editor] confirm: " + a.informativeText.replacingOccurrences(of: "\n", with: " | ")); go(.alertFirstButtonReturn) }
        else { a.beginSheetModal(for: w, completionHandler: go) }
    }

    static func backupPath(_ p: FirmwareProfile, defaults: UserDefaults) -> String {
        let dir = BackupFolder.current(defaults)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return dir.appendingPathComponent("\(f.string(from: Date())) \(p.label.replacingOccurrences(of: " · ", with: " ")).bin").path
    }

    // MARK: - import / export

    /// A .bin has no model in it: nothing is preselected, the user says where it is from
    /// (a Karina V1 file read as K1 would get the wrong scrambler table).
    private func profilePopup() -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.addItem(withTitle: "Choose\u{2026}")
        p.addItems(withTitles: FirmwareProfile.all.map(\.label))
        p.selectItem(at: 0)
        return p
    }

    @objc func importChannels(_ sender: Any?) {
        guard let w = window, editable else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Channels"
        panel.message = "Channels are added like Paste: from the selected row, or the first free row. Settings in the file are ignored."
        panel.allowedContentTypes = [UTType.commaSeparatedText, UTType(filenameExtension: "img") ?? .data, UTType(filenameExtension: "bin") ?? .data]
        let popup = profilePopup()
        let label = NSTextField(labelWithString: "A .bin file (Read Configuration) is from:")
        let acc = NSStackView(views: [label, popup])
        acc.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        panel.accessoryView = acc
        panel.isAccessoryViewDisclosed = true
        panel.beginSheetModal(for: w) { r in
            guard r == .OK, let url = panel.url else { return }
            let i = popup.indexOfSelectedItem - 1
            self.importFile(url, binProfile: i >= 0 ? FirmwareProfile.all[i] : nil)
        }
    }

    func importFile(_ url: URL, binProfile: FirmwareProfile?) {
        do {
            let data = Array(try Data(contentsOf: url))
            let imported: ImportedChannels
            switch url.pathExtension.lowercased() {
            case "csv":
                imported = try ChannelFiles.readCSV(String(decoding: data, as: UTF8.self))
            case "img":
                let img = ChannelFiles.readCHIRPImage(data)
                guard let p = img.profile else {
                    throw ChannelFileError.unknownFormat("This CHIRP image is for '\(img.model ?? "an unknown radio")'. Only UV-K5 / UV-K1 images (stock or Karina) can be imported.")
                }
                imported = try ChannelFiles.channels(ofMemory: img.memory, profile: p)
            default:
                guard data.count == K5.configSize || data.count == K5.maxConfigSize else {
                    throw ChannelFileError.unknownFormat("A .bin from Read Configuration is 7424 or 8192 bytes; this file has \(data.count).")
                }
                guard let binProfile else {
                    throw ChannelFileError.unknownFormat("A .bin file doesn't say which radio and firmware it is from. Import it again and choose them under \u{201C}A .bin file is from\u{201D}.")
                }
                imported = try ChannelFiles.channels(ofMemory: data, profile: binProfile)
            }
            if imported.channels.isEmpty { alert("No channels in \(url.lastPathComponent)", ""); return }
            insert(imported.channels.map(\.channel), slots: imported.channels.map(\.slot), from: imported.source, at: nil,
                   what: "imported from \(url.lastPathComponent)", notes: imported.notes)
        } catch {
            alert("Can't import \(url.lastPathComponent)", "\(error)")
        }
    }

    @objc func exportChannels(_ sender: Any?) {
        guard let w = window else { return }
        let sel = table.selectedRowIndexes.count > 1
        let list: [(slot: Int, channel: Channel)] = sel
            ? table.selectedRowIndexes.compactMap { r in mem.channel(visibleRows[r]).map { (visibleRows[r], $0) } }
            : (0..<Channels.count).compactMap { i in mem.channel(i).map { (i, $0) } }
        let panel = NSSavePanel()
        panel.title = "Export Channels"
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let base = "\(profile.radio == .v1 ? "UV-K5" : "UV-K1") channels \(f.string(from: Date()))"
        panel.nameFieldStringValue = base + ".csv"
        let format = NSPopUpButton(frame: .zero, pullsDown: false)
        format.addItems(withTitles: ["CSV (CHIRP columns)", "CHIRP image (.img, the whole memory)"])
        let note = NSTextField(labelWithString: sel ? "\(list.count) selected channels" : "all \(list.count) channels")
        note.textColor = .secondaryLabelColor
        let acc = NSStackView(views: [NSTextField(labelWithString: "Format:"), format, note])
        acc.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        panel.accessoryView = acc
        format.target = panel
        panel.allowedContentTypes = [.commaSeparatedText]
        format.action = #selector(NSSavePanel.validateVisibleColumns)
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didSendActionNotification, object: format.menu, queue: .main) { _ in
            let img = format.indexOfSelectedItem == 1
            panel.allowedContentTypes = [img ? (UTType(filenameExtension: "img") ?? .data) : .commaSeparatedText]
            panel.nameFieldStringValue = base + (img ? ".img" : ".csv")
            note.stringValue = img ? "all channels (a CHIRP image is the whole memory)" : (sel ? "\(list.count) selected channels" : "all \(list.count) channels")
        }
        panel.beginSheetModal(for: w) { r in
            NotificationCenter.default.removeObserver(observer)
            guard r == .OK, let url = panel.url else { return }
            let bytes: [UInt8] = format.indexOfSelectedItem == 1
                ? ChannelFiles.chirpImage(self.mem.bytes, profile: self.profile, firmwareString: self.firmware)
                : Array(ChannelFiles.csv(list).utf8)
            do { try Data(bytes).write(to: url) } catch { self.alert("Not saved", "\(error)") }
        }
    }

    // MARK: - window

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if !dirty { return true }
        confirm("Close without writing?", "Your changes have not been written to the radio. (Export Channels keeps them in a file.)", "Close") {
            self.snapshot = self.mem.bytes
            self.window?.close()
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        probeTimer?.invalidate()
        Self.open[port] = nil
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undo }
    private let undo = UndoManager()

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(paste(_:)), #selector(delete(_:)), #selector(importChannels(_:)): return editable
        case #selector(copy(_:)): return !table.selectedRowIndexes.isEmpty
        default: return true
        }
    }

    // MARK: - UI test mode (see MainWindowController.uiTestStep)

    private static let uiTesting = ProcessInfo.processInfo.environment["K5PROG_UITEST"] != nil

    func uiTest(_ step: String) {
        let env = ProcessInfo.processInfo.environment
        switch step {
        case "import":
            let bp = env["K5PROG_UITEST_BIN_PROFILE"].flatMap(FirmwareProfile.init(key:))
            if let path = env["K5PROG_UITEST_OPEN"] { importFile(URL(fileURLWithPath: path), binProfile: bp) }
        case "write":
            writeToRadio()
        case "export":
            if let path = env["K5PROG_UITEST_SAVE"] {
                try? Data(path.hasSuffix(".img") ? ChannelFiles.chirpImage(mem.bytes, profile: profile, firmwareString: firmware)
                                                 : Array(ChannelFiles.csv((0..<Channels.count).compactMap { i in mem.channel(i).map { (i, $0) } }).utf8))
                    .write(to: URL(fileURLWithPath: path))
            }
        case let x where x.hasPrefix("edit=") || x.hasPrefix("set="):
            // edit=<column>:<channel number>: as if double-clicked; set=<column>:<channel>:<text>: typed + Enter
            let p = x.split(separator: "=", maxSplits: 1)[1].split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            if p.count >= 2, let col = Col(rawValue: String(p[0])), let n = Int(p[1]),
               let row = visibleRows.firstIndex(of: n - 1) {
                table.selectRowIndexes([row], byExtendingSelection: false)
                let colIdx = table.column(withIdentifier: .init(col.rawValue))
                editText(col, n - 1, row: row, colIdx: colIdx)
                if let f = table.view(atColumn: colIdx, row: row, makeIfNecessary: false) as? NSTextField,
                   let tv = f.currentEditor() as? NSTextView {
                    host?.memoAdd("[editor] editing \(col.rawValue) \(n): selection \(tv.selectedRange().length) chars, caret alpha \(tv.insertionPointColor.alphaComponent)")
                }
                if p.count == 3, let f = table.view(atColumn: colIdx, row: row, makeIfNecessary: false) as? NSTextField {
                    f.stringValue = String(p[2])
                    textCommitted(f)
                }
            }
        case "caret-end":   // collapse the selection of the cell being edited: the caret must show
            if let tv = window?.firstResponder as? NSTextView {
                tv.setSelectedRange(NSRange(location: tv.string.utf16.count, length: 0))
                host?.memoAdd("[editor] no selection: caret alpha \(tv.insertionPointColor.alphaComponent)")
            }
        case "caret":   // the shared field editor's caret is back after a cell edit (search field)
            window?.makeFirstResponder(search)
            if let tv = search.currentEditor() as? NSTextView {
                host?.memoAdd("[editor] search caret alpha \(tv.insertionPointColor.alphaComponent)")
            }
        case let x where x.hasPrefix("profile="):   // as if picked with the selectors
            if let p = FirmwareProfile(key: String(x.dropFirst(8))) { setProfile(p, confirm: true) }
        case "close":
            snapshot = mem.bytes
            window?.close()
        default: break
        }
    }

    private func alert(_ title: String, _ text: String) {
        if Self.uiTesting { host?.memoAdd("[editor] " + title + (text.isEmpty ? "" : " | " + text.replacingOccurrences(of: "\n", with: " | "))); return }
        guard let w = window else { return }
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        // never runModal: it would pull the app to the front while the user works elsewhere
        if w.attachedSheet == nil { a.beginSheetModal(for: w) }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.alert(title, text) } }
    }

    private func confirm(_ title: String, _ text: String, _ ok: String, _ action: @escaping () -> Void) {
        guard let w = window else { return }
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: ok)
        a.addButton(withTitle: "Cancel")
        a.beginSheetModal(for: w) { if $0 == .alertFirstButtonReturn { action() } }
    }
}

private extension RadioType {
    var short: String { self == .v1 ? "UV-K5 V1" : "UV-K1 / K5 V3" }
}
