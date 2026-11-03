import Foundation

struct UserData: Codable, Hashable {
    var playedPercentage: Double?
    var playbackPositionTicks: Int64?
    var played: Bool?
}

struct Item: Codable, Identifiable, Hashable {
    let id: String
    var name: String?
    var type: String?
    var overview: String?
    var productionYear: Int?
    var runTimeTicks: Int64?
    var officialRating: String?
    var communityRating: Double?
    var genres: [String]?
    var seriesName: String?
    var seriesId: String?
    var seasonId: String?
    var indexNumber: Int?
    var parentIndexNumber: Int?
    var isFolder: Bool?
    var mediaType: String?
    var backdropImageTags: [String]?
    var parentBackdropItemId: String?
    var userData: UserData?

    var title: String { name ?? "Untitled" }
    var hasBackdrop: Bool { !(backdropImageTags ?? []).isEmpty }
    var isSeriesLike: Bool { type == "Series" || type == "Season" }
    var isPlayable: Bool { mediaType == "Video" || ["Movie", "Episode", "Video"].contains(type ?? "") }
    var isBrowsableFolder: Bool { (isFolder ?? false) && !["Series", "Season", "BoxSet"].contains(type ?? "") }

    var episodeCode: String? {
        guard let p = parentIndexNumber else { return nil }
        return "S\(p)E\(indexNumber.map(String.init) ?? "?")"
    }

    var subtitle: String? {
        if type == "Episode" {
            let parts = [seriesName, episodeCode].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        if let y = productionYear { return String(y) }
        return type == "Series" ? "Series" : nil
    }

    var meta: [String] {
        var m: [String] = []
        if type == "Episode", let c = episodeCode { m.append(c) }
        if let y = productionYear { m.append(String(y)) }
        if let r = formatRuntime(runTimeTicks) { m.append(r) }
        if let o = officialRating { m.append(o) }
        if let c = communityRating { m.append(String(format: "★ %.1f", c)) }
        if let g = genres, !g.isEmpty { m.append(g.prefix(3).joined(separator: ", ")) }
        return m
    }
}

struct ItemsResponse: Codable {
    var items: [Item]?
    var totalRecordCount: Int?
}

struct AuthUser: Codable {
    let id: String
    var name: String?
}

struct AuthResponse: Codable {
    let accessToken: String
    let user: AuthUser
}

struct MediaStream: Codable, Hashable {
    var type: String?
    var codec: String?
    var height: Int?
}

struct MediaSource: Codable, Identifiable, Hashable {
    let id: String
    var name: String?
    var container: String?
    var size: Int64?
    var directStreamUrl: String?
    var mediaStreams: [MediaStream]?

    var details: String {
        let v = mediaStreams?.first { $0.type == "Video" }
        var parts: [String] = []
        if let h = v?.height { parts.append(h >= 2100 ? "4K" : "\(h)p") }
        if let c = v?.codec, !c.isEmpty { parts.append(c.uppercased()) }
        if let c = container, !c.isEmpty { parts.append(c.uppercased()) }
        if let s = formatSize(size) { parts.append(s) }
        return parts.joined(separator: " · ")
    }
}

struct PlaybackInfo: Codable {
    var mediaSources: [MediaSource]?
    var playSessionId: String?
}

struct Selection: Identifiable {
    let id = UUID()
    let item: Item
    let source: MediaSource
    let session: String?
}

enum Route: Hashable {
    case detail(String, autoplay: Bool)
    case folder(String, String)
}

func route(for item: Item) -> Route {
    item.isBrowsableFolder ? .folder(item.id, item.title) : .detail(item.id, autoplay: false)
}

func formatRuntime(_ ticks: Int64?) -> String? {
    guard let ticks, ticks > 0 else { return nil }
    let m = Int((Double(ticks) / 6e8).rounded())
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
}

func formatSize(_ bytes: Int64?) -> String? {
    guard let bytes, bytes > 0 else { return nil }
    let gb = Double(bytes) / 1_073_741_824
    return gb >= 1 ? String(format: "%.1f GB", gb) : "\(Int(Double(bytes) / 1_048_576)) MB"
}

func formatClock(_ ms: Int32) -> String {
    let s = max(0, Int(ms) / 1000)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

// Jellyfin sends PascalCase keys; map them to camelCase properties.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
}

let jsonDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .custom { keys in
        let k = keys.last!.stringValue
        guard let f = k.first else { return AnyKey(stringValue: k) }
        return AnyKey(stringValue: f.lowercased() + k.dropFirst())
    }
    return d
}()
