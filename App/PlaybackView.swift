import SwiftUI
import AVKit

@MainActor @Observable final class PlaybackModel {
    let player = AVPlayer()
    var channel: Channel
    var error: String?
    private(set) var session = PlaybackSession()
    var buffering: Bool { session.buffering }
    var hasPicture = false
    private var intentionallyPaused = false
    private var statusObservation: NSKeyValueObservation?
    private var timeObservation: NSKeyValueObservation?
    private var timeout: Task<Void, Never>?
    /// WebVTT tracks of the current item; nil hides the Subtitles control.
    private(set) var subtitles: (group: AVMediaSelectionGroup, options: [AVMediaSelectionOption])?
    private(set) var subtitlesOn = UserDefaults.standard.bool(forKey: "subtitlesOn")
    init(channel: Channel) {
        self.channel = channel
        // The viewer's On/Off choice must win over system caption defaults.
        player.appliesMediaSelectionCriteriaAutomatically = false
    }

    /// `automatic` re-tunes after a stall or failure keep the retry budget; viewer tunes reset it.
    func tune(_ channel: Channel, automatic: Bool = false) {
        stop()
        session.begin(automatic: automatic)
        let generation = session.id
        self.channel = channel
        error = nil; hasPicture = false; intentionallyPaused = false
        // Keep AVPlayer's default read-ahead: a cap below Tunarr's 4 s HLS segment length stalls on every network hiccup.
        let item = AVPlayerItem(url: channel.streamURL)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let failed = item.status == .failed
            Task { @MainActor [weak self] in
                guard let self, failed, let recovery = self.session.fail(session: generation) else { return }
                self.recover(recovery, "This channel could not play. Check your connection and try again.")
            }
        }
        timeObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self, self.session.id == generation else { return }
                switch status {
                case .playing:
                    guard !self.intentionallyPaused,
                          self.session.receive(.playing, session: generation) else { return }
                    self.timeout?.cancel(); self.timeout = nil
                case .waitingToPlayAtSpecifiedRate:
                    guard !self.intentionallyPaused,
                          self.session.receive(.waiting, session: generation) else { return }
                    self.armTimeout(generation)
                default: break
                }
            }
        }
        player.replaceCurrentItem(with: item)
        armTimeout(generation)
        player.play()
        Task { [weak self] in
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible),
                  let self, self.session.id == generation else { return }
            // AVFoundation lists a CEA-608 "CC" option for every HLS stream without CLOSED-CAPTIONS=NONE; Tunarr never sends 608.
            let options = group.options.filter { $0.mediaType == .subtitle }
            guard !options.isEmpty else { return }
            self.subtitles = (group, options)
            self.applySubtitles()
        }
    }
    func toggleSubtitles() {
        subtitlesOn.toggle()
        UserDefaults.standard.set(subtitlesOn, forKey: "subtitlesOn")
        applySubtitles()
    }
    private func applySubtitles() {
        guard let (group, options) = subtitles, let item = player.currentItem else { return }
        let index = Subtitles.option(languages: options.map { $0.extendedLanguageTag ?? $0.locale?.identifier },
                                     preferred: Locale.preferredLanguages, enabled: subtitlesOn)
        item.select(index.map { options[$0] }, in: group)
    }
    func togglePause() {
        guard error == nil else { return }
        intentionallyPaused.toggle()
        if intentionallyPaused {
            session.receive(.paused, session: session.id)
            timeout?.cancel(); timeout = nil
            player.pause()
        } else {
            session.receive(.waiting, session: session.id)
            armTimeout(session.id)
            player.play()
        }
    }
    private func armTimeout(_ generation: UUID) {
        guard timeout == nil else { return }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, let recovery = self.session.expire(session: generation) else { return }
            self.recover(recovery, "Playback is not responding. Check your connection and try again.")
        }
    }
    private func recover(_ recovery: PlaybackSession.Recovery, _ message: String) {
        if recovery == .retry { tune(channel, automatic: true) } else { fail(message) }
    }
    private func fail(_ message: String) {
        stop(); error = message
    }
    func scenePhaseChanged(_ phase: ScenePhase) {
        // Siri and other temporary overlays must keep the current stream and picture intact.
        if phase == .background { stop() }
        else if phase == .active, session.phase == .stopped, error == nil { tune(channel) }
    }
    func stop() {
        session.stop(); hasPicture = false; subtitles = nil
        timeout?.cancel(); timeout = nil
        statusObservation?.invalidate(); statusObservation = nil
        timeObservation?.invalidate(); timeObservation = nil
        player.pause(); player.replaceCurrentItem(with: nil)
    }
}

/// Full-screen video plus its info bar. Stays mounted while the guide is shown on top so the show keeps playing.
struct PlaybackView: View {
    let model: PlaybackModel
    let channels: [Channel]
    let guide: Guide?
    let guideShown: Bool
    let showGuide: () -> Void
    /// Stops the show and returns to the plain guide.
    let close: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var showInfo = false
    @FocusState private var controlsFocus: String?
    @State private var hideTask: Task<Void, Never>?
    @State private var tooltip: String?
    @State private var tooltipTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            let generation = model.session.id
            NativePlayer(player: model.player, state: model.hasPicture && model.session.phase == .playing ? "playing-\(model.channel.number)" : "buffering") {
                if model.session.id == generation { model.hasPicture = true }
            }.id(generation).ignoresSafeArea()
            if !guideShown {
                if !showInfo && model.error == nil {
                    // Invisible focus target so Select/swipes can reveal controls. A custom style is required:
                    // tvOS draws a white highlight platter over focused `.plain` buttons.
                    Button { reveal() } label: { Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity) }
                        .buttonStyle(InvisibleButtonStyle()).focusEffectDisabled()
                        .focused($controlsFocus, equals: "surface")
                        .accessibilityIdentifier("showControls")
                        .accessibilityLabel("Show channel controls")
                }
                if model.buffering {
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("\(model.session.reconnecting ? "Reconnecting to" : "Tuning") \(model.channel.name)…").font(.headline)
                    }.padding(.horizontal, 60).padding(.vertical, 40).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
                }
                if let error = model.error {
                    VStack(spacing: 24) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 64)).foregroundStyle(amber)
                        Text("Unable to play").font(.title.bold())
                        Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        HStack(spacing: 30) {
                            Button("Retry", systemImage: "arrow.clockwise") { model.tune(model.channel) }
                            Button("Guide") { close() }
                        }.padding(.top, 16)
                    }.frame(maxWidth: 900).padding(60).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 36))
                } else if showInfo {
                    overlay.transition(.opacity)
                }
            }
        }
        .onAppear { if !guideShown { reveal() } }
        .onDisappear { hideTask?.cancel(); tooltipTask?.cancel() }
        .onChange(of: controlsFocus) { _, focus in
            tooltipTask?.cancel(); tooltip = nil
            guard let focus, focus != "surface" else { return }
            tooltipTask = Task {
                do { try await Task.sleep(for: .seconds(0.8)) } catch { return }
                withAnimation(.easeOut(duration: 0.2)) { tooltip = focus }
            }
        }
        .onChange(of: guideShown) { _, shown in
            if shown { hideTask?.cancel(); showInfo = false } else { reveal() }
        }
        .onExitCommand {
            // Back hides visible controls first; a second press stops the show and returns to the guide.
            if showInfo && model.error == nil { hide() } else { close() }
        }
        .onMoveCommand { _ in reveal() }
        .onPlayPauseCommand {
            model.togglePause()
            reveal()
        }
        .onChange(of: scenePhase) { _, phase in
            model.scenePhaseChanged(phase)
        }
    }
    /// Cable-box style info banner: channel on the left, what's on to the right, controls underneath.
    private var overlay: some View {
        TimelineView(.everyMinute) { context in
            let current = guide?.now(on: model.channel, at: context.date)
            VStack(alignment: .leading, spacing: 84) {  // Room for control tooltips.
                Spacer()
                HStack(alignment: .top, spacing: 48) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.channel.number).font(.system(size: 88, weight: .heavy).monospacedDigit()).foregroundStyle(amber)
                        Text(model.channel.name).font(.system(size: 28, weight: .semibold)).foregroundStyle(.secondary).lineLimit(2)
                    }.frame(width: 280, alignment: .leading)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(current?.title ?? "No program information").font(.system(size: 56, weight: .bold)).lineLimit(1)
                        if let current {
                            Text("\(current.start.clock) – \(current.end.clock)").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                            if !current.summary.isEmpty {
                                Text(current.summary).font(.callout).lineLimit(3).frame(maxWidth: 1200, alignment: .leading)
                            }
                        }
                        if model.session.phase == .paused {
                            Label("Paused", systemImage: "pause.fill").font(.callout.bold()).foregroundStyle(amber)
                        }
                    }
                }
                HStack(spacing: 30) {
                    control("Previous channel", "chevron.left", id: "previousChannel", focus: "previous") { surf(-1) }
                    control("Guide", "square.grid.2x2.fill", id: "backToGuide", focus: "guide") { showGuide() }
                    // Always present so the row doesn't shift when the track list loads; dimmed until a track exists.
                    control(model.subtitlesOn ? "Subtitles On" : "Subtitles Off",
                            model.subtitlesOn ? "captions.bubble.fill" : "captions.bubble", id: "subtitles", focus: "subtitles") {
                        model.toggleSubtitles(); reveal()
                    }.disabled(model.subtitles == nil)
                    control("Next channel", "chevron.right", id: "nextChannel", focus: "next") { surf(1) }
                }.padding(.leading, 328)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                VStack(spacing: 0) {
                    Spacer()
                    // Short fade, then near-solid behind the text so bright scenes stay readable.
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.85), location: 0.35),
                                           .init(color: .black.opacity(0.95), location: 1)],
                                   startPoint: .top, endPoint: .bottom).frame(height: 720)
                }.ignoresSafeArea().allowsHitTesting(false)
            }
        }
    }
    /// Icon-only control; its name appears above it once focus rests on it.
    private func control(_ title: String, _ systemImage: String, id: String, focus: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: systemImage).labelStyle(.iconOnly) }
            .accessibilityIdentifier(id).focused($controlsFocus, equals: focus)
            .overlay(alignment: .top) {
                if tooltip == focus {
                    Text(title).font(.callout.bold()).fixedSize().padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule()).offset(y: -66).transition(.opacity)
                }
            }
    }
    private func surf(_ step: Int) {
        guard !channels.isEmpty, let index = channels.firstIndex(where: { $0.id == model.channel.id }) else { return }
        model.tune(channels[(index + step + channels.count) % channels.count]); reveal()
    }
    private func reveal() {
        if !showInfo { withAnimation(.easeOut(duration: 0.2)) { showInfo = true }; controlsFocus = "guide" }
        hideTask?.cancel()
        hideTask = Task {
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            hide()
        }
    }
    private func hide() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) { showInfo = false }
        controlsFocus = "surface"
    }
}

private struct InvisibleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.contentShape(Rectangle()) }
}

// AVPlayerLayer avoids AVPlayerViewController taking over tvOS focus/modal accessibility.
private struct NativePlayer: UIViewRepresentable {
    let player: AVPlayer
    let state: String
    let onReady: () -> Void
    func makeUIView(context: Context) -> PlayerSurface {
        let view = PlayerSurface()
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "liveVideo"
        view.accessibilityLabel = "Live video"
        view.videoLayer.videoGravity = .resizeAspect
        view.videoLayer.player = player
        view.onReady = onReady
        view.observeReadiness()
        return view
    }
    func updateUIView(_ view: PlayerSurface, context: Context) {
        view.videoLayer.player = player
        view.accessibilityValue = state
        view.onReady = onReady
    }
    static func dismantleUIView(_ view: PlayerSurface, coordinator: ()) {
        view.observation?.invalidate()
        view.videoLayer.player = nil
        view.onReady = nil
    }
}

private final class PlayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var onReady: (() -> Void)?
    var observation: NSKeyValueObservation?
    func observeReadiness() {
        observation = videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            if ready { Task { @MainActor [weak self] in self?.onReady?() } }
        }
    }
}
