import SwiftUI

@main
struct VelvetApp: App {
    @StateObject private var client = Client()

    var body: some Scene {
        WindowGroup {
            Root()
                .environmentObject(client)
                .preferredColorScheme(.dark)
                .tint(.rose)
        }
    }
}

struct Root: View {
    @EnvironmentObject var client: Client

    var body: some View {
        if client.isSignedIn {
            TabView {
                HomeView().tabItem { Label("Home", systemImage: "house.fill") }
                LibraryView().tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
                SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
            }
        } else {
            LoginView()
        }
    }
}
