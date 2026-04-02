#if os(iOS)
import UIKit
import VLCKit

final class IOSVLCKitRenderingHost: NSObject, VLCKitRenderingHost, @unchecked Sendable, VLCDrawable, VLCPictureInPictureDrawable, VLCPictureInPictureMediaControlling {
    let playerView: UIView

    private weak var mediaPlayer: VLCMediaPlayer?
    private var pictureInPictureController: (any VLCPictureInPictureWindowControlling)?
    private var hostedVideoView: UIView?
    private var currentTimeMs: Int64 = 0
    private var durationMs: Int64 = 0
    private var mediaPlaying = false
    private var mediaSeekable = false
    private var pendingAutomaticPiPStart = false
    private var isPictureInPictureActive = false
    private var notificationObservers: [NSObjectProtocol] = []

    private var playHandler: (() -> Void)?
    private var pauseHandler: (() -> Void)?
    private var seekHandler: ((Int64, @escaping () -> Void) -> Void)?

    @MainActor
    override init() {
        self.playerView = IOSVLCPictureInPictureContainerView()
        super.init()
        playerView.backgroundColor = .black
        observeApplicationLifecycle()
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func attach(to player: VLCMediaPlayer, engine: VLCKitEngine) {
        mediaPlayer = player
        playHandler = { [weak engine] in
            Task { @MainActor [weak engine] in
                engine?.play()
            }
        }
        pauseHandler = { [weak engine] in
            Task { @MainActor [weak engine] in
                engine?.pause()
            }
        }
        seekHandler = { [weak engine] offsetMs, completion in
            guard engine != nil else {
                completion()
                return
            }

            Task { @MainActor [weak engine] in
                guard let engine else { return }
                let targetSeconds = max(0, engine.currentTime + (TimeInterval(offsetMs) / 1000.0))
                engine.seek(to: targetSeconds)
            }

            completion()
        }

        player.drawable = self
    }

    func detach(from player: VLCMediaPlayer) {
        mediaPlayer = nil
        player.drawable = nil
        playHandler = nil
        pauseHandler = nil
        seekHandler = nil
        pictureInPictureController = nil
    }

    func updatePlaybackState(
        currentTimeMs: Int64,
        durationMs: Int64,
        isPlaying: Bool,
        isSeekable: Bool
    ) {
        self.currentTimeMs = currentTimeMs
        self.durationMs = durationMs
        self.mediaPlaying = isPlaying
        self.mediaSeekable = isSeekable
    }

    func invalidatePlaybackState() {
        pictureInPictureController?.invalidatePlaybackState()
    }

    func addSubview(_ view: UIView) {
        MainActor.assumeIsolated {
            if hostedVideoView !== view {
                hostedVideoView?.removeFromSuperview()
                hostedVideoView = view
                view.frame = playerView.bounds
                view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                playerView.addSubview(view)
            }
        }
    }

    func bounds() -> CGRect {
        MainActor.assumeIsolated {
            playerView.bounds
        }
    }

    func mediaController() -> (any VLCPictureInPictureMediaControlling)? {
        self
    }

    func pictureInPictureReady() -> (((any VLCPictureInPictureWindowControlling)?) -> Void)? {
        { [weak self] controller in
            guard let self, let controller else { return }

            self.pictureInPictureController = controller
            controller.stateChangeEventHandler = { [weak self] isStarted in
                self?.isPictureInPictureActive = isStarted
                if isStarted {
                    self?.pendingAutomaticPiPStart = false
                }
            }
            controller.invalidatePlaybackState()
        }
    }

    func play() {
        playHandler?()
    }

    func pause() {
        pauseHandler?()
    }

    func seek(by offset: Int64, completion: @escaping () -> Void) {
        seekHandler?(offset, completion)
    }

    func mediaLength() -> Int64 {
        if let media = mediaPlayer?.media {
            return Int64(media.length.intValue)
        }
        return durationMs
    }

    func mediaTime() -> Int64 {
        if let mediaPlayer {
            return Int64(mediaPlayer.time.intValue)
        }
        return currentTimeMs
    }

    func isMediaSeekable() -> Bool {
        mediaPlayer?.isSeekable ?? mediaSeekable
    }

    func isMediaPlaying() -> Bool {
        mediaPlayer?.isPlaying ?? mediaPlaying
    }

    private func observeApplicationLifecycle() {
        let notificationCenter = NotificationCenter.default
        notificationObservers = [
            notificationCenter.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.pendingAutomaticPiPStart = self?.shouldStartPictureInPictureAutomatically ?? false
            },
            notificationCenter.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.pendingAutomaticPiPStart = false
            },
            notificationCenter.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.startPictureInPictureIfNeeded()
            },
        ]
    }

    private var shouldStartPictureInPictureAutomatically: Bool {
        MainActor.assumeIsolated {
            pictureInPictureController != nil &&
            !isPictureInPictureActive &&
            isMediaPlaying() &&
            playerView.window != nil &&
            !playerView.bounds.isEmpty
        }
    }

    private func startPictureInPictureIfNeeded() {
        guard pendingAutomaticPiPStart, shouldStartPictureInPictureAutomatically else {
            pendingAutomaticPiPStart = false
            return
        }

        pendingAutomaticPiPStart = false
        pictureInPictureController?.startPictureInPicture()
    }
}

private final class IOSVLCPictureInPictureContainerView: UIView {}
#endif
