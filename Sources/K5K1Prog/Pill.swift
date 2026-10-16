// K5K1 Prog - macOS programmer for Quansheng UV-K5 / UV-K5 V3 / UV-K1 radios.
//
// Rounded status pill (2.0): a tinted frame with one or two lines of text.
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

final class Pill: NSView {
    private let line1 = NSTextField(labelWithString: "")
    private let line2 = NSTextField(labelWithString: "")
    private var tint = NSColor.systemGray

    init(compact: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.cornerRadius = compact ? 9 : 12
        line1.font = NSFont.systemFont(ofSize: compact ? 11 : 13, weight: .medium)
        line2.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        for l in [line1, line2] {
            l.lineBreakMode = .byTruncatingTail
            l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let stack = NSStackView(views: [line1, line2])
        stack.orientation = compact ? .horizontal : .vertical
        stack.alignment = compact ? .firstBaseline : .leading
        stack.spacing = compact ? 6 : 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: compact ? 9 : 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: compact ? -9 : -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: compact ? 2 : 5),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: compact ? -2 : -5),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ first: String, _ second: String = "", tint: NSColor) {
        line1.stringValue = first
        line2.stringValue = second
        line2.isHidden = second.isEmpty
        self.tint = tint
        isHidden = first.isEmpty
        applyColors()
    }

    func setToolTip(_ s: String?) { toolTip = s; line1.toolTip = s; line2.toolTip = s }

    private func applyColors() {
        line1.textColor = tint
        line2.textColor = tint.withAlphaComponent(0.8)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = tint.withAlphaComponent(0.6).cgColor
            layer?.backgroundColor = tint.withAlphaComponent(0.10).cgColor
        }
    }

    // layer colours are CGColors: refresh them when Light / Dark changes
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }
}

/// Sidebar entry of the Memory Editor: title, a count on the right, rounded highlight when
/// selected (like the source list of the web sketch).
final class SideItem: NSView {
    private let title = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private let action: () -> Void
    var selected = false { didSet { applyColors() } }

    init(_ text: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        title.stringValue = text
        title.font = NSFont.systemFont(ofSize: 13)
        count.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        count.alignment = .right
        for v in [title, count] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            count.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 6),
        ])
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setCount(_ s: String) { count.stringValue = s }

    override func mouseDown(with event: NSEvent) { action() }

    private func applyColors() {
        title.textColor = selected ? .labelColor : .secondaryLabelColor
        title.font = NSFont.systemFont(ofSize: 13, weight: selected ? .medium : .regular)
        count.textColor = .secondaryLabelColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = selected ? NSColor.labelColor.withAlphaComponent(0.10).cgColor : NSColor.clear.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }
}
