import SwiftUI

/// Full-screen video player with controls overlay, track pickers, and auto-hide.
///
/// Present via `.fullScreenCover`. Playback starts on first appearance so the
/// underlying render surface is attached before the engine begins loading.
struct PlayerView: View {
    @Environment(PlexService.self) private var plexService
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(UserPreferences.self) private var preferences
    @State private var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    private let playbackSource: PlaybackSource
    private let mediaDetails: PlexMediaDetails?
    private let debugInfo: PlaybackDebugInfo?

    init(
        engine: any PlaybackEngine,
        playbackSource: PlaybackSource,
        mediaDetails: PlexMediaDetails? = nil,
        debugInfo: PlaybackDebugInfo? = nil
    ) {
        _viewModel = State(
            initialValue: PlayerViewModel(
                engine: engine,
                markers: mediaDetails?.markers ?? []
            )
        )
        self.playbackSource = playbackSource
        self.mediaDetails = mediaDetails
        self.debugInfo = debugInfo
    }

    var body: some View {
        @Bindable var vm = viewModel
        let upNextPresentation = playback.upNextPresentation

        ZStack {
            // Black letterbox behind video
            Color.black.ignoresSafeArea()

            // Video surface
            viewModel.engineView
                .ignoresSafeArea()

            if let upNextPresentation {
                upNextOverlay(upNextPresentation)
                    .transition(.opacity)
            } else {
                interactionOverlay

                // Buffering spinner
                if viewModel.shouldShowBufferingIndicator {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }

                // Error overlay
                if let error = viewModel.playbackError {
                    errorOverlay(error)
                }

                if preferences.playerDebugOverlayEnabled,
                   let debugInfo,
                   viewModel.playbackError == nil {
                    debugOverlay(debugInfo)
                }

                if let marker = viewModel.activeSkipMarker,
                   viewModel.playbackError == nil {
                    skipMarkerOverlay(marker)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                // Controls overlay
                if viewModel.showControls, viewModel.playbackError == nil {
                    controlsOverlay
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showControls)
        .animation(.easeInOut(duration: 0.2), value: viewModel.activeSkipMarker?.id)
        .animation(.easeInOut(duration: 0.25), value: upNextPresentation?.episode.ratingKey)
        .duskStatusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            viewModel.configureAutomaticTrackSelection(
                preferences: preferences,
                part: debugInfo?.part ?? mediaDetails?.media.first?.parts.first
            )
            // Start playback only after the full-screen player view exists.
            viewModel.startPlaybackIfNeeded(source: playbackSource)
        }
        .onDisappear { viewModel.cleanup() }
        .sheet(isPresented: $vm.showSubtitlePicker) { subtitlePicker }
        .sheet(isPresented: $vm.showAudioPicker) { audioPicker }
    }

    private var interactionOverlay: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                interactionZone(
                    seekOffset: -preferences.playerDoubleTapBackwardInterval.timeInterval
                )
                interactionZone(
                    seekOffset: preferences.playerDoubleTapForwardInterval.timeInterval
                )
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func interactionZone(seekOffset: TimeInterval) -> some View {
        #if os(tvOS)
        Color.clear
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture { viewModel.toggleControls() }
        #else
        if preferences.playerDoubleTapSeekEnabled {
            Color.clear
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    TapGesture(count: 2)
                        .onEnded { viewModel.seek(by: seekOffset) }
                        .exclusively(
                            before: TapGesture()
                                .onEnded { viewModel.toggleControls() }
                        )
                )
        } else {
            Color.clear
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture { viewModel.toggleControls() }
        }
        #endif
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        GeometryReader { geometry in
            let showsTrackLabels = geometry.size.width > geometry.size.height

            ZStack {
                // Gradient scrim (extends behind safe area)
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(0.7), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 120)

                    Spacer()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 160)
                }
                .ignoresSafeArea()

                // Actual controls (respect safe area)
                VStack {
                    topBar
                    Spacer()
                    centerControls
                    Spacer()
                    bottomBar(showsTrackLabels: showsTrackLabels)
                }
                .padding()
            }
        }
    }

    // MARK: - Debug Overlay

    private func debugOverlay(_ debugInfo: PlaybackDebugInfo) -> some View {
        GeometryReader { geometry in
            VStack {
                HStack {
                    Spacer()
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 110), spacing: 12, alignment: .top),
                            GridItem(.flexible(minimum: 110), spacing: 12, alignment: .top),
                        ],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(debugEntries(for: debugInfo)) { entry in
                            debugRow(entry.label, entry.value)
                        }
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    }
                    .frame(width: 288, alignment: .leading)
                }
                Spacer()
            }
            .padding(.top, max(16, geometry.safeAreaInsets.top + 8))
            .padding(.horizontal, 16)
        }
        .allowsHitTesting(false)
    }

    private func debugEntries(for debugInfo: PlaybackDebugInfo) -> [DebugOverlayEntry] {
        [
            DebugOverlayEntry(label: "Engine", value: debugInfo.engineLabel),
            DebugOverlayEntry(label: "Mode", value: debugInfo.decisionLabel),
            DebugOverlayEntry(label: "Transcode", value: debugInfo.transcodeLabel),
            DebugOverlayEntry(label: "Container", value: debugInfo.containerLabel),
            DebugOverlayEntry(label: "Bitrate", value: debugInfo.bitrateLabel),
            DebugOverlayEntry(label: "Video", value: debugInfo.videoLabel),
            DebugOverlayEntry(label: "Audio", value: debugInfo.audioLabel),
            DebugOverlayEntry(label: "Resolution", value: debugInfo.resolutionLabel),
            DebugOverlayEntry(label: "File", value: debugInfo.fileSizeLabel),
            DebugOverlayEntry(label: "Subtitles", value: debugInfo.subtitleLabel),
            DebugOverlayEntry(label: "State", value: debugStateLabel),
        ]
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.white)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var debugStateLabel: String {
        let stateText: String
        switch viewModel.state {
        case .idle: stateText = "Idle"
        case .loading: stateText = "Loading"
        case .playing: stateText = "Playing"
        case .paused: stateText = "Paused"
        case .stopped: stateText = "Stopped"
        case .error: stateText = "Error"
        }

        if viewModel.isBuffering {
            return "\(stateText) / Buffering"
        }
        return stateText
    }

    private struct DebugOverlayEntry: Identifiable {
        let label: String
        let value: String

        var id: String { label }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                viewModel.cleanup()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }

            if let header = mediaHeader {
                mediaHeaderView(header)
            }

            Spacer()
        }
    }

    private func mediaHeaderView(_ header: PlayerMediaHeader) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(header.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let secondaryTitle = header.secondaryTitle {
                Text(secondaryTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }

            if let subtitle = header.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 2)
    }

    private var mediaHeader: PlayerMediaHeader? {
        guard let mediaDetails else { return nil }

        if mediaDetails.type == .episode {
            let title = mediaDetails.grandparentTitle ?? mediaDetails.title
            let secondaryTitle = mediaDetails.grandparentTitle == nil ? nil : mediaDetails.title
            let subtitle = episodeContextSubtitle(
                season: mediaDetails.parentIndex,
                episode: mediaDetails.index
            )

            return PlayerMediaHeader(
                title: title,
                secondaryTitle: secondaryTitle,
                subtitle: subtitle
            )
        }

        return PlayerMediaHeader(
            title: mediaDetails.title,
            secondaryTitle: nil,
            subtitle: mediaDetails.year.map(String.init)
        )
    }

    private func episodeContextSubtitle(season: Int?, episode: Int?) -> String? {
        switch (season, episode) {
        case let (season?, episode?):
            return "Season \(season) · Episode \(episode)"
        case let (season?, nil):
            return "Season \(season)"
        case let (nil, episode?):
            return "Episode \(episode)"
        default:
            return nil
        }
    }

    private struct PlayerMediaHeader {
        let title: String
        let secondaryTitle: String?
        let subtitle: String?
    }

    // MARK: - Up Next

    private func upNextOverlay(_ presentation: UpNextPresentation) -> some View {
        GeometryReader { geometry in
            let metrics = UpNextLayoutMetrics.make(for: geometry)

            ZStack {
                upNextBackground

                upNextPanel(presentation, metrics: metrics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, metrics.outerPadding)
                    .padding(.top, max(geometry.safeAreaInsets.top + 16, 20))
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom + 16, 20))
            }
        }
        .ignoresSafeArea()
    }

    private var upNextBackground: some View {
        ZStack {
            Color.black

            LinearGradient(
                colors: [
                    Color.duskSurface.opacity(0.28),
                    Color.black.opacity(0.88),
                    Color.black,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.duskAccent.opacity(0.18),
                    Color.clear,
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }

    private func upNextPanel(_ presentation: UpNextPresentation, metrics: UpNextLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("UP NEXT")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(Color.duskAccent)

                    if let showTitle = presentation.episode.grandparentTitle {
                        Text(showTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .duskSuppressTVOSButtonChrome()
                .duskTVOSFocusEffectShape(Circle())
            }

            if metrics.usesVerticalLayout {
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    upNextPreviewCard(presentation, metrics: metrics)
                    upNextDetails(presentation, metrics: metrics)
                }
            } else {
                HStack(alignment: .top, spacing: metrics.contentSpacing) {
                    upNextPreviewCard(presentation, metrics: metrics)
                    upNextDetails(presentation, metrics: metrics)
                }
            }
        }
        .padding(metrics.panelPadding)
        .frame(width: metrics.panelWidth, height: metrics.panelHeight, alignment: .topLeading)
    }

    private func upNextPreviewCard(_ presentation: UpNextPresentation, metrics: UpNextLayoutMetrics) -> some View {
        let thumbnailURL = upNextThumbnailURL(for: presentation)

        return ZStack(alignment: .bottomLeading) {
            if let thumbnailURL {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Color.duskSurface
                    }
                }
            } else {
                Color.duskSurface
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                if let subtitle = upNextEpisodeContext(for: presentation.episode) {
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
            }
            .padding(12)

            Button {
                playback.playUpNextNow()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        }
                        .frame(width: metrics.playButtonSize, height: metrics.playButtonSize)

                    if presentation.isStarting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: metrics.playIconSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .offset(x: 2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .disabled(presentation.isStarting)
            .duskSuppressTVOSButtonChrome()
            .duskTVOSFocusEffectShape(Circle())
        }
        .frame(width: metrics.previewWidth, height: metrics.previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 10)
    }

    private func upNextDetails(_ presentation: UpNextPresentation, metrics: UpNextLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(presentation.episode.title)
                .font(metrics.titleFont)
                .foregroundStyle(.white)
                .lineLimit(metrics.titleLineLimit)

            if let metadata = upNextMetadata(for: presentation.episode) {
                Text(metadata)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)
            }

            if presentation.shouldAutoplay,
               let countdownLabel = upNextCountdownLabel(for: presentation) {
                upNextCountdownCard(label: countdownLabel, progress: presentation.autoplayProgress)
            } else {
                Text("Playback finished. Select the next episode when you're ready.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let summary = presentation.episode.summary,
               !summary.isEmpty {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.86))
                    .lineSpacing(4)
                    .lineLimit(metrics.summaryLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage = presentation.errorMessage {
                Text(errorMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.duskAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func upNextCountdownCard(label: String, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.duskAccent)

                Text(label)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))

                    Capsule()
                        .fill(Color.duskAccent)
                        .frame(width: geometry.size.width * max(0, min(progress ?? 0, 1)))
                        .animation(.linear(duration: 1), value: progress ?? 0)
                }
            }
            .frame(height: 6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func upNextThumbnailURL(for presentation: UpNextPresentation) -> URL? {
        plexService.imageURL(
            for: presentation.episode.thumb ?? presentation.episode.art ?? presentation.episode.grandparentThumb,
            width: 1280,
            height: 720
        )
    }

    private func upNextMetadata(for episode: PlexEpisode) -> String? {
        let parts = [
            upNextEpisodeContext(for: episode),
            formattedDuration(milliseconds: episode.duration),
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func upNextEpisodeContext(for episode: PlexEpisode) -> String? {
        switch (episode.parentIndex, episode.index) {
        case let (season?, episode?):
            return "Season \(season) · Episode \(episode)"
        case let (season?, nil):
            return "Season \(season)"
        case let (nil, episode?):
            return "Episode \(episode)"
        default:
            return nil
        }
    }

    private func upNextCountdownLabel(for presentation: UpNextPresentation) -> String? {
        guard let secondsRemaining = presentation.secondsRemaining else { return nil }
        return "Continues in \(secondsRemaining)s"
    }

    private func formattedDuration(milliseconds: Int?) -> String? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        let totalMinutes = milliseconds / 60_000
        return "\(totalMinutes) min"
    }

    private struct UpNextLayoutMetrics {
        let outerPadding: CGFloat
        let panelWidth: CGFloat
        let panelHeight: CGFloat
        let panelPadding: CGFloat
        let contentSpacing: CGFloat
        let sectionSpacing: CGFloat
        let previewWidth: CGFloat
        let previewHeight: CGFloat
        let usesVerticalLayout: Bool
        let titleFont: Font
        let titleLineLimit: Int
        let summaryLineLimit: Int
        let playButtonSize: CGFloat
        let playIconSize: CGFloat

        static func make(for geometry: GeometryProxy) -> Self {
            let size = geometry.size
            let outerPadding: CGFloat = size.width < 500 ? 16 : 28
            let safeHeight = size.height - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom - 40
            let panelWidth = min(size.width - outerPadding * 2, size.width < 500 ? 680 : 860)
            let panelHeight = min(size.width < 500 ? 340 : 400, safeHeight)
            let panelPadding: CGFloat = size.width < 500 ? 18 : 24
            let contentSpacing: CGFloat = size.width < 500 ? 16 : 24
            let sectionSpacing: CGFloat = size.width < 500 ? 16 : 20
            let previewWidth = min(max(panelWidth * (size.width < 500 ? 0.3 : 0.28), 112), size.width < 500 ? 136 : 220)
            let previewHeight = previewWidth * 9.0 / 16.0
            let remainingWidth = panelWidth - (panelPadding * 2) - previewWidth - contentSpacing
            let usesVerticalLayout = remainingWidth < 210

            return Self(
                outerPadding: outerPadding,
                panelWidth: panelWidth,
                panelHeight: panelHeight,
                panelPadding: panelPadding,
                contentSpacing: contentSpacing,
                sectionSpacing: sectionSpacing,
                previewWidth: previewWidth,
                previewHeight: previewHeight,
                usesVerticalLayout: usesVerticalLayout,
                titleFont: size.width < 500 ? .title2.weight(.bold) : .largeTitle.weight(.bold),
                titleLineLimit: size.width < 500 ? 2 : 3,
                summaryLineLimit: size.width < 500 ? 3 : 4,
                playButtonSize: size.width < 500 ? 54 : 64,
                playIconSize: size.width < 500 ? 20 : 24
            )
        }
    }

    // MARK: - Skip Marker Overlay

    private func skipMarkerOverlay(_ marker: PlexMarker) -> some View {
        GeometryReader { geometry in
            VStack {
                Spacer()

                HStack {
                    Spacer()
                    Button {
                        viewModel.skipActiveMarker()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: marker.isCredits ? "forward.end.fill" : "chevron.forward.2")
                                .font(.callout.weight(.semibold))

                            Text(marker.skipButtonTitle ?? "Skip")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                        .opacity(0.92)
                    }
                    .duskSuppressTVOSButtonChrome()
                    .duskTVOSFocusEffectShape(Capsule())
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, max(geometry.safeAreaInsets.bottom + skipMarkerBottomInset, 24))
        }
        .ignoresSafeArea()
    }

    private var skipMarkerBottomInset: CGFloat {
        viewModel.showControls ? 124 : 36
    }

    // MARK: - Center Controls

    private var centerControls: some View {
        HStack {
            Spacer()
            Button { viewModel.togglePlayPause() } label: {
                Image(systemName: viewModel.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
        }
    }

    // MARK: - Bottom Bar

    private func bottomBar(showsTrackLabels: Bool) -> some View {
        VStack(spacing: 8) {
            seekBar

            HStack {
                Text(viewModel.formattedTime)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))

                Text("/")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))

                Text(viewModel.formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                Button { viewModel.showSubtitlePicker = true } label: {
                    trackButtonLabel(
                        icon: viewModel.selectedSubtitleTrack == nil
                            ? "captions.bubble"
                            : "captions.bubble.fill",
                        title: subtitleControlTitle,
                        showsTitle: showsTrackLabels,
                        isEnabled: !viewModel.subtitleTracks.isEmpty
                    )
                }
                .disabled(viewModel.subtitleTracks.isEmpty)

                Button { viewModel.showAudioPicker = true } label: {
                    trackButtonLabel(
                        icon: "speaker.wave.2",
                        title: audioControlTitle,
                        showsTitle: showsTrackLabels,
                        isEnabled: !viewModel.audioTracks.isEmpty
                    )
                }
                .disabled(viewModel.audioTracks.isEmpty)
            }
        }
    }

    private var subtitleControlTitle: String {
        if let selectedSubtitleTrack = viewModel.selectedSubtitleTrack {
            return selectedSubtitleTrack.displayTitle
        }

        return viewModel.state == .loading ? "..." : "-"
    }

    private var audioControlTitle: String {
        if let selectedAudioTrack = viewModel.selectedAudioTrack {
            return selectedAudioTrack.displayTitle
        }

        return viewModel.state == .loading ? "..." : "-"
    }

    private func trackButtonLabel(
        icon: String,
        title: String,
        showsTitle: Bool,
        isEnabled: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)

            if showsTitle {
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.white.opacity(isEnabled ? 1.0 : 0.72))
        .padding(.horizontal, 10)
        .frame(width: showsTitle ? 132 : 36, height: 36, alignment: .leading)
        .background(.white.opacity(0.12), in: Capsule())
    }

    // MARK: - Seek Bar

    private var seekBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let progress = viewModel.duration > 0
                ? viewModel.displayPosition / viewModel.duration
                : 0
            let seekTrack = ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.3))
                    .frame(height: 4)

                // Filled track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.duskAccent)
                    .frame(width: max(0, width * progress), height: 4)

                // Thumb
                Circle()
                    .fill(Color.duskAccent)
                    .frame(
                        width: viewModel.isScrubbing ? 16 : 12,
                        height: viewModel.isScrubbing ? 16 : 12
                    )
                    .offset(x: thumbOffset(progress: progress, trackWidth: width))
                    .animation(.easeOut(duration: 0.15), value: viewModel.isScrubbing)
            }
            .frame(height: 32) // tall hit area
            .contentShape(Rectangle())

            #if os(tvOS)
            seekTrack
            #else
            seekTrack.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !viewModel.isScrubbing {
                            viewModel.beginScrub()
                        }
                        let fraction = max(0, min(1, value.location.x / width))
                        viewModel.updateScrub(to: fraction * viewModel.duration)
                    }
                    .onEnded { _ in
                        viewModel.endScrub()
                    }
            )
            #endif
        }
        .frame(height: 32)
    }

    private func thumbOffset(progress: Double, trackWidth: Double) -> Double {
        let thumbRadius: Double = viewModel.isScrubbing ? 8 : 6
        return max(0, min(trackWidth * progress - thumbRadius, trackWidth - thumbRadius * 2))
    }

    // MARK: - Error Overlay

    private func errorOverlay(_ error: PlaybackError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.duskAccent)

            Text(error.localizedDescription)
                .font(.headline)
                .foregroundStyle(Color.duskTextPrimary)
                .multilineTextAlignment(.center)

            Button("Close") {
                viewModel.cleanup()
                dismiss()
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(Color.duskAccent, in: Capsule())
            .duskSuppressTVOSButtonChrome()
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    // MARK: - Subtitle Picker

    private var subtitlePicker: some View {
        NavigationStack {
            List {
                Button {
                    viewModel.selectSubtitle(nil)
                } label: {
                    pickerRow(
                        title: "Off",
                        subtitle: nil,
                        isSelected: viewModel.selectedSubtitleTrackID == nil
                    )
                }
                .listRowBackground(Color.duskSurface)
                .duskSuppressTVOSButtonChrome()

                ForEach(viewModel.subtitleTracks) { track in
                    Button {
                        viewModel.selectSubtitle(track)
                    } label: {
                        pickerRow(
                            title: track.displayTitle,
                            subtitle: track.language,
                            isSelected: viewModel.selectedSubtitleTrackID == track.id
                        )
                    }
                    .listRowBackground(Color.duskSurface)
                    .duskSuppressTVOSButtonChrome()
                }
            }
            .duskScrollContentBackgroundHidden()
            .background(Color.duskBackground)
            .duskNavigationTitle("Subtitles")
            .duskNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { viewModel.showSubtitlePicker = false }
                        .duskSuppressTVOSButtonChrome()
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.duskBackground)
    }

    // MARK: - Audio Picker

    private var audioPicker: some View {
        NavigationStack {
            List {
                ForEach(viewModel.audioTracks) { track in
                    Button {
                        viewModel.selectAudio(track)
                    } label: {
                        pickerRow(
                            title: track.displayTitle,
                            subtitle: track.language,
                            isSelected: viewModel.selectedAudioTrackID == track.id
                        )
                    }
                    .listRowBackground(Color.duskSurface)
                    .duskSuppressTVOSButtonChrome()
                }
            }
            .duskScrollContentBackgroundHidden()
            .background(Color.duskBackground)
            .duskNavigationTitle("Audio")
            .duskNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { viewModel.showAudioPicker = false }
                        .duskSuppressTVOSButtonChrome()
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.duskBackground)
    }

    private func pickerRow(title: String, subtitle: String?, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Color.duskTextPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.duskTextSecondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.duskAccent)
            }
        }
    }
}
