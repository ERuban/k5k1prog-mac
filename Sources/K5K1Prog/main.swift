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
import K5Core
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    var controller: MainWindowController?

    /// In-app updates (not part of k5prog-win). Started only inside a real .app with a feed
    /// URL in its Info.plist, so `swift run` / tests never show Sparkle errors.
    private lazy var updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self,
                                                            userDriverDelegate: nil)
    private var updatesEnabled: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
    }

    /// Test hook: K5PROG_SPARKLE_FEED=<url> replaces the release feed (local update tests).
    func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["K5PROG_SPARKLE_FEED"]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if updatesEnabled { updater.startUpdater() }
        buildMenu()
        let c = MainWindowController()
        controller = c
        Appearance.apply(c.defaults)
        c.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let unwritten = MemoryEditorWindowController.open.values.filter(\.hasUnwrittenChanges)
        if !unwritten.isEmpty {
            unwritten.first?.showWindow(nil)
            let a = NSAlert()
            a.messageText = "Quit without writing?"
            a.informativeText = "The Memory Editor has changes that are not written to the radio: " + unwritten.map(\.port).joined(separator: ", ")
            a.addButton(withTitle: "Quit")
            a.addButton(withTitle: "Cancel")
            if a.runModal() != .alertFirstButtonReturn { return .terminateCancel }
        }
        guard let c = controller else { return .terminateNow }
        return c.formCloseQuery() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        let about = appMenu.addItem(withTitle: "About \(K5.appTitle)", action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        if updatesEnabled {
            let check = appMenu.addItem(withTitle: "Check for Updates…",
                                        action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
            check.target = updater
        }
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings\u{2026}", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(K5.appTitle)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Import Channels\u{2026}", action: #selector(MemoryEditorWindowController.importChannels(_:)), keyEquivalent: "i").keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "Export Channels\u{2026}", action: #selector(MemoryEditorWindowController.exportChannels(_:)), keyEquivalent: "e").keyEquivalentModifierMask = [.command, .shift]
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = file

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z").keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "\u{8}").keyEquivalentModifierMask = []
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let radioItem = NSMenuItem()
        main.addItem(radioItem)
        let radio = NSMenu(title: "Radio")
        let me = radio.addItem(withTitle: "Memory Editor\u{2026}", action: #selector(openMemoryEditor(_:)), keyEquivalent: "e")
        me.target = self
        radioItem.submenu = radio

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = window
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }

    private var settingsWindow: SettingsWindowController?

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil, let d = controller?.defaults { settingsWindow = SettingsWindowController(defaults: d) }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func openMemoryEditor(_ sender: Any?) {
        controller?.showWindow(nil)
        controller?.memoryEditorClick()
    }

    @objc func showAbout(_ sender: Any?) {
        let link = "https://github.com/ERuban/k5k1prog-mac"
        let text = NSMutableAttributedString()
        let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let plain: [NSAttributedString.Key: Any] = [.font: small, .paragraphStyle: center,
                                                    .foregroundColor: NSColor.labelColor]
        text.append(NSAttributedString(string: "By Evgeny Ruban\n\n", attributes: plain))
        text.append(NSAttributedString(string: "macOS port of k5prog-win by OneOfEleven,\nbased on k5prog by Jacek Lipkowski SQ5BPF.\n\n", attributes: plain))
        text.append(NSAttributedString(string: "Memory Editor: channel layout from the CHIRP drivers\nby Jacek Lipkowski SQ5BPF, Thibaut Berg and M2Boo.\n\n", attributes: plain))
        var linkAttrs = plain
        linkAttrs[.link] = URL(string: link)
        text.append(NSAttributedString(string: link, attributes: linkAttrs))
        text.append(NSAttributedString(string: "\n\nGNU General Public License v3", attributes: plain))
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: K5.appTitle,
            .applicationVersion: K5.version,
            .version: "",
            .credits: text,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 Evgeny Ruban",
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
