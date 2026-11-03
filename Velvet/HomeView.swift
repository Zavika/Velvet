import SwiftUI

struct RailData: Identifiable {
    let id: String
    let title: String
    let items: [Item]
}

struct HomeView: View {
    @EnvironmentObject var client: Client
    @State private var resume: [Item] = []
    @State private var rails: [RailData] = []
    @State private var loaded = false

    private var hero: Item? {
        let pool = resume + rails.flatMap(\.items)
        return pool.first(where: \.hasBackdrop) ?? pool.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let h = hero {
                        HeroView(item: h, isResume: resume.contains(h))
                    } else if loaded {
                        Message("Nothing here yet.").padding(.top, 160)
                    } else {
                        Loading().padding(.top, 220)
                    }
                    if !resume.isEmpty { Rail(title: "Continue watching", items: resume, wide: true) }
                    ForEach(rails) { r in
                        if !r.items.isEmpty { Rail(title: "Latest in \(r.title)", items: r.items) }
                    }
                }
                .padding(.bottom, 30)
            }
            .background(Color.ink)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .topTrailing) {
                Button { client.signOut() } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.textMain)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Sign out")
                .padding(.trailing, 16)
                .padding(.top, 4)
            }
            .refreshable { await load() }
            .task { if !loaded { await load() } }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func load() async {
        let c = client
        async let r = c.resume()
        async let v = c.views()
        let (res, views) = await (r, v)
        let picked = Array(views.prefix(8))
        let latest = await withTaskGroup(of: (Int, [Item]).self, returning: [Int: [Item]].self) { g in
            for (i, view) in picked.enumerated() {
                let id = view.id
                g.addTask { (i, await c.latest(id)) }
            }
            var m: [Int: [Item]] = [:]
            for await (i, list) in g { m[i] = list }
            return m
        }
        resume = res
        rails = picked.enumerated().map { RailData(id: $1.id, title: $1.title, items: latest[$0] ?? []) }
        loaded = true
    }
}

struct HeroView: View {
    let item: Item
    let isResume: Bool
    @EnvironmentObject var client: Client

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.panel
                .overlay {
                    AsyncImage(url: client.backdrop(item)) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() }
                    }
                }
                .clipped()
            LinearGradient(
                stops: [
                    .init(color: .ink, location: 0.02),
                    .init(color: .ink.opacity(0.55), location: 0.45),
                    .init(color: .ink.opacity(0.1), location: 0.8),
                    .init(color: .ink.opacity(0.6), location: 1)
                ],
                startPoint: .bottom, endPoint: .top
            )
            VStack(alignment: .leading, spacing: 12) {
                Text(isResume ? "CONTINUE WATCHING" : "JUST ADDED")
                    .font(.caption.weight(.bold))
                    .kerning(1.4)
                    .foregroundStyle(Color.rose)
                Text(item.type == "Episode" ? (item.seriesName ?? item.title) : item.title)
                    .font(.display(42))
                    .foregroundStyle(Color.textMain)
                    .lineLimit(3)
                if let o = item.overview {
                    Text(o)
                        .font(.subheadline)
                        .foregroundStyle(Color.textMain.opacity(0.8))
                        .lineLimit(3)
                }
                HStack(spacing: 10) {
                    NavigationLink(value: Route.detail(item.id, autoplay: true)) {
                        Label("Play", systemImage: "play.fill").pill(primary: true)
                    }
                    NavigationLink(value: Route.detail(item.id, autoplay: false)) {
                        Text("More info").pill(primary: false)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(height: 540)
    }
}
