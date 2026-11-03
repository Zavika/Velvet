import SwiftUI

struct DetailView: View {
    let itemId: String
    let autoplay: Bool
    @EnvironmentObject var client: Client

    @State private var item: Item?
    @State private var error: String?
    @State private var info: PlaybackInfo?
    @State private var infoError: String?
    @State private var loadingInfo = false
    @State private var seriesId: String?
    @State private var seasons: [Item] = []
    @State private var season: String?
    @State private var episodes: [Item] = []
    @State private var loadingEps = false
    @State private var playing: Selection?
    @State private var didAutoplay = false

    var body: some View {
        ScrollView {
            if let item { content(item) }
            else if let error { Message(error).padding(.top, 200) }
            else { Loading().padding(.top, 300) }
        }
        .background(Color.ink)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
        .fullScreenCover(item: $playing, onDismiss: { Task { await refresh() } }) { sel in
            PlayerView(selection: sel, client: client)
        }
    }

    @ViewBuilder
    private func content(_ it: Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                Color.panel
                    .overlay {
                        AsyncImage(url: client.backdrop(it)) { phase in
                            if let img = phase.image { img.resizable().scaledToFill() }
                        }
                    }
                    .clipped()
                LinearGradient(colors: [.ink, .ink.opacity(0)], startPoint: .bottom, endPoint: .center)
            }
            .frame(height: 360)

            VStack(alignment: .leading, spacing: 14) {
                if it.type == "Episode", let s = it.seriesName {
                    Text(s.uppercased()).font(.caption.weight(.bold)).kerning(1.4).foregroundStyle(Color.rose)
                }
                Text(it.title).font(.display(36)).foregroundStyle(Color.textMain)
                if !it.meta.isEmpty {
                    Text(it.meta.joined(separator: "  ·  "))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.muted)
                }
                if let o = it.overview {
                    Text(o).font(.subheadline).foregroundStyle(Color.textMain.opacity(0.82))
                }
                if it.isSeriesLike { seriesSection }
                else if it.isPlayable { sourcesSection(it) }
            }
            .padding(.horizontal, 16)
            .padding(.top, -50)
            .padding(.bottom, 40)
        }
    }

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(seasons) { s in
                        Chip(title: s.title, on: season == s.id) {
                            season = s.id
                            Task { await loadEpisodes() }
                        }
                    }
                }
            }
            if loadingEps { Loading() }
            ForEach(episodes) { e in
                NavigationLink(value: Route.detail(e.id, autoplay: false)) { EpisodeRow(item: e) }
                    .buttonStyle(.plain)
            }
            if !loadingEps && episodes.isEmpty && season != nil { Message("No episodes.") }
        }
        .padding(.top, 6)
    }

    private func sourcesSection(_ it: Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Streams").font(.display(19)).foregroundStyle(Color.textMain).padding(.top, 8)
            if loadingInfo {
                HStack(spacing: 10) {
                    ProgressView().tint(.rose)
                    Text("Finding streams…").font(.subheadline).foregroundStyle(Color.muted)
                }
                .padding(.vertical, 12)
            } else if let infoError {
                Message(infoError)
            } else if let srcs = info?.mediaSources, !srcs.isEmpty {
                ForEach(srcs) { s in
                    Button {
                        playing = Selection(item: it, source: s, session: info?.playSessionId)
                    } label: {
                        SourceRow(source: s, fallback: it.title)
                    }
                    .buttonStyle(.plain)
                }
            } else if info != nil {
                Message("No streams found for this title.")
            }
        }
    }

    private func load() async {
        guard item == nil else { return }
        do {
            let it = try await client.item(itemId)
            item = it
            if it.isSeriesLike {
                let sid = it.type == "Series" ? it.id : (it.seriesId ?? it.id)
                seriesId = sid
                seasons = await client.seasons(sid)
                season = it.type == "Season" ? it.id : seasons.first?.id
                await loadEpisodes()
            } else if it.isPlayable {
                await loadInfo(it)
            }
        } catch {
            self.error = "Couldn't load: \(error.localizedDescription)"
        }
    }

    private func loadInfo(_ it: Item) async {
        loadingInfo = true
        defer { loadingInfo = false }
        do {
            let i = try await client.playbackInfo(it.id)
            info = i
            if autoplay, !didAutoplay, let s = i.mediaSources?.first {
                didAutoplay = true
                playing = Selection(item: it, source: s, session: i.playSessionId)
            }
        } catch {
            infoError = "Couldn't find streams: \(error.localizedDescription)"
        }
    }

    private func loadEpisodes() async {
        guard let sid = seriesId, let season else { return }
        loadingEps = true
        episodes = []
        let list = await client.episodes(sid, season: season)
        if season == self.season { episodes = list }
        loadingEps = false
    }

    private func refresh() async {
        if let it = try? await client.item(itemId) { item = it }
    }
}

struct EpisodeRow: View {
    let item: Item
    @EnvironmentObject var client: Client

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtView(
                url: client.imageURL(item.id, "Primary", "fillWidth=360"),
                label: "E\(item.indexNumber.map(String.init) ?? "")",
                ratio: 16 / 9,
                progress: item.userData?.playedPercentage
            )
            .frame(width: 132)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(item.indexNumber.map { "\($0). " } ?? "")\(item.title)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textMain)
                    .lineLimit(2)
                Text([formatRuntime(item.runTimeTicks), item.overview].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color.muted)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

struct SourceRow: View {
    let source: MediaSource
    let fallback: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(source.name ?? fallback)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textMain)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                if !source.details.isEmpty {
                    Text(source.details).font(.caption).foregroundStyle(Color.muted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.onRose)
                .frame(width: 34, height: 34)
                .background(Color.rose, in: Circle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08)))
        .contentShape(Rectangle())
    }
}
