import Foundation
import Observation

/// One deadline suggested by the architect server. The owner decides whether it
/// becomes a gate; nothing is added automatically.
struct SuggestedGate: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var date: String
    var source: String
    var domain: String
    var estimated: Bool?
    var detail: String?
}

private struct SuggestedGatesResponse: Codable {
    var gates: [SuggestedGate]
}

/// Talks to the architect server on the private network. Optional: with no URL
/// or token set, or the server unreachable, the app behaves exactly the same.
@MainActor
@Observable
final class ArchitectClient {
    static let shared = ArchitectClient()

    enum Key {
        static let url = "architect.url"
        static let token = "architect.token"
        static let lastSync = "architect.lastSync"
    }

    var lastError: String?
    var lastSync: Date?
    var syncing = false

    private let defaults = UserDefaults.standard
    private var pending: Task<Void, Never>?

    private init() {
        let t = defaults.double(forKey: Key.lastSync)
        lastSync = t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    var urlString: String {
        get { defaults.string(forKey: Key.url) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.url) }
    }

    var token: String {
        get { defaults.string(forKey: Key.token) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.token) }
    }

    var isConfigured: Bool { baseURL != nil && !token.isEmpty }

    private var baseURL: URL? {
        var s = urlString
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest? {
        guard let base = baseURL, !token.isEmpty else { return nil }
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = method
        r.timeoutInterval = 10
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    /// Fire-and-forget snapshot upload. Coalesces bursts (a gate plus foreground).
    func syncSoon(_ store: SystemStore) {
        guard isConfigured, !DemoMode.isOn else { return }
        guard let body = try? JSONSerialization.data(withJSONObject: store.v3Snapshot()),
              let req = request("sync", method: "POST", body: body) else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.send(req)
        }
    }

    private func send(_ req: URLRequest) async {
        syncing = true
        defer { syncing = false }
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                lastError = code == 401 ? "Token rejected (401)" : "Server returned \(code)"
                return
            }
            lastError = nil
            let now = Date.now
            lastSync = now
            defaults.set(now.timeIntervalSince1970, forKey: Key.lastSync)
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }

    enum FetchError: LocalizedError {
        case notConfigured, status(Int)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Set the architect URL and token in Settings."
            case .status(let c): return c == 401 ? "Token rejected (401)." : "Server returned \(c)."
            }
        }
    }

    func fetchSuggestedGates() async throws -> [SuggestedGate] {
        guard let req = request("suggested-gates") else { throw FetchError.notConfigured }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw FetchError.status(code) }
        return try JSONDecoder().decode(SuggestedGatesResponse.self, from: data).gates
    }

    /// Health check for Settings: true when the token is accepted.
    func test() async -> String {
        guard let req = request("state") else { return FetchError.notConfigured.localizedDescription }
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(code) ? "Connected." : (FetchError.status(code).errorDescription ?? "Error")
        } catch {
            return (error as NSError).localizedDescription
        }
    }
}
