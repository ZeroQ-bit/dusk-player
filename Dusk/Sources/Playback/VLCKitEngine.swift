#if canImport(VLCKit)
import OSLog
import SwiftUI
import UIKit
import VLCKit
#endif

#if canImport(VLCKit)
private let vlcKitEngineLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Dusk",
    category: "VLCKitEngine"
)

/// Platform renderer contract for the shared VLCKit playback core.
protocol VLCKitRenderingHost: AnyObject, Sendable {
    var playerView: UIView { get }

    func attach(to player: VLCMediaPlayer, engine: VLCKitEngine)
    func detach(from player: VLCMediaPlayer)
    func updatePlaybackState(
        currentTimeMs: Int64,
        durationMs: Int64,
        isPlaying: Bool,
        isSeekable: Bool
    )
    func invalidatePlaybackState()
}

@MainActor
private func makeVLCKitRenderingHost() -> any VLCKitRenderingHost {
    #if os(iOS)
    IOSVLCKitRenderingHost()
    #elseif os(tvOS)
    TVOSVLCKitRenderingHost()
    #else
    fatalError("VLCKit is not supported on this platform")
    #endif
}

/// PlaybackEngine implementation backed by upstream VLCKit 4.x.
///
/// Shared playback logic lives here. Platform-specific rendering behavior
/// lives in `VLCKitRendererIOS.swift` and `VLCKitRendererTVOS.swift`.
@MainActor
@Observable
final class VLCKitEngine: NSObject, PlaybackEngine {
    private static let seekSettleDelay: Duration = .milliseconds(150)
    private static let seekRetryDelay: Duration = .milliseconds(450)
    private static let pendingSeekTolerance: TimeInterval = 1.0
    private static let pendingSeekStaleUpdateWindow: TimeInterval = 1.5

    private(set) var state: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isBuffering = false
    private(set) var error: PlaybackError?
    private(set) var availableSubtitleTracks: [SubtitleTrack] = []
    private(set) var availableAudioTracks: [AudioTrack] = []
    private(set) var selectedSubtitleTrackID: Int?
    private(set) var selectedAudioTrackID: Int?
    var onPlaybackEnded: (@MainActor () -> Void)?

    nonisolated(unsafe) private let mediaPlayer: VLCMediaPlayer
    private let renderingHost: any VLCKitRenderingHost

    private var pendingStartPosition: TimeInterval?
    private var hasAppliedStartPosition = false
    private var hasReportedPlaybackEnded = false
    private var suppressPlaybackEndedEvent = false
    private var pendingSeekTarget: TimeInterval?
    private var pendingSeekStartedAt: Date?
    private var currentAttemptContext: PlaybackAttemptContext?
    @ObservationIgnored nonisolated(unsafe) private var seekVerificationTask: Task<Void, Never>?

    override init() {
        let player = VLCMediaPlayer()
        let renderingHost = makeVLCKitRenderingHost()
        self.mediaPlayer = player
        self.renderingHost = renderingHost
        super.init()

        player.delegate = self
        player.timeChangeUpdateInterval = 0.25
        player.minimalTimePeriod = 250_000
        renderingHost.attach(to: player, engine: self)
    }

    deinit {
        seekVerificationTask?.cancel()
        mediaPlayer.stop()
        mediaPlayer.delegate = nil
        renderingHost.detach(from: mediaPlayer)
    }

    func load(source: PlaybackSource) {
        currentAttemptContext = source.context
        state = .loading
        isBuffering = true
        error = nil
        currentTime = 0
        duration = 0
        hasAppliedStartPosition = false
        hasReportedPlaybackEnded = false
        suppressPlaybackEndedEvent = false
        clearPendingSeek()
        pendingStartPosition = source.startPosition
        availableSubtitleTracks = []
        availableAudioTracks = []
        selectedSubtitleTrackID = nil
        selectedAudioTrackID = nil
        syncRendererPlaybackState()

        vlcKitEngineLogger.notice(
            "Playback attempt \(source.context.attemptLabel, privacy: .public) starting in VLCKit for ratingKey \(source.context.ratingKey, privacy: .public), media \(source.context.mediaID, privacy: .public), part \(source.context.partID, privacy: .public), URL \(source.context.sanitizedDirectPlayURL, privacy: .public)"
        )

        guard let media = VLCMedia(url: source.url) else {
            isBuffering = false
            state = .error
            vlcKitEngineLogger.error(
                "Playback attempt \(source.context.attemptLabel, privacy: .public) failed before opening: VLCKit could not create media for URL \(source.context.sanitizedDirectPlayURL, privacy: .public)"
            )
            error = .unknown("VLCKit could not open the direct-play stream.")
            return
        }
        applySubtitleStyling(to: media)
        mediaPlayer.media = media
        mediaPlayer.currentSubTitleFontScale = PlaybackSubtitleStyle.vlcSubtitleFontScale
        mediaPlayer.play()
    }

    func play() {
        suppressPlaybackEndedEvent = false
        mediaPlayer.play()
        syncRendererPlaybackState()
    }

    func pause() {
        seekVerificationTask?.cancel()
        seekVerificationTask = nil
        mediaPlayer.pause()
        syncRendererPlaybackState()
    }

    func stop() {
        clearPendingSeek()
        suppressPlaybackEndedEvent = true
        mediaPlayer.stop()
        state = .stopped
        hasReportedPlaybackEnded = false
        currentAttemptContext = nil
        syncRendererPlaybackState()
    }

    func seek(to position: TimeInterval) {
        let clampedPosition: TimeInterval
        if duration > 0 {
            clampedPosition = min(max(position, 0), duration)
        } else {
            clampedPosition = max(position, 0)
        }

        pendingSeekTarget = clampedPosition
        pendingSeekStartedAt = Date()
        currentTime = clampedPosition

        // Seek without pausing — pausing first creates a race between
        // VLCKit's asynchronous state callbacks and the timed resume,
        // which can leave the player stuck in a paused state.
        applySeek(to: clampedPosition)
        scheduleSeekVerification(target: clampedPosition)
        syncRendererPlaybackState()
    }

    func selectSubtitleTrack(_ track: SubtitleTrack?) {
        guard let track else {
            mediaPlayer.deselectAllTextTracks()
            selectedSubtitleTrackID = nil
            return
        }

        mediaPlayer.textTracks
            .first { Int($0.identifier) == track.id }?
            .isSelectedExclusively = true
        selectedSubtitleTrackID = track.id
    }

    func selectAudioTrack(_ track: AudioTrack) {
        mediaPlayer.audioTracks
            .first { Int($0.identifier) == track.id }?
            .isSelectedExclusively = true
        selectedAudioTrackID = track.id
    }

    func makePlayerView() -> AnyView {
        AnyView(VLCPlayerRepresentable(playerView: renderingHost.playerView))
    }

    fileprivate func handleStateChange(_ vlcState: VLCMediaPlayerState) {
        logStateChange(vlcState)
        switch vlcState {
        case .opening, .buffering:
            isBuffering = true
            if state != .playing && state != .paused {
                state = .loading
            }

        case .playing:
            isBuffering = false
            state = .playing
            suppressPlaybackEndedEvent = false

            if !hasAppliedStartPosition, let start = pendingStartPosition, start > 0 {
                hasAppliedStartPosition = true
                seek(to: start)
            }

            refreshTracks()

        case .paused:
            isBuffering = false
            state = .paused

        case .stopping:
            isBuffering = false

        case .stopped:
            isBuffering = false
            state = .stopped
            clearPendingSeek()

            if !suppressPlaybackEndedEvent, shouldTreatCurrentStopAsPlaybackEnded {
                currentTime = max(currentTime, duration)
                if !hasReportedPlaybackEnded {
                    hasReportedPlaybackEnded = true
                    if let currentAttemptContext {
                        vlcKitEngineLogger.notice(
                            "Playback attempt \(currentAttemptContext.attemptLabel, privacy: .public) VLCKit reached end of playback"
                        )
                    }
                    onPlaybackEnded?()
                }
            }

            suppressPlaybackEndedEvent = false

        case .error:
            isBuffering = false
            state = .error
            let parsedStatus = String(describing: mediaPlayer.media?.parsedStatus)
            let attemptLabel = currentAttemptContext?.attemptLabel ?? "unknown"
            let urlLabel = currentAttemptContext?.sanitizedDirectPlayURL ?? "<unknown>"
            vlcKitEngineLogger.error(
                "Playback attempt \(attemptLabel, privacy: .public) VLCKit entered error state. parsedStatus=\(parsedStatus, privacy: .public) currentTime=\(self.currentTime, privacy: .public) duration=\(self.duration, privacy: .public) URL=\(urlLabel, privacy: .public)"
            )
            error = .unknown(vlcPlaybackErrorMessage())
            clearPendingSeek()

        @unknown default:
            break
        }

        syncRendererPlaybackState()
        renderingHost.invalidatePlaybackState()
    }

    fileprivate func updateTime(timeMs: Int32, lengthMs: Int32) {
        let updatedTime = max(0, TimeInterval(timeMs) / 1000.0)
        if lengthMs > 0 {
            duration = TimeInterval(lengthMs) / 1000.0
        }

        if shouldAcceptUpdatedTime(updatedTime) {
            currentTime = updatedTime
        }
        syncRendererPlaybackState()
    }

    private var shouldTreatCurrentStopAsPlaybackEnded: Bool {
        let durationTolerance = max(1.0, min(5.0, duration * 0.01))
        let reachedDuration = duration > 0 && currentTime >= max(0, duration - durationTolerance)
        let reachedEndPosition = mediaPlayer.position >= 0.98
        return reachedDuration || reachedEndPosition
    }

    private func syncRendererPlaybackState() {
        renderingHost.updatePlaybackState(
            currentTimeMs: Int64(currentTime * 1000),
            durationMs: Int64(duration * 1000),
            isPlaying: state == .playing,
            isSeekable: duration > 0
        )
    }

    private func applySubtitleStyling(to media: VLCMedia) {
        media.addOption(":freetype-color=#FFFFFF")
        media.addOption(":freetype-background-color=#000000")
        media.addOption(":freetype-background-opacity=110")
        media.addOption(":freetype-shadow-color=#000000")
        media.addOption(":freetype-shadow-opacity=80")
        media.addOption(":freetype-shadow-distance=1")
    }

    private func applySeek(to position: TimeInterval) {
        if duration > 0 {
            let normalizedPosition = min(max(position / duration, 0), 1)
            if normalizedPosition.isFinite {
                mediaPlayer.position = normalizedPosition
            }
        }

        let targetMs = Int(position * 1000.0)
        mediaPlayer.time = VLCTime(int: Int32(clamping: targetMs))
    }

    private func scheduleSeekVerification(target: TimeInterval) {
        seekVerificationTask?.cancel()
        seekVerificationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.seekSettleDelay)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else { return }

            if self.shouldRetrySeek(toward: target) {
                self.applySeek(to: target)
            }

            do {
                try await Task.sleep(for: Self.seekRetryDelay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            if self.shouldRetrySeek(toward: target) {
                self.applySeek(to: target)
            }
        }
    }

    private func shouldRetrySeek(toward target: TimeInterval) -> Bool {
        guard let pendingSeekTarget else { return false }
        guard abs(pendingSeekTarget - target) <= Self.pendingSeekTolerance else { return false }
        return !hasReachedPendingSeekTarget(using: observedPlayerTime)
    }

    private func shouldAcceptUpdatedTime(_ updatedTime: TimeInterval) -> Bool {
        guard pendingSeekTarget != nil else { return true }

        if hasReachedPendingSeekTarget(using: updatedTime) {
            clearPendingSeek()
            return true
        }

        let elapsed = pendingSeekStartedAt.map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        if elapsed < Self.pendingSeekStaleUpdateWindow {
            return false
        }

        clearPendingSeek()
        return true
    }

    private func hasReachedPendingSeekTarget(using updatedTime: TimeInterval) -> Bool {
        guard let pendingSeekTarget else { return true }
        return abs(updatedTime - pendingSeekTarget) <= Self.pendingSeekTolerance
    }

    private var observedPlayerTime: TimeInterval {
        max(0, TimeInterval(mediaPlayer.time.intValue) / 1000.0)
    }

    private func clearPendingSeek() {
        pendingSeekTarget = nil
        pendingSeekStartedAt = nil
        seekVerificationTask?.cancel()
        seekVerificationTask = nil
    }

    private func vlcPlaybackErrorMessage() -> String {
        guard let currentAttemptContext else {
            return "VLCKit failed while opening the direct-play stream."
        }
        return "VLCKit failed while opening the direct-play stream. \(currentAttemptContext.sanitizedDirectPlayURL)"
    }

    private func logStateChange(_ vlcState: VLCMediaPlayerState) {
        let attemptLabel = currentAttemptContext?.attemptLabel ?? "unknown"
        let parsedStatus = String(describing: mediaPlayer.media?.parsedStatus)
        vlcKitEngineLogger.debug(
            "Playback attempt \(attemptLabel, privacy: .public) VLCKit state=\(String(describing: vlcState), privacy: .public) parsedStatus=\(parsedStatus, privacy: .public) currentTime=\(self.currentTime, privacy: .public) duration=\(self.duration, privacy: .public) buffering=\(self.isBuffering, privacy: .public)"
        )
    }

    private func refreshTracks() {
        availableAudioTracks = mediaPlayer.audioTracks.map { track in
            AudioTrack(
                id: Int(track.identifier),
                displayTitle: trackDisplayTitle(for: track),
                language: track.language,
                languageCode: normalizedLanguageCode(from: track.language),
                codec: track.codecName(),
                channels: Int(track.audio?.channelsNumber ?? 0).nonZeroValue,
                channelLayout: nil
            )
        }
        selectedAudioTrackID = mediaPlayer.audioTracks.first(where: \.isSelected).map { Int($0.identifier) }

        availableSubtitleTracks = mediaPlayer.textTracks.map { track in
            SubtitleTrack(
                id: Int(track.identifier),
                displayTitle: trackDisplayTitle(for: track),
                language: track.language,
                languageCode: normalizedLanguageCode(from: track.language),
                codec: track.codecName(),
                isForced: false,
                isHearingImpaired: false,
                isExternal: false,
                externalURL: nil
            )
        }
        selectedSubtitleTrackID = mediaPlayer.textTracks.first(where: \.isSelected).map { Int($0.identifier) }
    }

    private func trackDisplayTitle(for track: VLCMediaPlayer.Track) -> String {
        if !track.trackName.isEmpty {
            return track.trackName
        }

        if let description = track.trackDescription, !description.isEmpty {
            return description
        }

        if let language = track.language, !language.isEmpty {
            return language
        }

        return "Unknown"
    }

    private func normalizedLanguageCode(from language: String?) -> String? {
        guard let language, !language.isEmpty else { return nil }
        return language.lowercased()
    }
}

extension VLCKitEngine: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        Task { @MainActor [weak self] in
            self?.handleStateChange(newState)
        }
    }

    nonisolated func mediaPlayerLengthChanged(_ length: Int64) {
        let timeMs = mediaPlayer.time.intValue
        Task { @MainActor [weak self] in
            self?.updateTime(timeMs: timeMs, lengthMs: Int32(length))
            self?.renderingHost.invalidatePlaybackState()
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        let timeMs = mediaPlayer.time.intValue
        let lengthMs = mediaPlayer.media?.length.intValue ?? 0
        Task { @MainActor [weak self] in
            self?.updateTime(timeMs: timeMs, lengthMs: lengthMs)
        }
    }

    nonisolated func mediaPlayerTrackAdded(_ trackId: String, with trackType: VLCMedia.TrackType) {
        Task { @MainActor [weak self] in
            self?.refreshTracks()
        }
    }

    nonisolated func mediaPlayerTrackRemoved(_ trackId: String, with trackType: VLCMedia.TrackType) {
        Task { @MainActor [weak self] in
            self?.refreshTracks()
        }
    }

    nonisolated func mediaPlayerTrackUpdated(_ trackId: String, with trackType: VLCMedia.TrackType) {
        Task { @MainActor [weak self] in
            self?.refreshTracks()
        }
    }

    nonisolated func mediaPlayerTrackSelected(
        _ trackType: VLCMedia.TrackType,
        selectedId: String,
        unselectedId: String
    ) {
        Task { @MainActor [weak self] in
            self?.refreshTracks()
        }
    }
}

private struct VLCPlayerRepresentable: UIViewRepresentable {
    let playerView: UIView

    func makeUIView(context: Context) -> UIView {
        playerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private extension Int {
    var nonZeroValue: Int? {
        self == 0 ? nil : self
    }
}
#endif
