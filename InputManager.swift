import Foundation
import GameController
import SwiftUI

enum Defaults {
    static let ip = "ip"
    static let autoconnect = "autoconnect"
    static let matchLabels = "matchLabels"
    static let invertCX = "invertCX"
    static let invertCY = "invertCY"
    static let deadzone = "deadzone"
    static let promptUnknown = "promptUnknown"
    static let bindings = "bindings"
}

struct ButtonBinding: Codable, Equatable {
    var key: Int
    var name: String
}

struct PendingBind: Identifiable {
    let id: String
    let name: String
}

/// Reads the connected MFi / Xbox / PlayStation / Switch Pro controller and drives the Sender.
final class InputManager: ObservableObject {
    @Published var status = "Disconnected"
    @Published var controllerName = "No controller"
    @Published var connected = false
    @Published var readout = PadState()
    @Published var pending: PendingBind?      // unknown button waiting to be bound
    @Published var learning = false           // "Bind a button" mode
    @Published var bindings: [String: ButtonBinding] = [:]

    private var pad: GCController?
    private var dismissed = Set<String>()

    private let sender = Sender()
    private var gamepadState = PadState()
    private var touch: (x: Int, y: Int)? = nil

    init() {
        UserDefaults.standard.register(defaults: [
            Defaults.ip: "", Defaults.autoconnect: false, Defaults.matchLabels: false,
            Defaults.invertCX: false, Defaults.invertCY: false, Defaults.deadzone: 0.08, Defaults.promptUnknown: true,
        ])
        sender.onStatus = { [weak self] s in
            DispatchQueue.main.async {
                self?.status = s
                self?.connected = self?.sender.isRunning ?? false
            }
        }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(controllersChanged), name: .GCControllerDidConnect, object: nil)
        nc.addObserver(self, selector: #selector(controllersChanged), name: .GCControllerDidDisconnect, object: nil)
        if let data = UserDefaults.standard.data(forKey: Defaults.bindings),
           let b = try? JSONDecoder().decode([String: ButtonBinding].self, from: data) { bindings = b }
        controllersChanged()
        if UserDefaults.standard.bool(forKey: Defaults.autoconnect) { connect() }
    }

    var ip: String { UserDefaults.standard.string(forKey: Defaults.ip) ?? "" }

    func connect() { sender.start(host: ip); publish() }
    func disconnect() { sender.stop() }

    // MARK: Touch screen

    /// `nx`/`ny` are normalised 0...1 positions within the on-screen touch pad; nil = finger lifted.
    func setTouch(nx: Double?, ny: Double?) {
        if let nx = nx, let ny = ny {
            let x = Int(min(max(nx, 0), 1) * 4095)
            let y = Int(min(max(ny, 0), 1) * 4095)
            touch = (x, y)
        } else {
            touch = nil
        }
        publish()
    }

    // MARK: Controller

    @objc private func controllersChanged() {
        let c = GCController.controllers().first(where: { $0.extendedGamepad != nil })
        DispatchQueue.main.async {
            self.pad = c
            self.controllerName = c?.vendorName ?? "No controller"
            guard let c = c, let g = c.extendedGamepad else {
                self.gamepadState = PadState(); self.publish(); return
            }
            g.valueChangedHandler = { [weak self] _, element in
                self?.changed(element)
            }
            // Also watch every physical button (paddles, Share, touchpad...) for the binding prompt.
            for b in c.physicalInputProfile.allButtons {
                b.pressedChangedHandler = { [weak self] button, _, _ in
                    self?.changed(button)
                }
            }
            self.read(g)
        }
    }

    // MARK: Binding unknown buttons

    /// Stable name for a button element (same value used when saving and looking up).
    private func id(_ e: GCControllerElement) -> String {
        e.aliases.sorted().first ?? e.localizedName ?? "unknown"
    }

    /// Buttons the app already maps by default, with the 3DS key each one drives.
    private func defaultMap(_ g: GCExtendedGamepad) -> [(GCControllerButtonInput?, Key)] {
        let m = UserDefaults.standard.bool(forKey: Defaults.matchLabels)
        // Default is positional: 3DS diamond (A east, B south, X north, Y west).
        // "Match labels" keeps the printed letters instead.
        return [
            (g.buttonA, m ? .a : .b), (g.buttonB, m ? .b : .a),
            (g.buttonX, m ? .x : .y), (g.buttonY, m ? .y : .x),
            (g.leftShoulder, .l), (g.rightShoulder, .r),
            (g.leftTrigger, .zl), (g.rightTrigger, .zr),
            (g.buttonMenu, .start), (g.buttonOptions, .select),
            (g.leftThumbstickButton, .l3), (g.buttonHome, .l3),
            (g.rightThumbstickButton, .r3),
            (g.dpad.left, .dLeft), (g.dpad.right, .dRight),
            (g.dpad.up, .dUp), (g.dpad.down, .dDown),
        ]
    }

    private func changed(_ element: GCControllerElement) {
        guard let g = pad?.extendedGamepad else { return }
        read(g)
        guard pending == nil, let b = element as? GCControllerButtonInput, b.isPressed else { return }
        let bid = id(b)
        let known = Set(defaultMap(g).compactMap { $0.0 }.map { id($0) })
        let prompt = UserDefaults.standard.bool(forKey: Defaults.promptUnknown)
        if learning || (prompt && !known.contains(bid) && bindings[bid] == nil && !dismissed.contains(bid)) {
            learning = false
            pending = PendingBind(id: bid, name: b.localizedName ?? bid)
        }
    }

    func startLearning() { learning = true }

    func bind(_ p: PendingBind, to key: Key?) {
        if let key = key {
            bindings[p.id] = ButtonBinding(key: key.rawValue, name: p.name)
            saveBindings()
        } else {
            dismissed.insert(p.id)
        }
        pending = nil
        learning = false
        if let g = pad?.extendedGamepad { read(g) }
    }

    func cancelPending() { if let p = pending { dismissed.insert(p.id); pending = nil } }

    func unbind(_ bid: String) {
        bindings[bid] = nil
        saveBindings()
        if let g = pad?.extendedGamepad { read(g) }
    }

    func resetBindings() {
        bindings = [:]; dismissed = []
        saveBindings()
        if let g = pad?.extendedGamepad { read(g) }
    }

    private func saveBindings() {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Defaults.bindings)
        }
    }

    private func axis(_ v: Float, _ deadzone: Double, invert: Bool = false) -> Int {
        if Double(abs(v)) < deadzone { return 0 }
        let n = max(-32767, min(32767, Int(32767 * v)))
        return invert ? -n : n
    }

    private func read(_ g: GCExtendedGamepad) {
        let d = UserDefaults.standard
        let dz = d.double(forKey: Defaults.deadzone)
        var s = PadState()

        // Default mapping, skipping any button the user has re-bound.
        for (button, key) in defaultMap(g) {
            guard let button = button, bindings[id(button)] == nil else { continue }
            if button.isPressed { s.set(key, true) }
        }
        // Custom bindings (apply to any button the controller reports).
        for button in pad?.physicalInputProfile.buttons.values.map({ $0 }) ?? [] {
            if let bd = bindings[id(button)], let key = Key(rawValue: bd.key), button.isPressed {
                s.set(key, true)
            }
        }

        s.cpadX = axis(g.leftThumbstick.xAxis.value, dz)
        s.cpadY = axis(g.leftThumbstick.yAxis.value, dz)
        s.cstickX = axis(g.rightThumbstick.xAxis.value, dz, invert: d.bool(forKey: Defaults.invertCX))
        s.cstickY = axis(g.rightThumbstick.yAxis.value, dz, invert: d.bool(forKey: Defaults.invertCY))

        gamepadState = s
        publish()
    }

    private func publish() {
        var s = gamepadState
        s.touch = touch
        s.set(.touch, touch != nil)
        sender.update(s)
        DispatchQueue.main.async { self.readout = s }
    }
}
