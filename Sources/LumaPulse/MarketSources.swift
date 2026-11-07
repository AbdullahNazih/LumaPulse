import Foundation

enum MarketTopic: String, CaseIterable, Identifiable, Sendable {
    case stocks = "Stocks", crypto = "Crypto", gold = "Gold", silver = "Silver", macro = "Macro", world = "World"
    var id: String { rawValue }
}

struct FeedSource: Identifiable, Sendable {
    let id: String
    let name: String
    let detail: String
    let url: String
    let topics: Set<MarketTopic>
    var metalsOnly = false
    static let world = FeedSource(id: "bbc", name: "BBC News", detail: "World headlines", url: "https://feeds.bbci.co.uk/news/world/rss.xml", topics: [.world])
    static let all: [FeedSource] = [
        FeedSource(id: "cnbc", name: "CNBC", detail: "Stocks, earnings, and financial markets", url: "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=10000664", topics: [.stocks]),
        FeedSource(id: "coindesk", name: "CoinDesk", detail: "Crypto markets, exchanges, and regulation", url: "https://www.coindesk.com/arc/outboundfeeds/rss/", topics: [.crypto]),
        FeedSource(id: "fxstreet", name: "FXStreet", detail: "Gold, silver, and related macro news / analysis", url: "https://www.fxstreet.com/rss/news", topics: [], metalsOnly: true),
        FeedSource(id: "fed", name: "Federal Reserve", detail: "Official monetary-policy releases", url: "https://www.federalreserve.gov/feeds/press_monetary.xml", topics: [.macro]),
        world
    ]
    static let tradingDefaults: Set<String> = ["cnbc", "coindesk", "fxstreet", "fed"]
}

enum MarketRules {
    static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func topics(title: String, summary: String, source: FeedSource) -> Set<MarketTopic> {
        let text = title + " " + summary
        var topics = source.topics
        if matches(text, #"\b(gold|xau|bullion)\b"#) { topics.insert(.gold) }
        if matches(text, #"\b(silver|xag)\b"#) { topics.insert(.silver) }
        if matches(text, #"\b(bitcoin|ethereum|crypto|btc|eth|stablecoins?|blockchain)\b"#) { topics.insert(.crypto) }
        if matches(text, #"\b(federal reserve|fed|fomc|interest rates?|inflation|cpi|payrolls?|central bank)\b"#) { topics.insert(.macro) }
        return topics
    }
    static func kind(_ title: String, source: FeedSource) -> String {
        if source.id == "fed" { return "Official release" }
        return matches(title, #"\b(forecast|outlook|analysis|opinion|prediction)\b"#) || (source.id == "fxstreet" && matches(title, #"–|\s-\s"#)) ? "Analysis / forecast" : "News"
    }
    static func driver(_ title: String) -> String? {
        if matches(title, #"\b(fomc|federal reserve|fed|interest rates?|rate (cut|hike|decision)|central bank)\b"#) { return "Rates / policy" }
        if matches(title, #"\b(inflation|cpi|payrolls?|jobs report|gdp)\b"#) { return "Economic data" }
        if matches(title, #"\b(earnings|buybacks?|profit|revenue|guidance)\b"#) { return "Company results" }
        if matches(title, #"\b(sec|regulat\w*|etf|treasury|ban|bans|sanctions?)\b"#) { return "Regulation / flows" }
        if matches(title, #"\b(hack\w*|breach|exploit|liquidat\w*|outage)\b"#) { return "Security / disruption" }
        return nil
    }
}

struct FeedResult: Sendable {
    let sourceID: String
    let stories: [Story]?
}

enum MarketFeedLoader {
    static func parse(_ data: Data, source: FeedSource) -> [Story]? {
        guard data.count <= 1_048_576, let text = String(data: data, encoding: .utf8),
              text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              text.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { return nil }
        let delegate = FeedParser(source: source)
        let parser = XMLParser(data: data); parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        guard parser.parse(), delegate.itemCount > 0 else { return nil }
        return delegate.stories
    }
    static func fetch(_ source: FeedSource) async -> FeedResult {
        do {
            let (data, response) = try await LimitedHTTP.shared.get(URL(string: source.url)!)
            guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
            guard let stories = parse(data, source: source) else { throw URLError(.cannotParseResponse) }
            return FeedResult(sourceID: source.id, stories: stories)
        } catch { return FeedResult(sourceID: source.id, stories: nil) }
    }
}
