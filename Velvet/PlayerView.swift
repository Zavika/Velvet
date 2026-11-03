import SwiftUI
import MobileVLCKit

struct Track: Identifiable, Hashable {
    let id: Int32
    let name: String
}

@MainActor
final class PlayerModel: ObservableObject {
    let player = VLCMediaPlayer()
    let selection: Selection
    let client: Client

    @Published var playing = false
    @Published var position: Float = 0
    @Published var timeText = "0:00"
    @Published var remainingText = ""
    @Published var buffering = true
    @Published var failed = false
    @Published var audioTracks: [Track] = []
    @Published var subTracks: [Track] = []
    @Published var currentAudio: Int32 = -1
    @Published var currentSub: Int32 = -1
    var scrubbing = false

    private var timer: Timer?
    private var reportTimer: Timer?
    private var ticks = 0
    private var started = false
    private var stopped = false

    init(selection: Selection, client: Client) {
        self.selection = selection
        self.client = client
    }

    func start(view: UIView) {
        guard !started else { return }
        started = true
        guard let url = client.streamURL(selection.item, selection.source) else { failed = true; return }
        let media = VLCMedia(url: url)
        let resume = Double(selection.item.userData?.playbackPositionTicks ?? 0) / 1e7
        let length = Double(selection.item.runTimeTicks ?? 0) / 1e7
        if resume > 5 && (length == 0 || resume < length - 10) {
            media.addOption(":start-time=\(Int(resume))")
        }
        media.addOption(":network-caching=2000")
        player.media = media
        player.drawable = view
        player.play()
        client.report("", selection, ticks: Int64(resume * 1e7), paused: false)

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        reportTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendProgress() }
        }
    }

    private var currentTicks: Int64 { Int64(player.time.intValue) * 10_000 }

    private func sendProgress() {
        guard !stopped, player.time.intValue > 0 else { return }
        client.report("/Progress", selection, ticks: currentTicks, paused: !player.isPlaying)
    }

    private func tick() {
        let st = player.state
        playing = player.isPlaying
        buffering = !player.isPlaying && (st == .opening || st == .buffering || st == .stopped) && player.time.intValue == 0
        if st == .error { failed = true; buffering = false }
        let t = player.time.intValue
        let len = player.media?.length.intValue ?? 0
        if !scrubbing { position = player.position }
        timeText = formatClock(t)
        remainingText = len > 0 ? "-" + formatClock(len - t) : ""
        ticks += 1
        if ticks % 4 == 0 { loadTracks() }
    }

    private func loadTracks() {
        let an = (player.audioTrackNames as? [String]) ?? []
        let ai = (player.audioTrackIndexes as? [NSNumber]) ?? []
        let a = zip(ai, an).map { Track(id: $0.int32Value, name: $1) }.filter { $0.id >= 0 }
        if a != audioTracks { audioTracks = a }
        let sn = (player.videoSubTitlesNames as? [String]) ?? []
        let si = (player.videoSubTitlesIndexes as? [NSNumber]) ?? []
        let s = zip(si, sn).map { Track(id: $0.int32Value, name: $1) }
        if s != subTracks { subTracks = s }
        currentAudio = player.currentAudioTrackIndex
        currentSub = player.currentVideoSubTitleIndex
    }

    func togglePlay() {
        if player.isPlaying {
            player.pause()
            client.report("/Progress", selection, ticks: currentTicks, paused: true)
        } else {
            player.play()
        }
    }

    func skip(_ seconds: Int32) {
        if seconds > 0 { player.jumpForward(seconds) } else { player.jumpBackward(-seconds) }
    }

    func seek(_ pos: Float) { player.position = pos }

    func setAudio(_ i: Int32) { player.currentAudioTrackIndex = i; currentAudio = i }
    func setSub(_ i: Int32) { player.currentVideoSubTitleIndex = i; currentSub = i }

    func stop() {
        guard !stopped else { return }
        stopped = true
        timer?.invalidate()
        reportTimer?.invalidate()
        if started { client.report("/Stopped", selection, ticks: currentTicks, paused: true) }
        player.stop()
    }
}

struct VLCSurface: UIViewRepresentable {
    let model: PlayerModel

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        Task { @MainActor in model.start(view: v) }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct PlayerView: View {
    @StateObject private var model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?

    init(selection: Selection, client: Client) {
        _model = StateObject(wrappedValue: PlayerModel(selection: selection, client: client))
    }

    private var title: String {
        let it = model.selection.item
        return it.type == "Episode" ? (it.seriesName ?? it.title) : it.title
    }

    private var sub: String? {
        let it = model.selection.item
        guard it.type == "Episode" else { return nil }
        return [it.episodeCode, it.name].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VLCSurface(model: model).ignoresSafeArea()
            if model.buffering && !model.failed {
                ProgressView().tint(.rose).scaleEffect(1.5)
            }
            if model.failed {
                Text("This stream couldn't be played. Close the player and try another one.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.textMain)
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(32)
            }
            if showControls { controls.transition(.opacity) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) { showControls.toggle() }
            scheduleHide()
        }
        .statusBarHidden(!showControls)
        .persistentSystemOverlays(.hidden)
        .onAppear { scheduleHide() }
        .onDisappear { model.stop() }
    }

    private var controls: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.65), .clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack {
                HStack(spacing: 12) {
                    Button {
                        model.stop()
                        dismiss()
                    } label: {
                        circleIcon("xmark")
                    }
                    .accessibilityLabel("Close player")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline).lineLimit(1)
                        if let sub { Text(sub).font(.caption).foregroundStyle(Color.muted).lineLimit(1) }
                    }
                    Spacer()
                    if !model.audioTracks.isEmpty || !model.subTracks.isEmpty { tracksMenu }
                }
                Spacer()
                HStack(spacing: 52) {
                    Button { model.skip(-10); scheduleHide() } label: {
                        Image(systemName: "gobackward.10").font(.system(size: 30, weight: .semibold))
                    }
                    Button { model.togglePlay(); scheduleHide() } label: {
                        Image(systemName: model.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 46, weight: .bold))
                            .frame(width: 64, height: 64)
                    }
                    Button { model.skip(10); scheduleHide() } label: {
                        Image(systemName: "goforward.10").font(.system(size: 30, weight: .semibold))
                    }
                }
                Spacer()
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(get: { Double(model.position) }, set: { model.position = Float($0) }),
                        in: 0...1,
                        onEditingChanged: { editing in
                            model.scrubbing = editing
                            if !editing { model.seek(model.position) }
                            scheduleHide()
                        }
                    )
                    .tint(.rose)
                    HStack {
                        Text(model.timeText)
                        Spacer()
                        Text(model.remainingText)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.textMain.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .foregroundStyle(Color.textMain)
        }
    }

    private var tracksMenu: some View {
        Menu {
            if !model.audioTracks.isEmpty {
                Section("Audio") {
                    ForEach(model.audioTracks) { t in
                        Button { model.setAudio(t.id) } label: {
                            if t.id == model.currentAudio { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                        }
                    }
                }
            }
            if !model.subTracks.isEmpty {
                Section("Subtitles") {
                    ForEach(model.subTracks) { t in
                        Button { model.setSub(t.id) } label: {
                            if t.id == model.currentSub { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                        }
                    }
                }
            }
        } label: {
            circleIcon("captions.bubble")
        }
        .accessibilityLabel("Audio and subtitles")
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .bold))
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled && model.playing && !model.scrubbing {
                withAnimation(.easeOut(duration: 0.25)) { showControls = false }
            }
        }
    }
}
