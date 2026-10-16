// K5K1 Prog - macOS programmer for Quansheng UV-K5 / UV-K5 V3 / UV-K1 radios.
//
// Settings window (2.0, not in k5prog-win): appearance and where the Memory Editor saves
// its backups.
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

enum BackupFolder {
    static let key = "Editor.BackupFolder"

    static var standard: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("K5K1 Prog Backups")
    }

    /// K5PROG_BACKUP_DIR (dev / UI tests) > the folder chosen in Settings > ~/Documents/K5K1 Prog Backups
    static func current(_ defaults: UserDefaults) -> URL {
        if let env = ProcessInfo.processInfo.environment["K5PROG_BACKUP_DIR"] { return URL(fileURLWithPath: env) }
        if let p = defaults.string(forKey: key), !p.isEmpty { return URL(fileURLWithPath: p) }
        return standard
    }
}

enum Appearance: Int, CaseIterable {
    case auto = 0, light, dark
    static let key = "GUI.Appearance"
    var title: String { ["Auto", "Light", "Dark"][rawValue] }

    static func current(_ defaults: UserDefaults) -> Appearance { Appearance(rawValue: defaults.integer(forKey: key)) ?? .auto }

    /// Auto follows the system setting.
    static func apply(_ defaults: UserDefaults) {
        switch current(defaults) {
        case .auto: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

final class SettingsWindowController: NSWindowController {
    private let defaults: UserDefaults
    private let pathField = NSPathControl()
    private let defaultButton = NSButton(title: "Use Default Folder", target: nil, action: nil)
    private let appearance = NSSegmentedControl(labels: Appearance.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 210),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Settings"
        super.init(window: w)
        build()
        refresh()
        w.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        let lookTitle = NSTextField(labelWithString: "Appearance")
        lookTitle.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        appearance.target = self
        appearance.action = #selector(appearanceChanged)
        let lookNote = NSTextField(labelWithString: "Auto follows the macOS setting.")
        lookNote.textColor = .secondaryLabelColor
        lookNote.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let sep = NSBox()
        sep.boxType = .separator

        let title = NSTextField(labelWithString: "Memory Editor backups")
        title.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        let note = NSTextField(wrappingLabelWithString: "Before every Write to Radio the radio's configuration is saved here. Restore it with Write Configuration.")
        note.textColor = .secondaryLabelColor
        note.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        pathField.pathStyle = .standard
        pathField.isEditable = false
        pathField.target = self
        pathField.doubleAction = #selector(reveal)
        pathField.toolTip = "Double-click to show in Finder"
        pathField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let choose = NSButton(title: "Choose\u{2026}", target: self, action: #selector(choose))
        choose.bezelStyle = .rounded
        let row = NSStackView(views: [pathField, choose])
        row.spacing = 8

        defaultButton.target = self
        defaultButton.action = #selector(useDefault)
        defaultButton.bezelStyle = .rounded
        defaultButton.controlSize = .small
        defaultButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [lookTitle, appearance, lookNote, sep, title, row, defaultButton, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(4, after: row)
        stack.setCustomSpacing(4, after: appearance)
        stack.setCustomSpacing(14, after: lookNote)
        stack.setCustomSpacing(14, after: sep)

        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sep.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func appearanceChanged() {
        defaults.set(appearance.selectedSegment, forKey: Appearance.key)
        Appearance.apply(defaults)
    }

    private func refresh() {
        appearance.selectedSegment = Appearance.current(defaults).rawValue
        pathField.url = BackupFolder.current(defaults)
        let custom = !(defaults.string(forKey: BackupFolder.key) ?? "").isEmpty
        defaultButton.isEnabled = custom
        defaultButton.toolTip = BackupFolder.standard.path
    }

    @objc private func choose() {
        guard let w = window else { return }
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Use This Folder"
        p.message = "Folder for the Memory Editor's backups"
        let cur = BackupFolder.current(defaults)
        p.directoryURL = FileManager.default.fileExists(atPath: cur.path) ? cur : cur.deletingLastPathComponent()
        p.beginSheetModal(for: w) { r in
            guard r == .OK, let url = p.url else { return }
            if !FileManager.default.isWritableFile(atPath: url.path) {
                let a = NSAlert()
                a.messageText = "Can't write to this folder"
                a.informativeText = url.path
                a.beginSheetModal(for: w)
                return
            }
            self.defaults.set(url.path, forKey: BackupFolder.key)
            self.refresh()
        }
    }

    @objc private func useDefault() {
        defaults.removeObject(forKey: BackupFolder.key)
        refresh()
    }

    @objc private func reveal() {
        let url = BackupFolder.current(defaults)
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}
