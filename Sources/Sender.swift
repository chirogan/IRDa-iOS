import Foundation
import Network

/// Sends the current pad state to the 3DS every 15 ms over UDP (port 4950), like the original.
final class Sender {
    private let queue = DispatchQueue(label: "irda.sender", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var connection: NWConnection?
    private let lock = NSLock()
    private var state = PadState()

    var onStatus: ((String) -> Void)?

    var isRunning: Bool { queue.sync { timer != nil } }

    func update(_ s: PadState) {
        lock.lock(); state = s; lock.unlock()
    }

    func start(host: String) {
        stop()
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let port = NWEndpoint.Port(rawValue: Packet.port) else {
            onStatus?("Enter the 3DS IP address first")
            return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: port, using: .udp)
        conn.stateUpdateHandler = { [weak self] st in
            switch st {
            case .ready: self?.onStatus?("Sending to \(host):\(Packet.port)")
            case .failed(let e): self?.onStatus?("Failed: \(e.localizedDescription)")
                DispatchQueue.global().async { self?.stop() }
            case .waiting(let e): self?.onStatus?("Waiting: \(e.localizedDescription)")
            default: break
            }
        }
        conn.start(queue: queue)

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(15), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); let s = self.state; self.lock.unlock()
            conn.send(content: Data(Packet.pack(s)), completion: .contentProcessed { _ in })
        }
        queue.sync { connection = conn; timer = t }
        t.resume()
        onStatus?("Connecting to \(host)…")
    }

    func stop() {
        queue.sync {
            timer?.cancel(); timer = nil
            connection?.cancel(); connection = nil
        }
        onStatus?("Disconnected")
    }
}
