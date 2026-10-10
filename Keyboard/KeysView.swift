import UIKit
import Combine
import AudioToolbox

/// The typing keys, drawn and touch-handled like Apple's keyboard:
/// one touch surface (so fast typing and two-thumb rollover work), letter pop-ups,
/// key clicks and haptics, hold-to-repeat delete, and hold-space-to-move-cursor.
final class KeysView: UIView {
    static let keyHeight: CGFloat = 43
    static let rowGap: CGFloat = 11
    static let keyGap: CGFloat = 6
    static let sideInset: CGFloat = 3
    static let topInset: CGFloat = 8
    static let bottomInset: CGFloat = 4
    static var preferredHeight: CGFloat { topInset + keyHeight * 4 + rowGap * 3 + bottomInset }

    private enum Kind: Equatable {
        case char(String), shift, delete, layerSwitch, altLayer, globe, space, returnKey
        var isChar: Bool { if case .char = self { return true } else { return false } }
        var isSpecial: Bool {
            switch self {
            case .char, .space: return false
            default: return true
            }
        }
    }

    private struct Key {
        let kind: Kind
        var frame: CGRect
        let view: KeyCapView
    }

    private let model: KeyboardModel
    private var keys: [Key] = []
    private var bag = Set<AnyCancellable>()
    private let popup = KeyPopupView()

    private var touchKeys: [ObjectIdentifier: Int] = [:]
    private var repeatTimer: Timer?
    private var spaceTouch: (id: ObjectIdentifier, startX: CGFloat, lastStep: Int, began: Date, moved: Bool)?

    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var soundsOn = true
    private var hapticsOn = true

    init(model: KeyboardModel) {
        self.model = model
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        clipsToBounds = false
        popup.isHidden = true
        // Typing state talks to the keys directly (not through SwiftUI), so keystrokes stay fast.
        model.onLayoutChange = { [weak self] in
            DispatchQueue.main.async { self?.rebuild() }   // after the current touch finishes
        }
        model.onShiftChange = { [weak self] in self?.updateLabels() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reloadSettings() {
        soundsOn = SharedStore.keySounds
        hapticsOn = SharedStore.haptics
        haptic.prepare()
    }

    private var lastWidth: CGFloat = 0
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastWidth { lastWidth = bounds.width; rebuild() }
    }

    // MARK: - Layout

    private func rows() -> ([String], [String], [String]) {
        switch model.layer {
        case .letters:
            return ("qwertyuiop".map(String.init), "asdfghjkl".map(String.init), "zxcvbnm".map(String.init))
        case .numbers:
            return ("1234567890".map(String.init),
                    ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
                    [".", ",", "?", "!", "'"])
        case .symbols:
            return (["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                    ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
                    [".", ",", "?", "!", "'"])
        }
    }

    private func rebuild() {
        guard bounds.width > 0 else { return }
        keys.forEach { $0.view.removeFromSuperview() }
        keys.removeAll()
        touchKeys.removeAll()
        hidePopup()

        let g = Self.keyGap, h = Self.keyHeight
        let inner = bounds.width - Self.sideInset * 2
        let unit = (inner - g * 9) / 10
        var y = Self.topInset
        let (r1, r2, r3) = rows()

        func addRow(_ chars: [String], width: CGFloat, y: CGFloat) {
            let total = CGFloat(chars.count) * width + CGFloat(chars.count - 1) * g
            var x = (bounds.width - total) / 2
            for c in chars {
                add(.char(c), CGRect(x: x, y: y, width: width, height: h))
                x += width + g
            }
        }

        addRow(r1, width: unit, y: y); y += h + Self.rowGap
        addRow(r2, width: unit, y: y); y += h + Self.rowGap

        // Row 3: shift / #+= / 123 · characters · delete
        let modWidth = unit * 1.35
        add(model.layer == .letters ? .shift : .altLayer, CGRect(x: Self.sideInset, y: y, width: modWidth, height: h))
        add(.delete, CGRect(x: bounds.width - Self.sideInset - modWidth, y: y, width: modWidth, height: h))
        let r3Width = model.layer == .letters ? unit : (inner - modWidth * 2 - g * 6 - unit * 0.6) / 5
        addRow(r3, width: r3Width, y: y)
        y += h + Self.rowGap

        // Row 4: 123/ABC · (globe) · space · return
        var x = Self.sideInset
        let switchWidth = unit * 1.3
        add(.layerSwitch, CGRect(x: x, y: y, width: switchWidth, height: h)); x += switchWidth + g
        if model.showGlobe {
            add(.globe, CGRect(x: x, y: y, width: unit * 1.1, height: h)); x += unit * 1.1 + g
        }
        let returnWidth = unit * 2.1
        let spaceWidth = bounds.width - Self.sideInset - returnWidth - g - x
        add(.space, CGRect(x: x, y: y, width: spaceWidth, height: h))
        add(.returnKey, CGRect(x: bounds.width - Self.sideInset - returnWidth, y: y, width: returnWidth, height: h))

        addSubview(popup)    // above the keys
        updateLabels()
    }

    private func add(_ kind: Kind, _ frame: CGRect) {
        let view = KeyCapView(frame: frame, special: kind.isSpecial)
        addSubview(view)
        keys.append(Key(kind: kind, frame: frame, view: view))
    }

    private func updateLabels() {
        let upper = model.layer == .letters && model.shift != .off
        for key in keys {
            switch key.kind {
            case .char(let c):
                key.view.setText(upper ? c.uppercased() : c, size: model.layer == .letters ? 25 : 23)
            case .shift:
                let name = model.shift == .locked ? "capslock.fill" : model.shift == .once ? "shift.fill" : "shift"
                key.view.setSymbol(name)
                key.view.special = model.shift == .off      // lights up white when on, like Apple's
            case .delete: key.view.setSymbol("delete.left")
            case .altLayer: key.view.setText(model.layer == .numbers ? "#+=" : "123", size: 16)
            case .layerSwitch: key.view.setText(model.layer == .letters ? "123" : "ABC", size: 16)
            case .globe: key.view.setSymbol("globe")
            case .space: key.view.setText("space", size: 16)
            case .returnKey: key.view.setText("return", size: 16)
            }
        }
    }

    // MARK: - Touch handling

    /// The key under a point; gaps between keys belong to the nearest key, like Apple's keyboard.
    private func keyIndex(at point: CGPoint) -> Int? {
        guard !keys.isEmpty else { return nil }
        var best: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (i, key) in keys.enumerated() {
            let f = key.frame.insetBy(dx: -Self.keyGap / 2, dy: -Self.rowGap / 2)
            if f.contains(point) { return i }
            let dx = max(f.minX - point.x, 0, point.x - f.maxX)
            let dy = max(f.minY - point.y, 0, point.y - f.maxY)
            let d = dx * dx + dy * dy
            if d < bestDistance { bestDistance = d; best = i }
        }
        return best
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let i = keyIndex(at: touch.location(in: self)) else { continue }
            let kind = keys[i].kind

            // Two-thumb rollover: a new key press commits any letter still held down.
            for (id, held) in touchKeys where keys.indices.contains(held) && keys[held].kind.isChar {
                commit(keys[held].kind)
                keys[held].view.setPressed(false)
                touchKeys[id] = nil
            }

            touchKeys[ObjectIdentifier(touch)] = i
            keys[i].view.setPressed(kind != .shift)
            feedback(for: kind)

            switch kind {
            case .char:
                showPopup(for: i)
            case .delete:
                model.deleteBackward()
                startRepeating()
            case .shift:
                model.tapShift()
            case .space:
                spaceTouch = (ObjectIdentifier(touch), touch.location(in: self).x, 0, Date(), false)
            default:
                break
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let current = touchKeys[id] else { continue }
            let point = touch.location(in: self)

            // Hold space and slide to move the cursor
            if let s = spaceTouch, s.id == id {
                if Date().timeIntervalSince(s.began) > 0.25 || s.moved {
                    let step = Int((point.x - s.startX) / 9)
                    if step != s.lastStep {
                        if !s.moved { keys[current].view.setText("", size: 16) }
                        model.moveCursor(by: step - s.lastStep)
                        spaceTouch = (s.id, s.startX, step, s.began, true)
                    }
                }
                continue
            }

            // Sliding a finger across letters moves the highlight, like Apple's keyboard
            if keys[current].kind.isChar, let next = keyIndex(at: point), next != current, keys[next].kind.isChar {
                keys[current].view.setPressed(false)
                keys[next].view.setPressed(true)
                touchKeys[id] = next
                showPopup(for: next)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let i = touchKeys.removeValue(forKey: id), keys.indices.contains(i) else { continue }
            let kind = keys[i].kind
            keys[i].view.setPressed(false)

            if let s = spaceTouch, s.id == id {
                spaceTouch = nil
                if s.moved { updateLabels(); continue }      // was a cursor move, not a space
            }
            switch kind {
            case .delete: stopRepeating()
            case .shift: break                                  // acted on touch-down
            default: commit(kind)
            }
        }
        if !touchKeys.values.contains(where: { keys.indices.contains($0) && keys[$0].kind.isChar }) { hidePopup() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let i = touchKeys.removeValue(forKey: ObjectIdentifier(touch)), keys.indices.contains(i) {
                keys[i].view.setPressed(false)
            }
        }
        stopRepeating()
        spaceTouch = nil
        hidePopup()
        updateLabels()
    }

    private func commit(_ kind: Kind) {
        switch kind {
        case .char(let c): model.type(c)
        case .space: model.space()
        case .returnKey: model.newline()
        case .layerSwitch: model.setLayer(model.layer == .letters ? .numbers : .letters)
        case .altLayer: model.setLayer(model.layer == .numbers ? .symbols : .numbers)
        case .globe: model.nextKeyboard()
        case .shift, .delete: break
        }
    }

    // MARK: - Delete repeat

    private func startRepeating() {
        stopRepeating()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.model.deleteBackward()
                if self.soundsOn { AudioServicesPlaySystemSound(1155) }
            }
        }
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    // MARK: - Feedback

    private func feedback(for kind: Kind) {
        if hapticsOn { haptic.impactOccurred(intensity: 0.7); haptic.prepare() }
        guard soundsOn else { return }
        switch kind {
        case .char: AudioServicesPlaySystemSound(1104)
        case .delete: AudioServicesPlaySystemSound(1155)
        default: AudioServicesPlaySystemSound(1156)
        }
    }

    // MARK: - Letter pop-up

    private func showPopup(for i: Int) {
        guard case .char(let c) = keys[i].kind else { return }
        let upper = model.layer == .letters && model.shift != .off
        popup.show(text: upper ? c.uppercased() : c, keyFrame: keys[i].frame, in: bounds)
        bringSubviewToFront(popup)
    }

    private func hidePopup() { popup.isHidden = true }
}

// MARK: - One key cap

final class KeyCapView: UIView {
    private let face = UIView()
    private let label = UILabel()
    private let symbol = UIImageView()
    private var pressed = false

    var special: Bool { didSet { refreshColors() } }

    init(frame: CGRect, special: Bool) {
        self.special = special
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        face.frame = bounds
        face.layer.cornerRadius = 8
        face.layer.cornerCurve = .continuous
        face.layer.shadowOffset = CGSize(width: 0, height: 1)
        face.layer.shadowRadius = 0
        face.layer.shadowOpacity = 1
        addSubview(face)

        label.frame = bounds
        label.textAlignment = .center
        label.textColor = .label
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        addSubview(label)

        symbol.frame = bounds
        symbol.contentMode = .center
        symbol.tintColor = .label
        addSubview(symbol)

        refreshColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setText(_ text: String, size: CGFloat) {
        symbol.image = nil
        label.text = text
        label.font = .systemFont(ofSize: size, weight: size >= 22 ? .regular : .regular)
        // Lowercase letters sit slightly high in the system font; nudge to match Apple's keys.
        label.frame = bounds.offsetBy(dx: 0, dy: (size >= 22 && text == text.lowercased()) ? -1.5 : 0)
    }

    func setSymbol(_ name: String) {
        label.text = nil
        symbol.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular))
    }

    func setPressed(_ on: Bool) {
        guard on != pressed else { return }
        pressed = on
        refreshColors()
    }

    private func refreshColors() {
        let base: UIColor = special ? .keySpecial : .keyLetter
        let down: UIColor = special ? .keyLetter : .keySpecial
        face.backgroundColor = pressed ? down : base
        face.layer.shadowColor = UIColor.keyShadow.resolvedColor(with: traitCollection).cgColor
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        refreshColors()
    }
}

// MARK: - The balloon that pops up above a pressed letter

final class KeyPopupView: UIView {
    private let label = UILabel()
    private var keyRect: CGRect = .zero   // the key's position inside this view

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 40, weight: .regular)
        label.textColor = .label
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(text: String, keyFrame: CGRect, in container: CGRect) {
        let bulgeWidth = keyFrame.width + 22
        let bulgeHeight = keyFrame.height + 4
        let totalHeight = bulgeHeight + keyFrame.height + 6
        var x = keyFrame.midX - bulgeWidth / 2
        x = min(max(x, container.minX + 1), container.maxX - bulgeWidth - 1)   // keep edge keys on screen
        frame = CGRect(x: x, y: keyFrame.maxY - totalHeight, width: bulgeWidth, height: totalHeight)
        keyRect = CGRect(x: keyFrame.minX - x, y: totalHeight - keyFrame.height,
                         width: keyFrame.width, height: keyFrame.height)
        label.text = text
        label.frame = CGRect(x: 0, y: 2, width: bulgeWidth, height: bulgeHeight - 6)
        isHidden = false
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let r: CGFloat = 9
        let bulge = CGRect(x: 0.5, y: 0.5, width: bounds.width - 1, height: keyRect.minY - 6)
        let stem = keyRect
        let path = UIBezierPath()
        // Bulge (top) with a smooth neck down into the key-shaped stem
        path.move(to: CGPoint(x: bulge.minX + r, y: bulge.minY))
        path.addLine(to: CGPoint(x: bulge.maxX - r, y: bulge.minY))
        path.addQuadCurve(to: CGPoint(x: bulge.maxX, y: bulge.minY + r), controlPoint: CGPoint(x: bulge.maxX, y: bulge.minY))
        path.addLine(to: CGPoint(x: bulge.maxX, y: bulge.maxY - r))
        path.addCurve(to: CGPoint(x: stem.maxX, y: stem.minY + 4),
                      controlPoint1: CGPoint(x: bulge.maxX, y: bulge.maxY + 2),
                      controlPoint2: CGPoint(x: stem.maxX, y: stem.minY - 4))
        path.addLine(to: CGPoint(x: stem.maxX, y: stem.maxY - 8))
        path.addQuadCurve(to: CGPoint(x: stem.maxX - 8, y: stem.maxY), controlPoint: CGPoint(x: stem.maxX, y: stem.maxY))
        path.addLine(to: CGPoint(x: stem.minX + 8, y: stem.maxY))
        path.addQuadCurve(to: CGPoint(x: stem.minX, y: stem.maxY - 8), controlPoint: CGPoint(x: stem.minX, y: stem.maxY))
        path.addLine(to: CGPoint(x: stem.minX, y: stem.minY + 4))
        path.addCurve(to: CGPoint(x: bulge.minX, y: bulge.maxY - r),
                      controlPoint1: CGPoint(x: stem.minX, y: stem.minY - 4),
                      controlPoint2: CGPoint(x: bulge.minX, y: bulge.maxY + 2))
        path.addLine(to: CGPoint(x: bulge.minX, y: bulge.minY + r))
        path.addQuadCurve(to: CGPoint(x: bulge.minX + r, y: bulge.minY), controlPoint: CGPoint(x: bulge.minX, y: bulge.minY))
        path.close()
        UIColor.keyLetter.setFill()
        path.fill()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        setNeedsDisplay()
    }
}
