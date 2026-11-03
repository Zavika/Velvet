import SwiftUI

struct ArtView: View {
    let url: URL?
    let label: String
    var ratio: CGFloat = 2 / 3
    var progress: Double? = nil

    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.panel2, .panel], startPoint: .topLeading, endPoint: .bottomTrailing))
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.muted)
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
            .overlay {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() }
                }
            }
            .overlay(alignment: .bottom) {
                if let p = progress, p > 0 {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.25))
                            Capsule().fill(Color.rose).frame(width: g.size.width * min(1, p / 100))
                        }
                    }
                    .frame(height: 4)
                    .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct Card: View {
    let item: Item
    var width: CGFloat? = nil
    var wide = false
    @EnvironmentObject var client: Client

    var body: some View {
        NavigationLink(value: route(for: item)) {
            VStack(alignment: .leading, spacing: 6) {
                ArtView(
                    url: wide ? client.wideImage(item) : client.imageURL(item.id),
                    label: item.title,
                    ratio: wide ? 16 / 9 : 2 / 3,
                    progress: item.userData?.playedPercentage
                )
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textMain)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let s = item.subtitle {
                    Text(s).font(.caption).foregroundStyle(Color.muted).lineLimit(1)
                }
            }
            .frame(minWidth: width, maxWidth: width ?? .infinity, alignment: .topLeading)
        }
        .buttonStyle(.plain)
    }
}

struct Rail: View {
    let title: String
    let items: [Item]
    var wide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.display(21))
                .foregroundStyle(Color.textMain)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { Card(item: $0, width: wide ? 236 : 128, wide: wide) }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct Chip: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(on ? Color.rose : Color.panel, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(on ? 0 : 0.08)))
                .foregroundStyle(on ? Color.onRose : Color.textMain)
        }
        .buttonStyle(.plain)
    }
}

struct Message: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(40)
    }
}

struct Loading: View {
    var body: some View {
        ProgressView().tint(.rose).frame(maxWidth: .infinity).padding(40)
    }
}

struct ItemGrid: View {
    let parentId: String
    @EnvironmentObject var client: Client
    @State private var items: [Item] = []
    @State private var total = Int.max
    @State private var loading = false
    @State private var error: String?

    private let cols = [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, alignment: .leading, spacing: 16) {
                ForEach(items) { it in
                    Card(item: it).onAppear {
                        if it.id == items.last?.id { Task { await loadMore() } }
                    }
                }
            }
            .padding(16)
            if loading { Loading() }
            else if let error { Message(error) }
            else if items.isEmpty && total == 0 { Message("This library is empty.") }
        }
        .background(Color.ink)
        .task { if items.isEmpty { await loadMore() } }
    }

    private func loadMore() async {
        guard !loading, items.count < total else { return }
        loading = true
        defer { loading = false }
        do {
            let r = try await client.children(parentId, start: items.count)
            let new = r.items ?? []
            items += new
            total = new.isEmpty ? items.count : (r.totalRecordCount ?? items.count)
        } catch {
            self.error = "Couldn't load: \(error.localizedDescription)"
            total = items.count
        }
    }
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .detail(let id, let autoplay):
            DetailView(itemId: id, autoplay: autoplay)
        case .folder(let id, let name):
            ItemGrid(parentId: id).navigationTitle(name)
        }
    }
}
