import Foundation
import Network

/// A tiny HTTP listener on 127.0.0.1 only. The hook forwarder POSTs one JSON event per request.
final class Server {
    private let listener: NWListener
    private let onEvent: (Data) -> Void
    private let limit = 8_000_000

    init?(port: UInt16, onEvent: @escaping (Data) -> Void, onFail: @escaping (String) -> Void) {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params) else { return nil }
        self.listener = l
        self.onEvent = onEvent
        l.newConnectionHandler = { [weak self] c in
            c.start(queue: .main)
            self?.read(c, Data())
        }
        l.stateUpdateHandler = { state in
            if case .failed(let e) = state { onFail("\(e)") }
        }
        l.start(queue: .main)
    }

    private func read(_ c: NWConnection, _ buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer
            if let d = data { buf.append(d) }
            if buf.count > self.limit { c.cancel(); return }
            if let r = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[..<r.lowerBound], as: UTF8.self)
                let lines = head.components(separatedBy: "\r\n")
                let len = lines.first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
                let body = buf[r.upperBound...]
                if body.count >= len {
                    if (lines.first ?? "").hasPrefix("POST /event") { self.onEvent(Data(body.prefix(len))) }
                    let resp = "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
                    c.send(content: Data(resp.utf8), completion: .contentProcessed { _ in c.cancel() })
                    return
                }
            }
            if done || err != nil { c.cancel(); return }
            self.read(c, buf)
        }
    }
}
