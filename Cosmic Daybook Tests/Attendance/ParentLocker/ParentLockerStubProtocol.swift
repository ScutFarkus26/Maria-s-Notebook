import Foundation
import Synchronization

/// A stand-in for the network in the ParentLocker HTTP tests: answers each
/// request from `respond` and records what was asked. One test at a time
/// (the suite is serialized), since `URLProtocol` is registered by class.
nonisolated final class ParentLockerStubProtocol: URLProtocol {

    enum Reply: Sendable {
        case page(status: Int, headers: [String: String], body: Data)
        /// A redirect the session's delegate is asked about.
        case redirect(to: URL, headers: [String: String])
    }

    struct Seen: Sendable {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data?
    }

    private struct State {
        var respond: (@Sendable (URLRequest) -> Reply)?
        var seen: [Seen] = []
    }

    private static let state = Mutex(State())

    static func reset(_ respond: @escaping @Sendable (URLRequest) -> Reply) {
        state.withLock { $0 = State(respond: respond) }
    }

    static var seen: [Seen] { state.withLock { $0.seen } }

    /// An ephemeral configuration that sends everything here.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ParentLockerStubProtocol.self]
        return configuration
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = request
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let reply = Self.state.withLock { state -> Reply? in
            guard let url = request.url else { return nil }
            state.seen.append(Seen(
                url: url, method: request.httpMethod ?? "GET",
                headers: request.allHTTPHeaderFields ?? [:], body: body
            ))
            return state.respond?(request)
        }
        guard let url = request.url, let reply else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        switch reply {
        case .page(let status, let headers, let body):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
            if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let target, let headers):
            var fields = headers
            fields["Location"] = target.absoluteString
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: fields)
            if let response {
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
