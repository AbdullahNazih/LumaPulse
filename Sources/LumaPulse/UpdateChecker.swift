import Foundation
import SwiftUI

struct ReleaseVersion: Comparable, Equatable {
    let parts: [Int]
    let candidate: Int?
    init?(_ text: String) {
        let text = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let pieces = text.components(separatedBy: "-rc.")
        guard pieces.count <= 2 else { return nil }
        let parts = pieces[0].split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }), let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
        self.parts = [major, minor, patch]
        if pieces.count == 2 { guard let candidate = Int(pieces[1]), candidate > 0 else { return nil }; self.candidate = candidate } else { candidate = nil }
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.parts != rhs.parts { return lhs.parts.lexicographicallyPrecedes(rhs.parts) }
        if let left = lhs.candidate, let right = rhs.candidate { return left < right }
        return lhs.candidate != nil && rhs.candidate == nil
    }
}

struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: String
    let draft: Bool
    let prerelease: Bool
    var trustedURL: URL? {
        guard let version = ReleaseVersion(tag_name), version.candidate == nil, !draft, !prerelease,
              let url = URL(string: html_url), url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil, url.port == nil,
              url.path == "/AbdullahNazih/LumaPulse/releases/tag/\(tag_name)", url.query == nil, url.fragment == nil else { return nil }
        return url
    }
}

@MainActor final class UpdateChecker: ObservableObject {
    @Published var enabled = UserDefaults.standard.object(forKey: "automaticUpdateChecks") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "automaticUpdateChecks")
            if started { schedule() }
        }
    }
    @Published var status = "Checks GitHub for new stable releases"
    @Published var release: GitHubRelease?
    @Published var checking = false
    var onAvailable: ((GitHubRelease) -> Void)?
    private var timer: Timer?
    private var started = false
    private var stopped = false
    private var lastCheck = Date.distantPast
    let currentVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0") + (Bundle.main.object(forInfoDictionaryKey: "LumaPulseReleaseSuffix") as? String ?? "-rc.1")
    func start() {
        started = true
        schedule()
    }
    func stop() {
        stopped = true
        timer?.invalidate()
        timer = nil
    }
    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard enabled, !stopped else { return }
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 21_600, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let self, self.enabled else { return }; await self.check() }
        }
        timer?.tolerance = 600
    }
    func check(manual: Bool = false) async {
        guard !stopped, !checking, manual || Date().timeIntervalSince(lastCheck) > 21_000 else { return }
        checking = true; status = "Checking GitHub…"
        defer { checking = false; lastCheck = Date() }
        do {
            let (data, response) = try await LimitedHTTP.shared.get(URL(string: "https://api.github.com/repos/AbdullahNazih/LumaPulse/releases/latest")!, limit: 262_144, headers: ["Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"])
            guard !stopped else { return }
            if response.statusCode == 404 { status = "No stable release published yet"; return }
            guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
            let found = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard found.trustedURL != nil, let incoming = ReleaseVersion(found.tag_name), let current = ReleaseVersion(currentVersion) else { throw URLError(.cannotParseResponse) }
            if incoming > current {
                release = found; status = "Update available: \(found.tag_name)"
                if UserDefaults.standard.string(forKey: "lastNotifiedRelease") != found.tag_name {
                    UserDefaults.standard.set(found.tag_name, forKey: "lastNotifiedRelease"); onAvailable?(found)
                }
            } else { release = nil; status = "You have the latest stable release" }
        } catch { status = "Update check unavailable · try again later" }
    }
}

struct UpdateSettings: View {
    @ObservedObject var checker: UpdateChecker
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("APP UPDATES").font(.system(size: 10, weight: .bold)).tracking(1.5)
            Toggle("Notify me about new versions", isOn: $checker.enabled)
            Text("Checks the official GitHub repository at launch and every six hours. Updates are never installed automatically.").font(.system(size: 11)).foregroundColor(.secondary)
            HStack {
                Button("Check for updates") { Task { await checker.check(manual: true) } }.disabled(checker.checking)
                if let url = checker.release?.trustedURL { Link("View release", destination: url) }
            }.buttonStyle(.bordered)
            Text(checker.status).font(.system(size: 10)).foregroundColor(.secondary)
        }
    }
}
