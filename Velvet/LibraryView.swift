import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var client: Client
    @State private var views: [Item] = []
    @State private var selected: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(views) { v in
                            Chip(title: v.title, on: selected == v.id) { selected = v.id }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                if let s = selected {
                    ItemGrid(parentId: s).id(s)
                } else if loaded {
                    Message("No libraries found.")
                    Spacer()
                } else {
                    Loading()
                    Spacer()
                }
            }
            .background(Color.ink)
            .navigationTitle("Library")
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
            .task {
                guard !loaded else { return }
                views = await client.views()
                selected = selected ?? views.first?.id
                loaded = true
            }
        }
    }
}

struct SearchView: View {
    @EnvironmentObject var client: Client
    @State private var query = ""
    @State private var results: [Item] = []
    @State private var searching = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(results) { Card(item: $0) }
                }
                .padding(16)
                if searching { Loading() }
                else if let message { Message(message) }
            }
            .background(Color.ink)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Movies, shows, episodes")
            .task(id: query) { await run() }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }

    private func run() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { results = []; message = nil; return }
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        searching = true
        defer { searching = false }
        do {
            let r = try await client.search(term)
            if Task.isCancelled { return }
            results = r
            message = r.isEmpty ? "No results for “\(term)”." : nil
        } catch {
            if !Task.isCancelled { message = "Search failed: \(error.localizedDescription)" }
        }
    }
}
