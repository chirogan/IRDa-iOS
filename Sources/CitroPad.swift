import Foundation

/// 3DS key bits. Order matches the original IRDa `CitroPad.Keys` enum.
enum Key: Int, CaseIterable {
    case a = 0, b, select, start, dRight, dLeft, dUp, dDown, r, l, x, y, l3, r3, zl, zr, touch

    var label: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        case .select: return "SELECT"
        case .start: return "START"
        case .dRight: return "DRIGHT"
        case .dLeft: return "DLEFT"
        case .dUp: return "DUP"
        case .dDown: return "DDOWN"
        case .r: return "R"
        case .l: return "L"
        case .x: return "X"
        case .y: return "Y"
        case .l3: return "HOME"
        case .r3: return "POWER"
        case .zl: return "ZL"
        case .zr: return "ZR"
        case .touch: return "TOUCH"
        }
    }
}

/// Snapshot of everything that goes into one packet.
/// Stick axes are -32767...32767 with +Y = up. Touch is raw 12-bit (0...4095) per axis.
struct PadState: Equatable {
    var held: Int = 0
    var cpadX = 0, cpadY = 0
    var cstickX = 0, cstickY = 0
    var touch: (x: Int, y: Int)? = nil

    static func == (a: PadState, b: PadState) -> Bool {
        a.held == b.held && a.cpadX == b.cpadX && a.cpadY == b.cpadY
            && a.cstickX == b.cstickX && a.cstickY == b.cstickY
            && a.touch?.x == b.touch?.x && a.touch?.y == b.touch?.y
    }

    mutating func set(_ k: Key, _ down: Bool) {
        if down { held |= 1 << k.rawValue } else { held &= ~(1 << k.rawValue) }
    }
    func isDown(_ k: Key) -> Bool { held & (1 << k.rawValue) != 0 }
}

/// Direct port of `CitroPad.Pack()` from the original Android app (20-byte UDP payload).
enum Packet {
    static let size = 20
    static let port: UInt16 = 4950
    private static let sqrt1_2 = Double(Float(0.5).squareRoot())  // original uses (float)sqrt(0.5)

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { max(min(v, hi), lo) }
    private static func clampd(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(min(v, hi), lo) }

    static func pack(_ s: PadState) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: size)

        let k = ~s.held & 4095
        p[0] = UInt8(k & 0xFF)
        p[1] = UInt8((k >> 8) & 0xF)
        p[2] = 0
        p[3] = 0

        if let t = s.touch {
            let tp = ((t.x & 0xFFF) | ((t.y & 0xFFF) << 12)) & 0xFFFFFF
            p[4] = UInt8(tp & 0xFF)
            p[5] = UInt8((tp >> 8) & 0xFF)
            p[6] = UInt8((tp >> 16) & 0xFF)
            p[7] = 1
        } else {
            p[7] = 2
        }

        if s.cpadX == 0 && s.cpadY == 0 {
            p[8] = 0xFF; p[9] = 0xF8; p[10] = 0x7F
        } else {
            let cx = (clamp(s.cpadX >> 4, -2048, 2047) + 2048) & 4095
            let cy = (clamp(s.cpadY >> 4, -2048, 2047) + 2048) & 4095
            let cp = (cx | (cy << 12)) & 0xFFFFFF
            p[8] = UInt8(cp & 0xFF)
            p[9] = UInt8((cp >> 8) & 0xFF)
            p[10] = UInt8((cp >> 16) & 0xFF)
        }

        p[11] = 0
        p[12] = 0x81
        p[13] = (s.isDown(.zr) ? 2 : 0) | (s.isDown(.zl) ? 4 : 0)

        if s.cstickX == 0 && s.cstickY == 0 {
            p[14] = 0x80; p[15] = 0x80
        } else {
            let ox = clampd(Double(Float(s.cstickX) / 32767.0), -1, 1)
            let oy = clampd(Double(Float(s.cstickY) / 32767.0), -1, 1)
            p[15] = UInt8(truncatingIfNeeded: Int(clampd((oy + ox) * sqrt1_2 * 127.0, -127, 127) + 128.0))
            p[14] = UInt8(truncatingIfNeeded: Int(clampd((oy - ox) * sqrt1_2 * 127.0, -127, 127) + 128.0))
        }

        p[16] = (s.isDown(.r3) ? 2 : 0) | (s.isDown(.l3) ? 1 : 0)
        return p
    }
}
