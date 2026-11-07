import Foundation
import Security
import SwiftUI

enum TradingProvider: String, CaseIterable, Identifiable {
    case benzinga, tradingEconomics
    var id: String { rawValue }
    var name: String { self == .benzinga ? "Benzinga" : "Trading Economics" }
    var keyHint: String { self == .benzinga ? "Streaming API token" : "API key:secret" }
    var detail: String { self == .benzinga ? "Stock and crypto news stream" : "Live economic releases · actual vs forecast" }
    func url(key: String) -> URL {
        var components = URLComponents(string: self == .benzinga ? "wss://api.benzinga.com/api/v1/news/stream" : "wss://stream.tradingeconomics.com/")!
        components.queryItems = [URLQueryItem(name: self == .benzinga ? "token" : "client", value: key)]
        return components.url!
    }
}

enum ProviderKeychain {
    private static let service = "com.anazih.lumapulse.providers"
    static func read(_ provider: TradingProvider) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: provider.rawValue, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String, provider: TradingProvider) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: provider.rawValue]
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }
}

struct ProviderEvent {
    var story: Story?
    var deletedID: String?
    var alert = false
}

enum ProviderDecoder {
    static func date(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let result = iso.date(from: text) { return result }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = iso.date(from: text) { return result }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let result = formatter.date(from: text) { return result }
        }
        return nil
    }
    static func text(_ value: Any?) -> String { value.map { String(describing: $0) } ?? "" }
    static func fresh(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) >= -5 && now.timeIntervalSince(date) <= 300
    }
    static func decode(_ data: Data, provider: TradingProvider, now: Date = Date()) throws -> [ProviderEvent] {
        guard data.count <= 262_144 else { throw URLError(.dataLengthExceedsMaximum) }
        let object = try JSONSerialization.jsonObject(with: data)
        let rows = (object as? [[String: Any]]) ?? (object as? [String: Any]).map { [$0] } ?? []
        return rows.prefix(100).compactMap { row in
            if provider == .benzinga {
                guard let envelope = row["data"] as? [String: Any], let action = envelope["action"] as? String else { return nil }
                let articleID = "benzinga:" + text(envelope["id"])
                guard !text(envelope["id"]).isEmpty, text(envelope["id"]) != "<null>" else { return nil }
                if action.lowercased() == "deleted" { return ProviderEvent(deletedID: articleID) }
                guard ["created", "updated"].contains(action.lowercased()) else { return nil }
                guard let content = envelope["content"] as? [String: Any], let title = content["title"] as? String, !title.isEmpty,
                      let link = content["url"] as? String, let url = URL(string: link), NetworkPolicy.https(url, hosts: ["benzinga.com"]) else { return nil }
                let source = FeedSource(id: provider.rawValue, name: provider.name, detail: "", url: "", topics: [])
                let summary = String((content["teaser"] as? String ?? "").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).prefix(2000))
                var topics = MarketRules.topics(title: title, summary: summary, source: source)
                if !(content["stocks"] as? [[String: Any]] ?? []).isEmpty || topics.isEmpty { topics.insert(.stocks) }
                let published = date(content["created"] as? String ?? envelope["timestamp"] as? String ?? "")
                let story = Story(title: String(title.prefix(500)), summary: summary, source: provider.name, date: published, link: link, topics: topics, sourceID: provider.rawValue, kind: MarketRules.kind(title, source: source), providerArticleID: String(articleID.prefix(128)))
                return ProviderEvent(story: story, alert: action.lowercased() == "created" && fresh(published, now: now) && story.kind == "News" && (story.driver != nil || MarketRules.matches(title, #"\bbreaking\b"#)))
            }
            guard row["topic"] as? String == "calendar", let title = row["event"] as? String, !title.isEmpty else { return nil }
            let actual = text(row["actual"])
            guard !actual.isEmpty, actual.lowercased() != "null", actual != "<null>" else { return nil }
            let calendarID = text(row["calendarId"] ?? row["calendarid"])
            guard !calendarID.isEmpty, calendarID != "<null>" else { return nil }
            let country = row["country"] as? String ?? ""
            let date = date(row["date"] as? String ?? "")
            let importance = Int(text(row["importance"])) ?? 0
            let forecast = text(row["forecast"] ?? row["forecast "])
            let previous = text(row["previous"])
            let unit = row["unit"] as? String ?? ""
            func display(_ value: String) -> String {
                guard !value.isEmpty, value != "<null>", value.lowercased() != "null" else { return "—" }
                return unit.isEmpty || value.hasSuffix(unit) ? value : value + unit
            }
            let summary = "Actual: \(display(actual)) · Forecast: \(display(forecast)) · Previous: \(display(previous))"
            let story = Story(title: "\(country.isEmpty ? "" : country + ": ")\(title) — \(display(actual))", summary: summary, source: provider.name, date: date, link: "https://tradingeconomics.com/calendar", topics: [.macro], sourceID: provider.rawValue, kind: "Economic release", providerArticleID: "tradingEconomics:" + calendarID)
            return ProviderEvent(story: story, alert: importance == 3 && fresh(date, now: now))
        }
    }
}

@MainActor final class TradingAPIController: ObservableObject {
    @Published var status: [TradingProvider: String] = [:]
    @Published var connected: Set<TradingProvider> = []
    var onEvent: ((ProviderEvent) -> Void)?
    private var workers: [TradingProvider: Task<Void, Never>] = [:]
    private var sockets: [TradingProvider: URLSessionWebSocketTask] = [:]
    private let session = URLSession(configuration: NetworkPolicy.configuration, delegate: SameOriginRedirectDelegate(), delegateQueue: nil)
    func resumeConfigured() {
        for provider in TradingProvider.allCases where UserDefaults.standard.bool(forKey: "providerEnabled." + provider.rawValue) {
            guard workers[provider] == nil else { continue }
            guard let key = ProviderKeychain.read(provider) else { status[provider] = "Enter your key to connect"; continue }
            start(provider, key: key)
        }
    }
    func connect(_ provider: TradingProvider, key raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 512, !key.contains(where: \.isWhitespace) else { status[provider] = "Enter valid API credentials (no spaces)"; return }
        guard ProviderKeychain.save(key, provider: provider) else { status[provider] = "Could not save credentials in macOS Keychain"; return }
        UserDefaults.standard.set(true, forKey: "providerEnabled." + provider.rawValue)
        start(provider, key: key)
    }
    func disconnect(_ provider: TradingProvider) {
        UserDefaults.standard.set(false, forKey: "providerEnabled." + provider.rawValue)
        stop(provider); status[provider] = "Disconnected · key saved in Keychain"
    }
    func reconnect(_ provider: TradingProvider) {
        guard let key = ProviderKeychain.read(provider) else { status[provider] = "Enter and save your API credentials"; return }
        UserDefaults.standard.set(true, forKey: "providerEnabled." + provider.rawValue)
        start(provider, key: key)
    }
    func stopAll() { for provider in TradingProvider.allCases { stop(provider); status[provider] = "Paused" } }
    private func stop(_ provider: TradingProvider) {
        workers.removeValue(forKey: provider)?.cancel()
        sockets.removeValue(forKey: provider)?.cancel(with: .goingAway, reason: nil)
        connected.remove(provider)
    }
    private func start(_ provider: TradingProvider, key: String) {
        stop(provider)
        workers[provider] = Task { [weak self] in
            guard let self else { return }
            var backoff: UInt64 = 2
            while !Task.isCancelled {
                self.status[provider] = "Connecting to stream…"
                let socket = self.session.webSocketTask(with: provider.url(key: key))
                socket.maximumMessageSize = 262_144
                self.sockets[provider] = socket
                socket.resume()
                var heartbeat: Task<Void, Never>?
                defer { heartbeat?.cancel(); socket.cancel(with: .goingAway, reason: nil) }
                do {
                    try await self.ping(socket)
                    if Task.isCancelled { return }
                    if provider == .tradingEconomics { try await socket.send(.string("{\"topic\":\"subscribe\",\"to\":\"calendar\"}")) }
                    self.connected.insert(provider)
                    self.status[provider] = "Connected · waiting for live events"
                    heartbeat = Task {
                        while !Task.isCancelled {
                            do { try await Task.sleep(nanoseconds: 30_000_000_000); try await self.ping(socket) }
                            catch { if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }; return }
                        }
                    }
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        guard !Task.isCancelled else { return }
                        let data: Data
                        switch message { case .string(let value): data = Data(value.utf8); case .data(let value): data = value; @unknown default: continue }
                        if let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let error = row["error"], !(error is NSNull), String(describing: error) != "false" {
                            self.status[provider] = "Stream rejected · check key and subscription access"
                            heartbeat?.cancel(); socket.cancel(with: .normalClosure, reason: nil); self.connected.remove(provider)
                            return
                        }
                        let events = (try? ProviderDecoder.decode(data, provider: provider)) ?? []
                        for event in events { self.onEvent?(event) }
                        if !events.isEmpty { self.status[provider] = "Receiving live events"; backoff = 2 }
                    }
                } catch {
                    if !Task.isCancelled { self.status[provider] = "Connection unavailable · retry in \(backoff)s; check stream entitlement" }
                }
                heartbeat?.cancel(); socket.cancel(with: .goingAway, reason: nil)
                guard !Task.isCancelled else { return }
                self.connected.remove(provider)
                do { try await Task.sleep(nanoseconds: backoff * 1_000_000_000) } catch { return }
                backoff = min(60, backoff * 2)
            }
        }
    }
    private func ping(_ socket: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in if let error { continuation.resume(throwing: error) } else { continuation.resume() } }
        }
    }
}

struct TradingAPISettings: View {
    @ObservedObject var controller: TradingAPIController
    let connect: (TradingProvider, String) -> Void
    let reconnect: (TradingProvider) -> Void
    @State private var keys: [TradingProvider: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RECOMMENDED LIVE PROVIDERS").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundColor(Color(red: 0.27, green: 0.87, blue: 0.72))
            ForEach(TradingProvider.allCases) { provider in
                VStack(alignment: .leading, spacing: 7) {
                    Text(provider.name).fontWeight(.semibold)
                    Text(provider.detail).font(.system(size: 11)).foregroundColor(.secondary)
                    SecureField(provider.keyHint, text: Binding(get: { keys[provider] ?? "" }, set: { keys[provider] = $0 })).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save & connect") { connect(provider, keys[provider] ?? ""); keys[provider] = "" }
                        Button("Reconnect") { reconnect(provider) }
                        Button("Disconnect") { controller.disconnect(provider) }
                    }.buttonStyle(.bordered).font(.system(size: 11))
                    Text(controller.status[provider] ?? "Not connected · streaming API access required").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            Text("Credentials are stored in macOS Keychain. Connect uses your existing API subscription. RSS remains available below.").font(.system(size: 11)).foregroundColor(.secondary).lineSpacing(4)
        }
    }
}
