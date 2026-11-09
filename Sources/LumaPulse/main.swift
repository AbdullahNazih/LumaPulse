import AppKit
import Combine
import SwiftUI
import Foundation

struct Story: Identifiable, Sendable {
    var id: String { providerArticleID ?? (link.isEmpty ? title : link) }
    let title: String
    let summary: String
    let source: String
    let date: Date?
    let link: String
    var topics: Set<MarketTopic> = []
    var sourceID: String = ""
    var kind: String = "News"
    var providerArticleID: String? = nil
    var driver: String? { MarketRules.driver(title) }
}

enum AlertTiming {
    static func clamp(_ seconds: Int) -> Int { min(1800, max(1, seconds)) }
    static func duration(preset: Int, custom: Int) -> Int {
        [5, 10, 30].contains(preset) ? preset : clamp(custom)
    }
}

final class FeedParser: NSObject, XMLParserDelegate {
    var stories: [Story] = []
    var itemCount = 0
    private let source: FeedSource
    init(source: FeedSource = .world) { self.source = source }
    private var inside = false
    private var field = ""
    private var values: [String: String] = [:]
    private let formatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"; return f
    }()
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "item" { inside = true; values = [:] }
        field = name
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inside { values[field, default: ""] += string }
    }
    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        if let text = String(data: data, encoding: .utf8) { self.parser(parser, foundCharacters: text) }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "item" {
            itemCount += 1
            let title = String(values["title", default: ""].trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
            let link = values["link", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, NetworkPolicy.article(link, source: source), stories.count < 200 {
                let summary = String(values["description", default: ""].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).prefix(2000))
                let topics = MarketRules.topics(title: title, summary: summary, source: source)
                if !source.metalsOnly || !topics.intersection([.gold, .silver, .macro]).isEmpty {
                    stories.append(Story(title: title, summary: summary, source: source.name, date: formatter.date(from: values["pubDate", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)), link: link, topics: topics, sourceID: source.id, kind: MarketRules.kind(title, source: source)))
                }
            }
            inside = false
        }
        field = ""
    }
}

@MainActor final class NewsModel: ObservableObject {
    @Published var stories: [Story] = []
    @Published var saved: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "savedStories") ?? [])
    @Published var live = false
    @Published var loading = false
    @Published var message = "Preview stories · illustrative content"
    @Published var updated: Date?
    @Published var filter = "Headlines"
    @Published var query = ""
    @Published var selectedTopic = "All"
    @Published var driversOnly = false
    @Published private(set) var enabledSources: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "enabledNewsSources") ?? Array(FeedSource.tradingDefaults))
    @Published var sourceStatus: [String: String] = [:]
    let api = TradingAPIController()
    let updates = UpdateChecker()
    @Published var automaticMarketAlerts = UserDefaults.standard.object(forKey: "automaticMarketAlerts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automaticMarketAlerts, forKey: "automaticMarketAlerts") }
    }
    private var alertedIDs: Set<String> = []
    var alertIsDemo: Bool { activeAlert?.link == "simulation:breaking" }
    func connectAPI(_ provider: TradingProvider, key: String) {
        if !live { setMode(true) }
        api.connect(provider, key: key)
    }
    func receive(_ event: ProviderEvent) {
        guard live else { return }
        if let deletedID = event.deletedID {
            stories.removeAll { $0.id == deletedID }
            if activeAlert?.id == deletedID { dismissAlert() }
        }
        guard let story = event.story else { return }
        stories.removeAll { $0.id == story.id }
        stories.append(story)
        stories.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        stories = Array(stories.prefix(300))
        if let active = activeAlert, active.id == story.id, active.title != story.title || active.summary != story.summary {
            activeAlert = story
            onAlert?(story, TimeInterval(alertDuration))
        }
        if event.alert && automaticMarketAlerts && alertedIDs.insert(story.id).inserted {
            activeAlert = story
            onAlert?(story, TimeInterval(alertDuration))
        }
    }
    func setSource(_ id: String, enabled: Bool) {
        if enabled { enabledSources.insert(id) } else { enabledSources.remove(id) }
        UserDefaults.standard.set(Array(enabledSources), forKey: "enabledNewsSources")
        if live {
            scheduleRefresh()
            stories.removeAll { story in FeedSource.all.contains(where: { $0.id == story.sourceID }) && !enabledSources.contains(story.sourceID) }
            Task { await refresh() }
        }
    }
    @Published var animate = true
    @Published var settings = false
    @Published var showTitle = true
    @Published var activeAlert: Story?
    @Published private(set) var alertPreset = UserDefaults.standard.object(forKey: "alertPreset") as? Int ?? 10
    @Published private(set) var customDuration = AlertTiming.clamp(UserDefaults.standard.object(forKey: "customAlertDuration") as? Int ?? 60)
    var onAlert: ((Story, TimeInterval) -> Void)?
    var onUninstall: (() -> Void)?
    var onDismissAlert: (() -> Void)?
    var alertDuration: Int { AlertTiming.duration(preset: alertPreset, custom: customDuration) }
    func setAlertPreset(_ value: Int) {
        alertPreset = [5, 10, 30].contains(value) ? value : 0
        UserDefaults.standard.set(alertPreset, forKey: "alertPreset")
        restartActiveAlert()
    }
    func setCustomDuration(_ value: Int) {
        customDuration = AlertTiming.clamp(value)
        UserDefaults.standard.set(customDuration, forKey: "customAlertDuration")
        if alertPreset == 0 { restartActiveAlert() }
    }
    private func restartActiveAlert() {
        if let story = activeAlert { onAlert?(story, TimeInterval(alertDuration)) }
    }
    func dismissAlert() {
        activeAlert = nil
        onDismissAlert?()
    }
    private var timer: Timer?
    static let preview = [
        Story(title: "Stocks: earnings, company results, and the market open", summary: "PREVIEW — Enable live sources for CNBC financial-market headlines.", source: "Design preview", date: nil, link: "preview:stocks", topics: [.stocks]),
        Story(title: "Crypto: regulation, ETF flows, and exchange developments", summary: "PREVIEW — CoinDesk brings crypto reporting into your briefing.", source: "Design preview", date: nil, link: "preview:crypto", topics: [.crypto]),
        Story(title: "Gold and silver: metals news, forecasts, and macro context", summary: "PREVIEW — FXStreet headlines are filtered for precious metals and macro topics. Forecasts are labeled separately.", source: "Design preview", date: nil, link: "preview:metals", topics: [.gold, .silver]),
        Story(title: "Federal Reserve: official policy releases", summary: "PREVIEW — Follow monetary-policy announcements at the source.", source: "Design preview", date: nil, link: "preview:macro", topics: [.macro])
    ]
    init(automaticAlerts: Bool? = nil) {
        if let automaticAlerts { automaticMarketAlerts = automaticAlerts }
        stories = Self.preview
        api.onEvent = { [weak self] event in self?.receive(event) }
    }
    var refreshInterval: TimeInterval { ProcessInfo.processInfo.isLowPowerModeEnabled ? 300 : 60 }
    func scheduleRefresh() {
        timer?.invalidate()
        timer = nil
        guard live, !enabledSources.isEmpty else { return }
        let interval = refreshInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer?.tolerance = interval / 10
    }
    var visible: [Story] {
        let display = activeAlert.map { alert in [alert] + stories.filter { $0.id != alert.id } } ?? stories
        return display.filter { (filter != "Saved" || saved.contains($0.id)) && (selectedTopic == "All" || $0.topics.contains { $0.rawValue == selectedTopic }) && (!driversOnly || $0.driver != nil) && (query.isEmpty || ($0.title + " " + $0.summary + " " + $0.source).localizedCaseInsensitiveContains(query)) }
    }
    func simulateBreakingNews() {
        activeAlert = Story(title: "Central bank announces surprise interest-rate decision", summary: "SIMULATION ONLY — Fictional market-news alert. No actual announcement is being reported. Your live feed stays unchanged.", source: "LumaPulse simulation", date: Date(), link: "simulation:breaking", topics: [.stocks, .crypto, .gold, .silver, .macro])
        filter = "Headlines"; selectedTopic = "All"; query = ""; settings = false
        restartActiveAlert()
    }
    func toggleSaved(_ story: Story) {
        if saved.contains(story.id) { saved.remove(story.id) } else { saved.insert(story.id) }
        UserDefaults.standard.set(Array(saved), forKey: "savedStories")
        objectWillChange.send()
    }
    func setMode(_ enabled: Bool) {
        live = enabled
        scheduleRefresh()
        if enabled { stories = []; api.resumeConfigured(); Task { await refresh() } }
        else { api.stopAll(); dismissAlert(); stories = Self.preview; updated = nil; message = "Preview stories · illustrative content" }
    }
    func refresh() async {
        guard live, !loading else { return }
        let requested = enabledSources
        let sources = FeedSource.all.filter { requested.contains($0.id) }
        guard !sources.isEmpty else { stories.removeAll { !$0.sourceID.hasPrefix("benzinga") && $0.sourceID != "tradingEconomics" }; message = "RSS off · live provider status in Preferences"; return }
        loading = true
        message = "Refreshing market sources…"
        defer {
            loading = false
            if live && enabledSources != requested { Task { await refresh() } }
        }
        let results = await withTaskGroup(of: FeedResult.self, returning: [FeedResult].self) { group in
            for source in sources { group.addTask { await MarketFeedLoader.fetch(source) } }
            var results: [FeedResult] = []
            for await result in group { results.append(result) }
            return results
        }
        guard live, enabledSources == requested else { return }
        let failed = Set(results.filter { $0.stories == nil }.map(\.sourceID))
        for result in results {
            sourceStatus[result.sourceID] = result.stories.map { "Loaded · \($0.count) headlines" } ?? "Unavailable · previous headlines retained"
        }
        var seen: Set<String> = []
        let retained = stories.filter { failed.contains($0.sourceID) || $0.sourceID == "benzinga" || $0.sourceID == "tradingEconomics" }
        stories = (results.flatMap { $0.stories ?? [] } + retained).sorted {
            if $0.date == $1.date { return $0.title < $1.title }
            return ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
        }.filter { seen.insert($0.id).inserted }
        if failed.count < sources.count { updated = Date() }
        let names = sources.filter { failed.contains($0.id) }.map(\.name).joined(separator: ", ")
        message = failed.isEmpty ? "\(sources.count) sources · RSS active" : "Unavailable: \(names) · automatic retry"
    }
}

struct PulseView: View {
    @ObservedObject var model: NewsModel
    private var accent: Color { model.activeAlert == nil ? Color(red: 0.27, green: 0.87, blue: 0.72) : AlertPalette.rose }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").font(.system(size: 25, weight: .medium)).foregroundColor(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("LumaPulse").font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("MARKETS, AT A GLANCE").font(.system(size: 8, weight: .bold)).tracking(1.9).foregroundColor(.secondary)
                }
                Spacer()
                Text(model.alertIsDemo ? "SIMULATION" : (model.activeAlert != nil ? "ALERT" : (model.live ? "LIVE NEWS" : "DRAFT 01"))).font(.system(size: 9, weight: .bold)).tracking(1).padding(.horizontal, 9).padding(.vertical, 6).background(accent.opacity(0.12)).foregroundColor(accent).clipShape(Capsule())
                Button { model.settings.toggle() } label: { Image(systemName: model.settings ? "xmark" : "slider.horizontal.3") }.buttonStyle(.plain).padding(8).help("Preferences")
            }.padding(22)
            Divider().opacity(0.5)
            if model.activeAlert != nil {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.alertIsDemo ? "BREAKING NEWS · DEMO" : "MARKET ALERT").font(.system(size: 11, weight: .bold)).tracking(1)
                        Text(model.alertIsDemo ? "Fictional event for preview purposes" : model.activeAlert?.source ?? "Live provider").font(.system(size: 10))
                    }
                    Spacer()
                    Button(model.alertIsDemo ? "End demo" : "Dismiss") { model.dismissAlert() }.buttonStyle(.bordered).font(.system(size: 11))
                }.foregroundColor(accent).padding(.horizontal, 22).padding(.vertical, 12).background(accent.opacity(0.1))
            }
            if model.settings { preferences }
            else {
                HStack {
                    ForEach(["Headlines", "Saved"], id: \.self) { name in
                        Button { model.filter = name } label: {
                            Text(name).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 8)
                                .background(model.filter == name ? accent.opacity(0.16) : Color.clear).foregroundColor(model.filter == name ? accent : .secondary).clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise").rotationEffect(.degrees(model.loading ? 180 : 0)) }.buttonStyle(.plain).disabled(model.loading || !model.live).help("Refresh headlines")
                }.padding(.horizontal, 20).padding(.top, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(["All"] + MarketTopic.allCases.map(\.rawValue), id: \.self) { topic in
                            Button { model.selectedTopic = topic } label: {
                                Text(topic).font(.system(size: 11, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 7)
                                    .background(model.selectedTopic == topic ? accent.opacity(0.16) : Color.white.opacity(0.04)).foregroundColor(model.selectedTopic == topic ? accent : .secondary).clipShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 22)
                }.padding(.top, 12)
                Toggle("Market drivers only", isOn: $model.driversOnly).toggleStyle(.checkbox).font(.system(size: 11)).help("Headlines mentioning rates, economic data, earnings, regulation, or security events").frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 22).padding(.top, 10)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search headlines", text: $model.query).textFieldStyle(.plain)
                }.font(.system(size: 12)).padding(11).background(Color.white.opacity(0.045)).cornerRadius(10).padding(.horizontal, 22).padding(.top, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(model.filter == "Saved" ? "YOUR READING LIST" : "MARKET BRIEFING").font(.system(size: 9, weight: .bold)).tracking(1.7).foregroundColor(.secondary)
                            Spacer()
                            Text(Date(), format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()).font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        if model.loading && model.stories.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
                        if model.visible.isEmpty && !model.loading {
                            VStack(spacing: 12) {
                                Image(systemName: model.filter == "Saved" ? "bookmark" : "globe").font(.system(size: 30)).foregroundColor(accent)
                                Text(model.filter == "Saved" ? "A little space for later" : "No headlines to show").font(.headline)
                                Text(model.filter == "Saved" ? "Bookmark a story and find it here." : "Try another search or refresh the feed.").font(.caption).foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 45)
                        }
                        ForEach(Array(model.visible.enumerated()), id: \.element.id) { index, story in
                            storyCard(story, featured: index == 0 && model.filter == "Headlines")
                        }
                    }.padding(22)
                }
            }
            Divider().opacity(0.5)
            HStack(spacing: 7) {
                Circle().fill(model.live && model.updated != nil ? accent : Color.orange).frame(width: 5, height: 5)
                Text(model.message).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(2)
                Spacer(minLength: 2)
                Button("Test alert") { model.simulateBreakingNews() }.font(.system(size: 10)).buttonStyle(.plain).foregroundColor(accent)
                Button("Quit") { NSApp.terminate(nil) }.font(.system(size: 10)).buttonStyle(.plain).foregroundColor(.secondary)
            }.padding(.horizontal, 22).padding(.vertical, 13)
        }.frame(width: 460, height: 660).background(Color(red: 0.055, green: 0.075, blue: 0.10)).preferredColorScheme(.dark)
    }
    func storyCard(_ story: Story, featured: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(story.link == "simulation:breaking" ? "BREAKING · FICTIONAL HEADLINE" : story.source.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.3).foregroundColor(accent)
                Spacer()
                if let date = story.date { Text(date, style: .relative).font(.system(size: 9)).foregroundColor(.secondary) }
                Button { model.toggleSaved(story) } label: { Image(systemName: model.saved.contains(story.id) ? "bookmark.fill" : "bookmark").foregroundColor(model.saved.contains(story.id) ? accent : .secondary) }.buttonStyle(.plain).help(model.saved.contains(story.id) ? "Remove bookmark" : "Save story")
            }
            HStack(spacing: 6) {
                Text(([story.kind] + story.topics.map(\.rawValue).sorted()).joined(separator: " · ")).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if let driver = story.driver { Text(driver).font(.system(size: 9, weight: .semibold)).foregroundColor(.orange).lineLimit(1) }
            }
            Button {
                if let url = URL(string: story.link), url.scheme == "https" { NSWorkspace.shared.open(url) }
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    Text(story.title).font(.system(size: featured ? 24 : 16, weight: .semibold, design: .rounded)).tracking(featured ? -0.5 : 0).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading).foregroundColor(.white)
                    Text(story.summary).font(.system(size: 12)).foregroundColor(.secondary).lineSpacing(4).lineLimit(featured ? 4 : 2).multilineTextAlignment(.leading)
                    if featured { Label(story.link == "simulation:breaking" ? "Simulation only · no article to open" : (model.live ? "Read at \(story.source)" : "Preview · enable live news in preferences"), systemImage: model.live && story.link != "simulation:breaking" ? "arrow.up.right" : "sparkles").font(.system(size: 10, weight: .medium)).foregroundColor(accent).padding(.top, 4) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
        }.padding(featured ? 20 : 4).background(featured ? Color.white.opacity(0.045) : Color.clear).cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(featured ? accent.opacity(0.18) : .clear, lineWidth: 1))
    }
    var preferences: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your market briefing.").font(.system(size: 25, weight: .semibold, design: .rounded))
            UpdateSettings(checker: model.updates)
            Divider()
            TradingAPISettings(controller: model.api, connect: model.connectAPI, reconnect: { provider in
                if !model.live { model.setMode(true) }
                model.api.reconnect(provider)
            })
            Toggle("Automatic market alerts", isOn: $model.automaticMarketAlerts)
            Text("Alerts highlight fresh Benzinga market-driver news and high-importance economic releases. The newest alert replaces the previous one.").font(.system(size: 11)).foregroundColor(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("TRADING NEWS SOURCES").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundColor(accent)
                Toggle("Use live headlines", isOn: Binding(get: { model.live }, set: { model.setMode($0) }))
                ForEach(FeedSource.all) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(source.name, isOn: Binding(get: { model.enabledSources.contains(source.id) }, set: { model.setSource(source.id, enabled: $0) }))
                        Text(source.detail).font(.system(size: 11)).foregroundColor(.secondary)
                        if model.live && model.enabledSources.contains(source.id) {
                            Text(model.sourceStatus[source.id] ?? "Waiting for refresh").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }
                Text("RSS refreshes every minute, or every five minutes in Low Power Mode. Publisher delays may apply. Market-driver tags highlight headline topics; forecasts are shown as analysis.").font(.system(size: 11)).foregroundColor(.secondary).lineSpacing(4)
                Text("RSS feeds are the fallback briefing. Automatic alerts use the connected streaming providers above.").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("BREAKING NEWS DURATION").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundColor(accent)
                Picker("Show alert for", selection: Binding(get: { model.alertPreset }, set: { model.setAlertPreset($0) })) {
                    Text("5 sec").tag(5)
                    Text("10 sec").tag(10)
                    Text("30 sec").tag(30)
                    Text("Custom").tag(0)
                }.pickerStyle(.segmented)
                if model.alertPreset == 0 {
                    HStack {
                        Text("Seconds")
                        TextField("Seconds", value: Binding(get: { model.customDuration }, set: { model.setCustomDuration($0) }), format: .number).textFieldStyle(.roundedBorder).frame(width: 75)
                        Stepper("", value: Binding(get: { model.customDuration }, set: { model.setCustomDuration($0) }), in: 1...1800).labelsHidden()
                        Text("up to 1,800 (30 min)").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
                Text("The headline appears automatically in the menu bar and a banner below it. It clears after \(model.alertDuration) seconds. This preference is saved.").font(.system(size: 11)).foregroundColor(.secondary).lineSpacing(4)
                Button("Preview breaking-news notification") { model.simulateBreakingNews() }.buttonStyle(.bordered)
            }
            Divider()
            VStack(alignment: .leading, spacing: 15) {
                Text("MENU BAR").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundColor(accent)
                Toggle("Pulse during alerts", isOn: $model.animate)
                Toggle("Show LumaPulse label", isOn: $model.showTitle)
            }
            Divider()
            Text("LumaPulse \(model.updates.currentVersion)\nStocks · Crypto · Gold · Silver").font(.system(size: 12)).foregroundColor(.secondary).lineSpacing(6)
            Button("Uninstall LumaPulse…", role: .destructive) { model.onUninstall?() }.buttonStyle(.bordered)
            Button("Back to headlines") { model.settings = false }.buttonStyle(.borderedProminent).tint(accent).foregroundColor(.black)
        }.font(.system(size: 13)).padding(24).frame(maxHeight: .infinity)
        }
    }
}

struct BreakingBanner: View {
    let story: Story
    let duration: TimeInterval
    let deadline: Date
    let dismiss: () -> Void
    private let red = AlertPalette.rose
    private var isDemo: Bool { story.link == "simulation:breaking" }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, deadline.timeIntervalSince(context.date))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill").font(.system(size: 16, weight: .black))
                    Text(isDemo ? "BREAKING NEWS" : (story.kind == "App update" ? "UPDATE AVAILABLE" : (story.kind == "Economic release" ? "ECONOMIC RELEASE" : "MARKET ALERT"))).font(.system(size: 15, weight: .heavy)).tracking(1)
                    if isDemo { Text("DEMO").font(.system(size: 9, weight: .heavy)).padding(.horizontal, 6).padding(.vertical, 3).background(Color.black.opacity(0.08)).cornerRadius(4) }
                    Spacer()
                    Text(remaining >= 60 ? "\(Int(ceil(remaining / 60))) min left" : "\(Int(ceil(remaining))) sec left").font(.system(size: 10)).monospacedDigit()
                    Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).padding(4).help("Dismiss notification")
                }.foregroundColor(AlertPalette.text).padding(.horizontal, 16).padding(.vertical, 11).background(AlertPalette.rose)
                Text(story.title).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundColor(.white).lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 16).padding(.top, 12)
                HStack {
                    Text(isDemo ? "Fictional headline · preview only" : story.source).font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                    if story.kind == "App update", let url = URL(string: story.link) { Link("View release", destination: url).font(.system(size: 11, weight: .semibold)) }
                    Text("LumaPulse").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
                }.padding(.horizontal, 16).padding(.top, 8)
                ProgressView(value: min(1, remaining / duration)).tint(red).progressViewStyle(.linear).padding(.horizontal, 16).padding(.top, 8)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(red: 0.075, green: 0.065, blue: 0.085))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(red.opacity(0.45), lineWidth: 1))
        }.preferredColorScheme(.dark)
    }
}

@MainActor final class BreakingBannerController {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    func show(story: Story, duration: TimeInterval, onDismiss: @escaping () -> Void) {
        hide()
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let width = min(560, screen.visibleFrame.width - 32)
        let size = NSSize(width: width, height: 180)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: BreakingBanner(story: story, duration: duration, deadline: Date().addingTimeInterval(duration), dismiss: onDismiss))
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - width - 16, y: screen.visibleFrame.maxY - size.height - 8))
        self.panel = panel
        panel.orderFrontRegardless()
        dismissal = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000)) }
            catch { return }
            guard self != nil else { return }
            onDismiss()
        }
    }
    func hide() {
        dismissal?.cancel(); dismissal = nil
        panel?.orderOut(nil); panel = nil
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = NewsModel()
    var item: NSStatusItem!
    let popover = NSPopover()
    var timer: Timer?
    var beat = false
    private var observations = Set<AnyCancellable>()
    let banner = BreakingBannerController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self; item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 460, height: 660)
        popover.contentViewController = NSHostingController(rootView: PulseView(model: model))
        model.onAlert = { [weak self] story, duration in
            guard let self else { return }
            self.popover.performClose(nil)
            self.scheduleStatus()
            self.banner.show(story: story, duration: duration) { [weak self] in self?.model.dismissAlert() }
        }
        model.onDismissAlert = { [weak self] in
            self?.banner.hide()
            self?.scheduleStatus()
        }
        model.updates.onAvailable = { [weak self] release in
            guard let self, let url = release.trustedURL else { return }
            let story = Story(title: "LumaPulse \(release.tag_name) is available", summary: "Open the official GitHub release to see what's new and download the update.", source: "GitHub Releases", date: Date(), link: url.absoluteString, kind: "App update")
            self.model.activeAlert = story
            self.model.onAlert?(story, TimeInterval(self.model.alertDuration))
        }
        model.onUninstall = { [weak self] in
            guard let self else { return }
            self.popover.performClose(nil)
            Uninstaller.run(prepare: {
                self.model.updates.stop()
                self.model.setMode(false)
            }, finish: { NSApp.terminate(nil) })
        }
        Publishers.Merge3(
            model.$animate.dropFirst().map { _ in () },
            model.$showTitle.dropFirst().map { _ in () },
            model.$live.dropFirst().map { _ in () }
        ).sink { [weak self] in Task { @MainActor in self?.scheduleStatus() } }
            .store(in: &observations)
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.model.scheduleRefresh()
                    self?.scheduleStatus()
                }
            }.store(in: &observations)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.scheduleStatus() } }
            .store(in: &observations)
        if !CommandLine.arguments.contains("--no-update-check") { model.updates.start() }
        if CommandLine.arguments.contains("--live") { model.setMode(true) }
        if CommandLine.arguments.contains("--simulate") { model.simulateBreakingNews() }
        scheduleStatus()
        if CommandLine.arguments.contains("--show") && !CommandLine.arguments.contains("--simulate") { toggle() }
    }
    func scheduleStatus() {
        timer?.invalidate()
        timer = nil
        beat = false
        updateStatus()
        guard model.activeAlert != nil, model.animate,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.timer != nil else { return }
                self.beat.toggle()
                self.updateStatus()
            }
        }
        timer?.tolerance = 0.16
    }
    func updateStatus() {
        let hasAlert = model.activeAlert != nil
        let name = hasAlert ? (beat ? "bolt.circle.fill" : "bolt.circle") : "waveform.path.ecg"
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "LumaPulse news")
        item.button?.image?.isTemplate = true
        item.button?.imagePosition = .imageLeading
        item.length = hasAlert ? min(600, (NSScreen.main?.frame.width ?? 1440) * 0.40) : NSStatusItem.variableLength
        item.button?.cell?.lineBreakMode = .byTruncatingTail
        let title = hasAlert ? " \(model.alertIsDemo ? "BREAKING NEWS [DEMO]" : (model.activeAlert?.kind == "App update" ? "UPDATE AVAILABLE" : "MARKET ALERT")) · \(model.activeAlert?.title ?? "")" : (model.showTitle ? " LumaPulse" : "")
        item.button?.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: hasAlert ? NSFont.boldSystemFont(ofSize: 12) : NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: hasAlert ? AlertPalette.ink : NSColor.labelColor
        ])
        item.button?.wantsLayer = true
        item.button?.layer?.backgroundColor = hasAlert ? AlertPalette.background.cgColor : nil
        item.button?.layer?.cornerRadius = hasAlert ? 4 : 0
        item.button?.contentTintColor = hasAlert ? AlertPalette.ink : nil
        item.button?.toolTip = model.alertIsDemo ? "SIMULATION ONLY · Fictional breaking-news preview" : (model.activeAlert.map { "\($0.source) · \($0.title)" } ?? (model.live ? "LumaPulse · Stocks, crypto, gold and silver" : "LumaPulse · Draft preview"))
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

if CommandLine.arguments.contains("--check-live-feeds") {
    Task {
        var successes = 0
        for source in FeedSource.all where FeedSource.tradingDefaults.contains(source.id) {
            let result = await MarketFeedLoader.fetch(source)
            print("\(source.name): \(result.stories.map { "\($0.count) headlines" } ?? "unavailable")")
            if result.stories != nil { successes += 1 }
        }
        exit(successes > 0 ? 0 : 1)
    }
    RunLoop.main.run()
}
if CommandLine.arguments.contains("--sandbox-smoke") {
    let outside = URL(fileURLWithPath: "/private/tmp/lumapulse-sandbox-probe-\(UUID().uuidString)")
    do {
        try Data("probe".utf8).write(to: outside)
        try? FileManager.default.removeItem(at: outside)
        print("FAILED: sandbox allowed an unexpected outside-container write")
        exit(1)
    } catch { print("Passed: sandbox denied outside-container file write") }
    exit(0)
}
if CommandLine.arguments.contains("--verify-feeds") {
    let fixtures = ["cnbc": "cnbc-search", "coindesk": "coindesk", "fxstreet": "fxstreet", "fed": "fed"]
    for source in FeedSource.all where fixtures[source.id] != nil {
        let data = try Data(contentsOf: URL(fileURLWithPath: "/tmp/lumapulse-\(fixtures[source.id]!).xml"))
        let feed = FeedParser(source: source)
        let parser = XMLParser(data: data); parser.delegate = feed
        precondition(parser.parse() && !feed.stories.isEmpty, "Feed must parse: \(source.name)")
        precondition(feed.stories.allSatisfy { $0.source == source.name && $0.sourceID == source.id && $0.date != nil })
        print("Verified \(source.name): \(feed.stories.count) headlines, publisher attribution, publication dates")
        if source.id == "fxstreet" {
            precondition(feed.stories.contains { $0.topics.contains(.gold) })
            precondition(feed.stories.contains { $0.topics.contains(.silver) })
            precondition(feed.stories.allSatisfy { !$0.topics.intersection([.gold, .silver, .macro]).isEmpty })
            print("Verified gold / silver coverage and metals / macro filtering")
        }
    }
    exit(0)
}
if CommandLine.arguments.contains("--self-test") {
    let xml = """
    <rss><channel><item><title><![CDATA[World & diplomacy]]></title><description><![CDATA[<p>A report</p>]]></description><link>https://example.com/world</link><pubDate>Sat, 07 Nov 2026 09:00:00 +0000</pubDate></item><item><title>Unsafe link</title><link>javascript:alert(1)</link></item><item><title></title><link>https://example.com/empty</link></item></channel></rss>
    """
    let fixtureSource = FeedSource(id: "fixture", name: "Fixture", detail: "", url: "https://example.com/rss", topics: [])
    let feed = FeedParser(source: fixtureSource); let parser = XMLParser(data: Data(xml.utf8)); parser.delegate = feed
    precondition(parser.parse())
    precondition(feed.stories.count == 1, "Invalid or unsafe stories must be excluded")
    precondition(feed.stories[0].title == "World & diplomacy", "CDATA must preserve titles")
    precondition(feed.stories[0].summary == "A report", "Descriptions must remove HTML")
    precondition(feed.stories[0].date != nil, "RSS dates must parse")
    let bad = XMLParser(data: Data("<rss><item>".utf8))
    precondition(!bad.parse(), "Malformed feeds must fail")
    precondition(AlertTiming.duration(preset: 5, custom: 100) == 5)
    precondition(AlertTiming.duration(preset: 10, custom: 100) == 10)
    precondition(AlertTiming.duration(preset: 30, custom: 100) == 30)
    precondition(AlertTiming.duration(preset: 0, custom: 900) == 900)
    precondition(AlertTiming.duration(preset: 0, custom: 9999) == 1800)
    precondition(AlertTiming.duration(preset: 0, custom: 0) == 1)
    let metals = FeedSource.all.first { $0.id == "fxstreet" }!
    precondition(MarketRules.topics(title: "Gold and silver react to Fed rate decision", summary: "", source: metals) == [.gold, .silver, .macro])
    precondition(MarketRules.topics(title: "Goldman Sachs reports profits", summary: "", source: metals).isEmpty)
    precondition(MarketRules.kind("Silver Price Forecast", source: metals) == "Analysis / forecast")
    precondition(MarketRules.driver("Company earnings beat expectations") == "Company results")
    precondition(MarketRules.driver("A weekend market overview") == nil)
    precondition(!NetworkPolicy.article("https://bbc.com.evil.example/story", source: .world))
    precondition(!NetworkPolicy.article("https://user@bbc.com/story", source: .world))
    precondition(!NetworkPolicy.article("http://www.bbc.com/story", source: .world))
    precondition(!NetworkPolicy.article("https://bbc.com:8443/story", source: .world))
    precondition(NetworkPolicy.article("https://www.bbc.com/story", source: .world))
    precondition(MarketFeedLoader.parse(Data("<!DOCTYPE rss [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><rss/>".utf8), source: .world) == nil)
    precondition(MarketFeedLoader.parse(Data(repeating: 65, count: 1_048_577), source: .world) == nil)
    precondition(ReleaseVersion("1.0.0-rc.1")! < ReleaseVersion("1.0.0")!)
    precondition(ReleaseVersion("1.10.0")! > ReleaseVersion("1.9.0")!)
    precondition(ReleaseVersion("1.0.0;bad") == nil)
    precondition(GitHubRelease(tag_name: "v1.1.0", html_url: "https://github.com/AbdullahNazih/LumaPulse/releases/tag/v1.1.0", draft: false, prerelease: false).trustedURL != nil)
    precondition(GitHubRelease(tag_name: "v1.1.0", html_url: "https://github.com/evil/LumaPulse/releases/tag/v1.1.0", draft: false, prerelease: false).trustedURL == nil)
    precondition(GitHubRelease(tag_name: "v1.1.0", html_url: "https://github.com/AbdullahNazih/LumaPulse/releases/tag/v1.1.0", draft: false, prerelease: true).trustedURL == nil)
    let fixtureTime = ProviderDecoder.date("2026-11-07T12:00:00Z")!
    let benzingaJSON = Data(#"{"kind":"news","data":{"action":"created","id":101,"timestamp":"2026-11-07T12:00:00Z","content":{"title":"Example company reports earnings","teaser":"Test event","created":"Sat, 07 Nov 2026 12:00:00 +0000","url":"https://www.benzinga.com/test-example","stocks":[{"name":"EXAMPLE"}]}}}"#.utf8)
    let newsEvents = try ProviderDecoder.decode(benzingaJSON, provider: .benzinga, now: fixtureTime)
    precondition(newsEvents.count == 1 && newsEvents[0].alert && newsEvents[0].story?.source == "Benzinga")
    let staleEvents = try ProviderDecoder.decode(benzingaJSON, provider: .benzinga, now: fixtureTime.addingTimeInterval(301))
    precondition(staleEvents[0].alert == false)
    let calendarJSON = Data(#"{"topic":"calendar","calendarId":"42","event":"Inflation Rate","country":"United States","actual":"2.4%","forecast":"2.5%","previous":"2.6%","date":"2026-11-07T12:00:00","importance":"3"}"#.utf8)
    let calendarEvents = try ProviderDecoder.decode(calendarJSON, provider: .tradingEconomics, now: fixtureTime)
    precondition(calendarEvents.count == 1 && calendarEvents[0].alert && calendarEvents[0].story?.kind == "Economic release")
    precondition(calendarEvents[0].story!.summary.contains("Forecast: 2.5%"))
    let unreleased = String(data: calendarJSON, encoding: .utf8)!.replacingOccurrences(of: "2.4%", with: "")
    let unreleasedEvents = try ProviderDecoder.decode(Data(unreleased.utf8), provider: .tradingEconomics, now: fixtureTime)
    precondition(unreleasedEvents.isEmpty)
    let encoded = URLComponents(url: TradingProvider.benzinga.url(key: "test&token=?"), resolvingAgainstBaseURL: false)!
    precondition(encoded.queryItems?.first?.value == "test&token=?", "Credentials must be URL-encoded")
    MainActor.assumeIsolated {
        let installFolder = URL(fileURLWithPath: "/Applications", isDirectory: true)
        precondition(Uninstaller.matchesInstallFolder(installFolder, installFolder))
        precondition(!Uninstaller.matchesInstallFolder(installFolder.appendingPathComponent("Other"), installFolder))
        precondition(!Uninstaller.matchesInstallFolder(URL(string: "https://example.com/Applications")!, installFolder))
        let model = NewsModel(automaticAlerts: true)
        let originalIDs = model.stories.map(\.id)
        model.selectedTopic = "Silver"
        precondition(model.visible.count == 1 && model.visible[0].topics.contains(.silver))
        model.query = "not a matching search"
        precondition(model.visible.isEmpty)
        model.query = ""; model.selectedTopic = "All"
        var alerts = 0
        var dismissed = 0
        model.onAlert = { story, duration in
            precondition(story.link == "simulation:breaking")
            precondition(duration == TimeInterval(model.alertDuration))
            alerts += 1
        }
        model.onDismissAlert = { dismissed += 1 }
        model.simulateBreakingNews()
        precondition(alerts == 1 && model.activeAlert != nil)
        model.simulateBreakingNews()
        precondition(alerts == 2, "A repeated test must trigger a fresh notification")
        model.dismissAlert()
        precondition(dismissed == 1 && model.activeAlert == nil)
        precondition(model.stories.map(\.id) == originalIDs, "Notifications must preserve the feed")
        model.onAlert = { story, _ in precondition(story.source == "Benzinga"); alerts += 1 }
        model.live = true
        model.receive(newsEvents[0])
        model.receive(newsEvents[0])
        precondition(alerts == 3, "Repeated stream messages must not repeat alerts")
        precondition(!model.alertIsDemo && model.visible.filter { $0.id == "benzinga:101" }.count == 1)
        model.receive(ProviderEvent(deletedID: "benzinga:101"))
        precondition(model.activeAlert == nil && !model.stories.contains { $0.id == "benzinga:101" })
        let paused = NewsModel(automaticAlerts: true)
        paused.receive(newsEvents[0])
        precondition(paused.activeAlert == nil, "Paused live mode must ignore events")
        let quiet = NewsModel(automaticAlerts: false)
        quiet.live = true; quiet.receive(newsEvents[0])
        precondition(quiet.activeAlert == nil && quiet.stories.contains { $0.id == "benzinga:101" })
    }
    print("Passed: RSS parser, topic filters, alert durations, stream decoding, stale/unreleased filtering, deduplication, deletions, pause/quiet mode, and credential URL encoding")
    exit(0)
}
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
