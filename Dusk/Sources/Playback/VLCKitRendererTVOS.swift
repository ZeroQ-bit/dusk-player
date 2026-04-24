#if os(tvOS)
import UIKit
import VLCKit

final class TVOSVLCKitRenderingHost: NSObject, VLCKitRenderingHost, @unchecked Sendable, VLCDrawable {
    let playerView: UIView
    private var hostedVideoView: UIView?

    @MainActor
    override init() {
        self.playerView = UIView()
        super.init()
        playerView.backgroundColor = .black
        playerView.clipsToBounds = true
    }

    func attach(to player: VLCMediaPlayer, engine: VLCKitEngine) {
        player.drawable = self
    }

    func detach(from player: VLCMediaPlayer) {
        player.drawable = nil
        MainActor.assumeIsolated {
            hostedVideoView?.removeFromSuperview()
            hostedVideoView = nil
        }
    }

    func updatePlaybackState(
        currentTimeMs: Int64,
        durationMs: Int64,
        isPlaying: Bool,
        isSeekable: Bool
    ) {}

    func invalidatePlaybackState() {}

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
}
#endif
