import SwiftUI

struct LoginView: View {
    @EnvironmentObject var client: Client
    @State private var server = UserDefaults.standard.string(forKey: "server") ?? ""
    @State private var user = ""
    @State private var pass = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()
            RadialGradient(colors: [Color.rose.opacity(0.25), .clear], center: .topTrailing, startRadius: 0, endRadius: 440)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    (Text("Velvet").foregroundColor(.textMain) + Text(".").foregroundColor(.rose))
                        .font(.display(58))
                    Text("Sign in to your Jellyfin server.")
                        .foregroundStyle(Color.muted)
                    field("SERVER URL") {
                        TextField("", text: $server, prompt: Text("https://your-server.example").foregroundColor(.muted))
                            .keyboardType(.URL)
                            .textContentType(.URL)
                    }
                    field("USERNAME") {
                        TextField("", text: $user).textContentType(.username)
                    }
                    field("PASSWORD") {
                        SecureField("", text: $pass).textContentType(.password)
                    }
                    if let error {
                        Text(error).font(.subheadline).foregroundStyle(Color.warn)
                    }
                    Button {
                        Task { await go() }
                    } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.onRose) }
                            Text(busy ? "Signing in…" : "Sign in")
                        }
                        .frame(maxWidth: .infinity)
                        .pill(primary: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || server.isEmpty || user.isEmpty)
                }
                .padding(24)
                .padding(.top, 70)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).kerning(1).foregroundStyle(Color.muted)
            content()
                .padding(14)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.09)))
                .foregroundStyle(Color.textMain)
        }
    }

    private func go() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await client.signIn(server: server, username: user, password: pass)
        } catch let e as URLError {
            error = "Can't reach the server (\(e.code.rawValue)). Check the address."
        } catch {
            self.error = "Sign in failed: \(error.localizedDescription)"
        }
    }
}
