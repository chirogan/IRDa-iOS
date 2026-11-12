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
}

/// Reads the connected MFi / Xbox / PlayStation / Switch Pro controller and drives the Sender.
final class InputManager: ObservableObject {
    @Published var status = "Disconnected"
    @Published var controllerName = "No controller"
    @Published var connected = false
    @Published var readout = PadState()

    private let sender = Sender()
    private var gamepadState = PadState()
    private var touch: (x: Int, y: Int)? = nil

    init() {
        UserDefaults.standard.register(defaults: [
            Defaults.ip: "", Defaults.autoconnect: false, Defaults.matchLabels: false,
            Defaults.invertCX: false, Defaults.invertCY: false, Defaults.deadzone: 0.08,
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
        let pad = GCController.controllers().first(where: { $0.extendedGamepad != nil })
        DispatchQueue.main.async {
            self.controllerName = pad?.vendorName ?? "No controller"
            self.connectedPad(pad)
        }
    }

    private func connectedPad(_ c: GCController?) {
        guard let g = c?.extendedGamepad else {
            gamepadState = PadState(); publish(); return
        }
        g.valueChangedHandler = { [weak self] gamepad, _ in
            self?.read(gamepad)
        }
        read(g)
    }

    private func axis(_ v: Float, _ deadzone: Double, invert: Bool = false) -> Int {
        if Double(abs(v)) < deadzone { return 0 }
        let n = max(-32767, min(32767, Int(32767 * v)))
        return invert ? -n : n
    }

    private func read(_ g: GCExtendedGamepad) {
        let d = UserDefaults.standard
        let match = d.bool(forKey: Defaults.matchLabels)
        let dz = d.double(forKey: Defaults.deadzone)
        var s = PadState()

        // Default is positional: the 3DS diamond (A east, B south, X north, Y west).
        // "Match labels" keeps the printed letters instead (A=A, B=B ...).
        if match {
            s.set(.a, g.buttonA.isPressed); s.set(.b, g.buttonB.isPressed)
            s.set(.x, g.buttonX.isPressed); s.set(.y, g.buttonY.isPressed)
        } else {
            s.set(.a, g.buttonB.isPressed); s.set(.b, g.buttonA.isPressed)
            s.set(.x, g.buttonY.isPressed); s.set(.y, g.buttonX.isPressed)
        }
        s.set(.l, g.leftShoulder.isPressed)
        s.set(.r, g.rightShoulder.isPressed)
        s.set(.zl, g.leftTrigger.isPressed)
        s.set(.zr, g.rightTrigger.isPressed)
        s.set(.start, g.buttonMenu.isPressed)
        s.set(.select, g.buttonOptions?.isPressed ?? false)
        s.set(.l3, (g.leftThumbstickButton?.isPressed ?? false) || (g.buttonHome?.isPressed ?? false))
        s.set(.r3, g.rightThumbstickButton?.isPressed ?? false)
        s.set(.dLeft, g.dpad.left.isPressed)
        s.set(.dRight, g.dpad.right.isPressed)
        s.set(.dUp, g.dpad.up.isPressed)
        s.set(.dDown, g.dpad.down.isPressed)

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
