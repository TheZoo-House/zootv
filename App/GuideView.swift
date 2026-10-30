import SwiftUI

let amber = Color(red: 1.0, green: 0.71, blue: 0.29)
let coral = Color(red: 1.0, green: 0.37, blue: 0.36)
private let night = Color(red: 0.04, green: 0.035, blue: 0.09)

/// Deep violet backdrop with a warm glow, shared by every full-screen surface except video.
struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.09, green: 0.06, blue: 0.18), night], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.42, green: 0.22, blue: 0.85).opacity(0.35), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 1100)
            RadialGradient(colors: [amber.opacity(0.10), .clear], center: .bottomLeading, startRadius: 0, endRadius: 900)
        }.ignoresSafeArea()
    }
}

struct GuideView: View {
    @State private var store = GuideStore()
    @State private var scroll = GridScroll()
    @State private var pendingChannel: Channel?
    /// Channel a `zootv://play` link asked for; honoured once the guide knows it.
    @State private var linkedChannel: String?
    /// The show keeps playing underneath while the guide is open over it.
    @State private var playback: PlaybackModel?
    @State private var guideOverShow = false
    @FocusState private var focusedChannel: String?
    /// What the info panel describes. Tiles report focus into it so moving focus doesn't rebuild the grid.
    @State private var selection = GuideSelection()
    @Environment(\.scenePhase) private var scenePhase
    private let window: TimeInterval = 2 * 60 * 60

    var body: some View {
        ZStack {
            if let playback {
                PlaybackView(model: playback, channels: store.guide?.channels ?? [], guide: store.guide,
                             guideShown: guideOverShow, showGuide: openGuide, close: closePlayback)
            }
            if playback == nil || guideOverShow {
                grid.onExitCommand(perform: playback == nil ? nil : { guideOverShow = false })
            }
        }
        .task {
            while !Task.isCancelled {
                if scenePhase == .active {
                    let firstLoad = store.guide == nil
                    await store.refresh()
                    if firstLoad { focusedChannel = store.guide?.channels.first?.id }
                }
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
        .onOpenURL { url in linkedChannel = DeepLink.channelID(from: url); followLink() }
        .onChange(of: store.guide?.channels) { _, _ in followLink() }
        .sheet(item: $store.detail, onDismiss: {
            if let channel = pendingChannel { pendingChannel = nil; watch(channel) }
        }) { programme in
            VStack(alignment: .leading, spacing: 24) {
                Text(programme.timingLabel(at: Date())).font(.caption.bold()).tracking(3).foregroundStyle(amber)
                Text(programme.title).font(.system(size: 64, weight: .bold))
                Text("\(programme.start.formatted(.dateTime.weekday(.wide).hour().minute())) – \(programme.end.clock)")
                    .font(.title3).foregroundStyle(.secondary)
                Text(programme.summary.isEmpty ? "No description is available for this program." : programme.summary)
                    .lineLimit(6).frame(maxWidth: 1100, alignment: .leading)
                Text(programme.end <= Date() ? "This program has ended. Catch-up playback is not available." : "This is scheduled live TV. Future programs cannot be started early.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 30) {
                    Button("Watch this channel live", systemImage: "play.fill") {
                        pendingChannel = store.guide?.channels.first { $0.id == programme.channelID }
                        store.detail = nil
                    }
                    Button("Back to guide") { store.detail = nil }
                }.padding(.top, 20)
            }.padding(70)
        }
    }

    private var grid: some View {
        TimelineView(.periodic(from: .now, by: 10)) { context in
            VStack(alignment: .leading, spacing: 30) {
                header(context.date)
                if let guide = store.guide {
                    guideBody(guide, now: context.date)
                } else if let error = store.error {
                    Spacer()
                    ContentUnavailableView {
                        Label("ZooTV is out of reach", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Try again") { Task { await store.refresh() } }.accessibilityIdentifier("retryGuide")
                    }
                    Spacer()
                } else {
                    Spacer()
                    ProgressView("Finding your channels…").frame(maxWidth: .infinity)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                // Dim, don't hide, the show playing underneath.
                if playback == nil { Backdrop() } else { Color.black.opacity(0.9).ignoresSafeArea() }
            }
        }
    }

    private func watch(_ channel: Channel) {
        guideOverShow = false
        if let playback {
            if playback.channel.id != channel.id || playback.error != nil { playback.tune(channel) }
        } else {
            let model = PlaybackModel(channel: channel)
            playback = model
            model.tune(channel)
        }
    }

    /// Unknown IDs just leave the guide showing.
    private func followLink() {
        guard let id = linkedChannel, let guide = store.guide else { return }
        linkedChannel = nil
        if let channel = guide.channels.first(where: { $0.id == id }) { store.detail = nil; watch(channel) }
    }

    private func closePlayback() {
        let channel = playback?.channel.id
        playback?.stop(); playback = nil; guideOverShow = false
        focusedChannel = channel
    }

    private func openGuide() {
        guideOverShow = true
        focusedChannel = playback?.channel.id
    }

    private func header(_ now: Date) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 18) {
                Image(systemName: "play.tv.fill").font(.system(size: 40, weight: .semibold))
                Text("ZooTV").font(.system(size: 46, weight: .black))
            }.foregroundStyle(LinearGradient(colors: [amber, coral], startPoint: .leading, endPoint: .trailing))
            Spacer()
            if store.guide != nil, let error = store.error {
                Label("Showing the last loaded guide. \(error)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(amber).lineLimit(1).padding(.horizontal, 40)
                Spacer()
            }
            VStack(alignment: .trailing, spacing: 0) {
                Text(now.clock).font(.system(size: 40, weight: .semibold).monospacedDigit())
                Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func guideBody(_ guide: Guide, now: Date) -> some View {
        // x = 0 is "now", so rows slide left as time passes, like a DVR guide; the rest scrolls horizontally.
        let lastEnd = guide.programmes.map(\.end).max() ?? now
        let firstTick = ceil(now.timeIntervalSince1970 / 1800) * 1800
        let ticks = stride(from: firstTick, to: lastEnd.timeIntervalSince1970, by: 1800).map { Date(timeIntervalSince1970: $0) }
        return VStack(alignment: .leading, spacing: 24) {
            InfoPanel(guide: guide, now: now, selection: selection)
            GeometryReader { geometry in
                let labelWidth: CGFloat = 250, inset: CGFloat = 20, rowHeight: CGFloat = 124
                let viewport = max(400, geometry.size.width - labelWidth)
                // Two hours fill the visible width.
                let perSecond = (viewport - inset) / window
                let contentWidth = max(viewport, lastEnd.timeIntervalSince(now) * perSecond + inset * 2)
                VStack(alignment: .leading, spacing: 10) {
                    TimeRuler(scroll: scroll, ticks: ticks, now: now, perSecond: perSecond, inset: inset)
                        .frame(width: viewport, height: 40, alignment: .leading).clipped()
                        .padding(.leading, labelWidth)
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            VStack(spacing: 14) {
                                ForEach(guide.channels) { channel in
                                    Button { watch(channel) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(channel.number).font(.system(size: 30, weight: .heavy).monospacedDigit())
                                                .foregroundStyle(.tint)
                                            Text(channel.name).font(.system(size: 24, weight: .semibold)).lineLimit(2)
                                        }
                                        .padding(.horizontal, 24)
                                        .frame(width: labelWidth, height: rowHeight, alignment: .leading)
                                    }
                                    .buttonStyle(TileStyle(fill: .white.opacity(0.09)) { selection.focus(channel: channel.id) })
                                    .focused($focusedChannel, equals: channel.id)
                                    .accessibilityIdentifier("channel-\(channel.number)")
                                    .accessibilityLabel("\(channel.number), \(channel.name), Watch live")
                                }
                            }
                            // One horizontal scroller for every row keeps them in step, like a real guide.
                            ScrollView(.horizontal) {
                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(guide.channels) { channel in
                                        GuideRow(channel: channel, schedule: guide.visible(on: channel, from: now, to: lastEnd), now: now,
                                                 perSecond: perSecond, height: rowHeight, viewport: viewport - inset * 2,
                                                 selection: selection, scroll: scroll) { programme in
                                            if programme.isLive(at: Date()) { watch(channel) } else { store.detail = programme }
                                        }
                                        .equatable()
                                        .frame(width: contentWidth - inset * 2, height: rowHeight, alignment: .leading)
                                        .id(channel.id)
                                    }
                                }
                                // Rows double as scroll targets so Back can scroll to now horizontally only.
                                .scrollTargetLayout()
                                .padding(.horizontal, inset)
                                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("grid")).minX } action: { scroll.x = -$0 }
                            }
                            .scrollPosition(id: $scroll.row, anchor: .leading)
                            .coordinateSpace(.named("grid"))
                            .frame(width: viewport)
                        }
                        // Room for the focused tile's scale and shadow inside the clipped scroll area.
                        .padding(.vertical, 20).padding(.leading, 30)
                    }.padding(.leading, -30)
                }
                // Back first returns a scrolled guide to now, then to the show; otherwise tvOS handles it.
                .onExitCommand(perform: !scroll.scrolled && playback == nil ? nil : {
                    if scroll.scrolled { backToNow() } else { guideOverShow = false }
                })
            }
        }
    }

    private func backToNow() {
        // Every row starts at now; pick one that differs from the current value so the change registers.
        let row = store.guide?.channels.first { $0.id != scroll.row }?.id
        withAnimation(.easeInOut(duration: 0.3)) { scroll.row = row }
        focusedChannel = selection.channelID
    }
}

/// One channel's programmes. Equatable so focus changes elsewhere in the guide skip rebuilding its tiles.
private struct GuideRow: View, Equatable {
    let channel: Channel
    let schedule: [Programme]
    let now: Date
    let perSecond: CGFloat
    let height: CGFloat
    let viewport: CGFloat
    let selection: GuideSelection
    let scroll: GridScroll
    let open: (Programme) -> Void
    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.channel == b.channel && a.schedule == b.schedule && a.now == b.now && a.perSecond == b.perSecond
            && a.height == b.height && a.viewport == b.viewport
    }
    var body: some View {
        // Only build tiles from a little behind the screen to a few screens ahead; rebuilt as scrolling moves on.
        let low = CGFloat(scroll.chunk - 2) * 1000, high = CGFloat(scroll.chunk + 5) * 1000
        ZStack(alignment: .leading) {
            if schedule.isEmpty {
                Text("No schedule published").font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 24).frame(width: viewport, height: height, alignment: .leading)
                    .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
            }
            ForEach(schedule) { programme in
                let begin = max(programme.start, now)
                let left = begin.timeIntervalSince(now) * perSecond
                let width = programme.end.timeIntervalSince(begin) * perSecond - 10
                if left < high && left + width > low {
                    let live = programme.isLive(at: now)
                    // tvOS centres a focused view wider than the screen, so only the start of a long
                    // programme takes focus; the tile's background still spans its full length.
                    let focusWidth = max(1, min(width, viewport * 0.75))
                    Button { open(programme) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(programme.title).font(.system(size: 26, weight: .semibold)).lineLimit(1)
                            Text("\(programme.start.clock) – \(programme.end.clock)")
                                .font(.system(size: 20).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.horizontal, 22).padding(.vertical, 20)
                        .frame(width: focusWidth, height: height, alignment: .topLeading)
                    }
                    .buttonStyle(TileStyle(fill: .white.opacity(live ? 0.12 : 0.05), extent: max(1, width), grows: false) {
                        selection.focus(programme: programme)
                    })
                    .accessibilityIdentifier("\(live ? "live" : "future")-\(channel.number)-\(programme.start.timeIntervalSince1970)")
                    .accessibilityLabel("\(programme.title), \(programme.start.clock) to \(programme.end.clock)")
                    .padding(.leading, left)
                }
            }
        }
    }
}

/// The programme (or channel) the info panel describes.
@MainActor @Observable final class GuideSelection {
    private(set) var programme: Programme?
    private(set) var channelID: String?
    func focus(programme: Programme) { self.programme = programme; channelID = programme.channelID }
    func focus(channel: String) { programme = nil; channelID = channel }
}

/// Details of the focused programme above the grid; a focused channel shows what's on it now.
private struct InfoPanel: View {
    let guide: Guide
    let now: Date
    let selection: GuideSelection
    var body: some View {
        // Fixed height so the grid does not jump as focus moves between programmes.
        VStack(alignment: .leading, spacing: 8) {
            if let programme = selection.programme ?? guide.channels.first(where: { $0.id == selection.channelID })
                .flatMap({ guide.now(on: $0, at: now) }) {
                Text(programme.timingLabel(at: now)).font(.caption.bold()).tracking(3).foregroundStyle(amber)
                Text(programme.title).font(.system(size: 44, weight: .bold)).lineLimit(1)
                Text("\(guide.channels.first { $0.id == programme.channelID }?.name ?? "") · \(programme.start.clock) – \(programme.end.clock)")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                if !programme.summary.isEmpty {
                    Text(programme.summary).font(.callout).lineLimit(2)
                }
            }
        }.frame(maxWidth: .infinity, minHeight: 180, maxHeight: 180, alignment: .bottomLeading)
    }
}

/// Horizontal scroll position of the guide grid. Kept outside view state so scrolling only redraws the time ruler.
@MainActor @Observable final class GridScroll {
    var x: CGFloat = 0 {
        didSet {
            // Past the grid's 20-point leading inset, which Back-to-now leaves scrolled away.
            if (x > 30) != scrolled { scrolled = x > 30 }
            if Int(x / 1000) != chunk { chunk = Int(x / 1000) }
        }
    }
    private(set) var scrolled = false
    /// Which 1000-point stretch is on screen; rows only build tiles near it.
    private(set) var chunk = 0
    /// Row at the leading edge, bound to the grid's scroll position.
    var row: String?
}

/// Half-hour labels that follow the grid's horizontal scroll.
private struct TimeRuler: View {
    let scroll: GridScroll
    let ticks: [Date]
    let now: Date
    let perSecond: CGFloat
    let inset: CGFloat
    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(ticks, id: \.self) { tick in
                HStack(spacing: 10) {
                    Capsule().fill(.white.opacity(0.25)).frame(width: 2, height: 22)
                    Text(tick.clock).font(.callout.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
                }.offset(x: inset + tick.timeIntervalSince(now) * perSecond - scroll.x)
            }
        }
    }
}

/// Glassy tile that turns into a white platter with dark text when focused, like native tvOS cards.
struct TileStyle: ButtonStyle {
    var fill: Color
    /// Width the tile's background spans when it is wider than the focusable label.
    var extent: CGFloat?
    /// Guide tiles sit edge to edge, so they highlight without growing into their neighbours.
    var grows = true
    var onFocus: () -> Void = {}
    func makeBody(configuration: Configuration) -> some View {
        Tile(configuration: configuration, fill: fill, extent: extent, grows: grows, onFocus: onFocus)
    }
    private struct Tile: View {
        let configuration: Configuration
        let fill: Color
        let extent: CGFloat?
        let grows: Bool
        let onFocus: () -> Void
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .foregroundStyle(focused ? night : .white)
                .tint(focused ? coral : amber)
                .background(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 16).fill(focused ? AnyShapeStyle(.white) : AnyShapeStyle(fill))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(focused ? 0 : 0.08)))
                        .frame(width: extent)
                }
                .scaleEffect(configuration.isPressed ? 0.97 : focused && grows ? 1.05 : 1)
                .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: 24, y: 14)
                .zIndex(focused ? 1 : 0)
                .animation(.easeOut(duration: 0.18), value: focused)
                .onChange(of: focused) { _, focused in if focused { onFocus() } }
        }
    }
}
