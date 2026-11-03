import Foundation

enum APIError: LocalizedError {
    case status(Int), unauthorized, badURL

    var errorDescription: String? {
        switch self {
        case .status(let c): return "The server returned an error (\(c))."
        case .unauthorized: return "Your session expired. Sign in again."
        case .badURL: return "That server address isn't valid."
        }
    }
}

@MainActor
final class Client: ObservableObject {
    @Published var server: String
    @Published var token: String?
    @Published var userId: String?
    let deviceId: String
    private let defaults = UserDefaults.standard

    init() {
        server = defaults.string(forKey: "server") ?? ""
        token = defaults.string(forKey: "token")
        userId = defaults.string(forKey: "userId")
        if let d = defaults.string(forKey: "deviceId") {
            deviceId = d
        } else {
            let d = UUID().uuidString
            defaults.set(d, forKey: "deviceId")
            deviceId = d
        }
    }

    var isSignedIn: Bool { token != nil && userId != nil }
    private var u: String { userId ?? "" }
    private let fields = "&Fields=Overview,PrimaryImageAspectRatio,ProductionYear&EnableImageTypes=Primary,Backdrop,Thumb"

    private func authHeader(_ tok: String?) -> String {
        var h = "MediaBrowser Client=\"Velvet\", Device=\"iPhone\", DeviceId=\"\(deviceId)\", Version=\"1.0.0\""
        if let tok { h += ", Token=\"\(tok)\"" }
        return h
    }

    // MARK: networking

    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: server + path) else { throw APIError.badURL }
        var r = URLRequest(url: url)
        r.httpMethod = method
        let h = authHeader(token)
        r.setValue(h, forHTTPHeaderField: "Authorization")
        r.setValue(h, forHTTPHeaderField: "X-Emby-Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && token != nil { clearSession(); throw APIError.unauthorized }
        guard (200..<300).contains(code) else { throw APIError.status(code) }
        return data
    }

    // Newer servers use /UserItems, /UserViews, /Items?userId=; older ones use /Users/{id}/...
    private func first(_ paths: [String]) async throws -> Data {
        var last: Error = APIError.status(0)
        for p in paths {
            do { return try await request(p) }
            catch APIError.unauthorized { throw APIError.unauthorized }
            catch { last = error }
        }
        throw last
    }

    private func items(_ paths: [String]) async throws -> [Item] {
        let d = try await first(paths)
        if let arr = try? jsonDecoder.decode([Item].self, from: d) { return arr }
        return try jsonDecoder.decode(ItemsResponse.self, from: d).items ?? []
    }

    // MARK: session

    func signIn(server raw: String, username: String, password: String) async throws {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        server = s
        token = nil
        let d = try await request("/Users/AuthenticateByName", method: "POST", body: ["Username": username, "Pw": password])
        let a = try jsonDecoder.decode(AuthResponse.self, from: d)
        defaults.set(s, forKey: "server")
        defaults.set(a.accessToken, forKey: "token")
        defaults.set(a.user.id, forKey: "userId")
        token = a.accessToken
        userId = a.user.id
    }

    func signOut() {
        if let t = token, let url = URL(string: server + "/Sessions/Logout") {
            var r = URLRequest(url: url)
            r.httpMethod = "POST"
            r.setValue(authHeader(t), forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: r).resume()
        }
        clearSession()
    }

    private func clearSession() {
        token = nil
        userId = nil
        defaults.removeObject(forKey: "token")
        defaults.removeObject(forKey: "userId")
    }

    // MARK: library

    func resume() async -> [Item] {
        (try? await items([
            "/UserItems/Resume?userId=\(u)&Limit=16&MediaTypes=Video\(fields)",
            "/Users/\(u)/Items/Resume?Limit=16&MediaTypes=Video\(fields)"
        ])) ?? []
    }

    func views() async -> [Item] {
        (try? await items(["/UserViews?userId=\(u)", "/Users/\(u)/Views"])) ?? []
    }

    func latest(_ parent: String) async -> [Item] {
        (try? await items([
            "/Items/Latest?userId=\(u)&parentId=\(parent)&Limit=16\(fields)",
            "/Users/\(u)/Items/Latest?ParentId=\(parent)&Limit=16\(fields)"
        ])) ?? []
    }

    func children(_ parent: String, start: Int) async throws -> ItemsResponse {
        let q = "ParentId=\(parent)&SortBy=SortName&SortOrder=Ascending&StartIndex=\(start)&Limit=60&Fields=ProductionYear"
        let d = try await first(["/Items?userId=\(u)&\(q)", "/Users/\(u)/Items?\(q)"])
        return try jsonDecoder.decode(ItemsResponse.self, from: d)
    }

    func search(_ term: String) async throws -> [Item] {
        let t = term.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? term
        let q = "searchTerm=\(t)&Recursive=true&IncludeItemTypes=Movie,Series,Episode&Limit=48&Fields=ProductionYear"
        return try await items(["/Items?userId=\(u)&\(q)", "/Users/\(u)/Items?\(q)"])
    }

    func item(_ id: String) async throws -> Item {
        let d = try await first(["/Items/\(id)?userId=\(u)", "/Users/\(u)/Items/\(id)"])
        return try jsonDecoder.decode(Item.self, from: d)
    }

    func seasons(_ series: String) async -> [Item] {
        (try? await items(["/Shows/\(series)/Seasons?userId=\(u)"])) ?? []
    }

    func episodes(_ series: String, season: String) async -> [Item] {
        (try? await items(["/Shows/\(series)/Episodes?userId=\(u)&seasonId=\(season)&Fields=Overview"])) ?? []
    }

    func playbackInfo(_ id: String) async throws -> PlaybackInfo {
        let p = "/Items/\(id)/PlaybackInfo?userId=\(u)"
        do {
            let d = try await request(p, method: "POST", body: ["UserId": u, "AutoOpenLiveStream": false])
            return try jsonDecoder.decode(PlaybackInfo.self, from: d)
        } catch APIError.unauthorized {
            throw APIError.unauthorized
        } catch {
            return try jsonDecoder.decode(PlaybackInfo.self, from: try await request(p))
        }
    }

    // MARK: images & streams

    func imageURL(_ id: String, _ type: String = "Primary", _ q: String = "fillHeight=420") -> URL? {
        URL(string: "\(server)/Items/\(id)/Images/\(type)?\(q)&quality=85&api_key=\(token ?? "")")
    }

    func wideImage(_ it: Item) -> URL? {
        if it.type == "Episode" { return imageURL(it.id, "Primary", "fillWidth=480") }
        if it.hasBackdrop { return imageURL(it.id, "Backdrop", "fillWidth=480") }
        if let p = it.parentBackdropItemId { return imageURL(p, "Backdrop", "fillWidth=480") }
        return imageURL(it.id, "Thumb", "fillWidth=480")
    }

    func backdrop(_ it: Item, width: Int = 1400) -> URL? {
        let q = "fillWidth=\(width)"
        if it.hasBackdrop { return imageURL(it.id, "Backdrop", q) }
        if let p = it.parentBackdropItemId { return imageURL(p, "Backdrop", q) }
        return imageURL(it.id, "Primary", q)
    }

    func streamURL(_ it: Item, _ s: MediaSource) -> URL? {
        if let d = s.directStreamUrl, !d.isEmpty {
            var url = d.hasPrefix("http") ? d : server + d
            if !url.lowercased().contains("api_key=") {
                url += (url.contains("?") ? "&" : "?") + "api_key=\(token ?? "")"
            }
            return URL(string: url)
        }
        let ms = s.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s.id
        return URL(string: "\(server)/Videos/\(it.id)/stream?static=true&mediaSourceId=\(ms)&deviceId=\(deviceId)&api_key=\(token ?? "")")
    }

    func report(_ kind: String, _ sel: Selection, ticks: Int64, paused: Bool) {
        let body: [String: Any] = [
            "ItemId": sel.item.id, "MediaSourceId": sel.source.id, "PlaySessionId": sel.session ?? "",
            "PlayMethod": "DirectStream", "PositionTicks": ticks, "IsPaused": paused, "CanSeek": true
        ]
        Task { _ = try? await request("/Sessions/Playing\(kind)", method: "POST", body: body) }
    }
}
