import Foundation
import LegadoCore

extension WebSocketSearchOptions {
    static func saved(read: (String) -> Any? = { UserDefaults.standard.object(forKey: $0) }) -> Self {
        .init(scope: read("searchScope") as? String ?? "", threadCount: read("threadCount") as? Int ?? 32,
              precisionSearch: read("precisionSearch") as? Bool ?? false)
    }
}

@MainActor
final class WebSocketSession {
    private let path: String
    private let routes: WebSocketRoutes
    private let send: (Data, @escaping (Bool) -> Void) -> Void
    private let end: () -> Void
    private var decoder = WebSocketFrameDecoder()
    private var closing = WebSocketCloseState()
    private var requestReceived = false
    private var stopped = false
    private var protocolFailed = false
    var shouldReceive: Bool { !stopped && !closing.received && !protocolFailed }
    private var work: Task<Void, Never>?
    private var authDeadline: DispatchWorkItem?
    private var heartbeat: DispatchWorkItem?
    private var closeDeadline: DispatchWorkItem?

    init(path: String, routes: WebSocketRoutes, send: @escaping (Data, @escaping (Bool) -> Void) -> Void,
         end: @escaping () -> Void) {
        self.path = path; self.routes = routes; self.send = send; self.end = end
        authDeadline = schedule(after: 10) { $0.authenticationTimedOut() }
    }

    func receive(_ bytes: Data) {
        guard shouldReceive else { return }
        do {
            for frame in try decoder.append(bytes) {
                guard !stopped else { return }
                switch frame.opcode {
                case .close:
                    work?.cancel(); authDeadline?.cancel(); heartbeat?.cancel()
                    if let reply = closing.receive(frame) {
                        send(reply.encoded()) { [weak self] _ in self?.finish() }
                    } else { finish() }
                    return
                case .ping:
                    if !closing.sent { transmit(.init(opcode: .pong, payload: frame.payload)) }
                case .pong: break
                case .text, .binary:
                    guard !requestReceived, !closing.sent else { continue }
                    requestReceived = true
                    authDeadline?.cancel()
                    scheduleHeartbeat()
                    let events = routes.events(path: path, message: frame.payload)
                    work = Task { [weak self] in
                        for await event in events {
                            guard !Task.isCancelled, let self, !self.stopped, !self.closing.sent else { break }
                            switch event {
                            case .text(let text):
                                let success = await self.transmitText(text)
                                if !success { return }
                            case .close(let code, let reason): self.initiateClose(code: code, reason: reason)
                            }
                        }
                    }
                case .continuation: break
                }
            }
        } catch {
            protocolFailed = true
            initiateClose(code: (error as? WebSocketError)?.closeCode ?? 1002, reason: "WebSocket frame error")
        }
    }

    func authenticationTimedOut() {
        guard !requestReceived else { return }
        initiateClose(code: 1008, reason: "认证超时")
    }

    private func transmitText(_ text: String) async -> Bool {
        guard !stopped, !closing.sent else { return false }
        return await withCheckedContinuation { continuation in
            send(WebSocketFrame(opcode: .text, payload: Data(text.utf8)).encoded()) { [weak self] success in
                if !success { self?.finish() }
                continuation.resume(returning: success)
            }
        }
    }

    private func transmit(_ frame: WebSocketFrame) {
        send(frame.encoded()) { [weak self] success in if !success { self?.finish() } }
    }

    private func initiateClose(code: UInt16, reason: String) {
        guard !stopped, let frame = closing.initiate(code: code, reason: reason) else { return }
        work?.cancel(); authDeadline?.cancel(); heartbeat?.cancel()
        closeDeadline = schedule(after: 5) { $0.finish() }
        if protocolFailed {
            send(frame.encoded()) { [weak self] _ in self?.finish() }
        } else { transmit(frame) }
    }

    private func scheduleHeartbeat() {
        heartbeat = schedule(after: 30) { session in
            guard !session.stopped, !session.closing.sent else { return }
            session.transmit(.init(opcode: .ping, payload: Data("ping".utf8)))
            session.scheduleHeartbeat()
        }
    }

    private func schedule(after seconds: Double, action: @escaping (WebSocketSession) -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return item
    }

    private func finish() {
        guard !stopped else { return }
        stop(); end()
    }

    func stop() {
        stopped = true
        work?.cancel(); work = nil
        authDeadline?.cancel(); authDeadline = nil
        heartbeat?.cancel(); heartbeat = nil
        closeDeadline?.cancel(); closeDeadline = nil
    }
}
