import SwiftUI

struct ContentView: View {
    @EnvironmentObject var input: InputManager
    @AppStorage(Defaults.ip) private var ip = ""
    @AppStorage(Defaults.autoconnect) private var autoconnect = false
    @AppStorage(Defaults.matchLabels) private var matchLabels = false
    @AppStorage(Defaults.invertCX) private var invertCX = false
    @AppStorage(Defaults.invertCY) private var invertCY = false
    @AppStorage(Defaults.deadzone) private var deadzone = 0.08
    @State private var blackout = false
    @State private var savedBrightness: CGFloat = 1

    var body: some View {
        ZStack {
            Form {
                Section("3DS") {
                    TextField("3DS IP address", text: $ip)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.system(.body, design: .monospaced))
                    Button(input.connected ? "Disconnect" : "Connect") {
                        input.connected ? input.disconnect() : input.connect()
                    }
                    Toggle("Auto-connect on launch", isOn: $autoconnect)
                    HStack { Text("Status"); Spacer(); Text(input.status).foregroundColor(.secondary) }
                    HStack { Text("Controller"); Spacer(); Text(input.controllerName).foregroundColor(.secondary) }
                }

                Section("Live input") {
                    Text(readoutText)
                        .font(.system(.footnote, design: .monospaced))
                }

                Section("Touch screen") {
                    TouchPad().frame(height: 180)
                }

                Section("Settings") {
                    Toggle("Match button labels (A=A, B=B)", isOn: $matchLabels)
                    Toggle("Invert C-Stick X", isOn: $invertCX)
                    Toggle("Invert C-Stick Y", isOn: $invertCY)
                    VStack(alignment: .leading) {
                        Text("Stick deadzone: \(Int(deadzone * 100))%")
                        Slider(value: $deadzone, in: 0.0...0.4, step: 0.01)
                    }
                    Button("Black screen (save battery)") {
                        savedBrightness = UIScreen.main.brightness
                        UIScreen.main.brightness = 0.0
                        blackout = true
                    }
                }
            }

            if blackout {
                Color.black.ignoresSafeArea()
                    .onTapGesture {
                        UIScreen.main.brightness = savedBrightness
                        blackout = false
                    }
            }
        }
    }

    private var readoutText: String {
        let s = input.readout
        let held = Key.allCases.filter { s.isDown($0) && $0 != .touch }.map(\.label).joined(separator: " | ")
        func pct(_ v: Int) -> String { String(format: "%.1f%%", Double(v) / 327.67) }
        let btn = held.isEmpty ? "-" : held
        let touchText = s.touch.map { t in "\(t.x),\(t.y)" } ?? "-"
        return """
        BTN: \(btn)

        CPAD  X \(pct(s.cpadX))  Y \(pct(s.cpadY))
        CSTK  X \(pct(s.cstickX))  Y \(pct(s.cstickY))
        TOUCH \(touchText)
        """
    }
}

/// 4:3 touch area that maps to the 3DS bottom screen.
struct TouchPad: View {
    @EnvironmentObject var input: InputManager

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height * 4 / 3)
            let size = CGSize(width: side, height: side * 3 / 4)
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.25))
                Text("Touch = 3DS bottom screen").font(.caption).foregroundColor(.secondary)
            }
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let originX = (geo.size.width - size.width) / 2
                        input.setTouch(nx: Double((v.location.x - originX) / size.width),
                                       ny: Double(v.location.y / size.height))
                    }
                    .onEnded { _ in input.setTouch(nx: nil, ny: nil) }
            )
        }
    }
}
