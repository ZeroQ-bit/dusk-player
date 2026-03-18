#if os(tvOS)
import SwiftUI

struct PlayerControlsTVOverlay: View {
    let viewModel: PlayerViewModel
    let context: PlayerControlsContext
    let onDismiss: () -> Void

    private let skipInterval: TimeInterval = 10

    var body: some View {
        GeometryReader { _ in
            ZStack {
                PlayerControlsGradientBackdrop()

                VStack(spacing: 26) {
                    topBar
                    Spacer()
                    transportControls
                    Spacer()
                    bottomBar
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 28)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 18) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .duskSuppressTVOSButtonChrome()
            .duskTVOSFocusEffectShape(Circle())

            if let header = context.mediaHeader {
                PlayerMediaHeaderView(header: header)
            }

            Spacer()
        }
    }

    private var transportControls: some View {
        let isPlaying = viewModel.state == .playing

        return HStack(spacing: 28) {
            transportButton(systemImage: "gobackward.10") {
                viewModel.handleDoubleTapSeek(by: -skipInterval)
            }

            transportButton(
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                font: .system(size: 46, weight: .medium)
            ) {
                viewModel.togglePlayPause()
            }

            transportButton(systemImage: "goforward.10") {
                viewModel.handleDoubleTapSeek(by: skipInterval)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            PlayerSeekBar(viewModel: viewModel, isInteractive: false)
                .frame(height: 36)

            HStack(alignment: .center, spacing: 18) {
                PlayerTimeStatusView(viewModel: viewModel)

                Spacer()

                tvTrackButton(
                    icon: viewModel.selectedSubtitleTrack == nil ? "captions.bubble" : "captions.bubble.fill",
                    title: context.subtitleControlTitle,
                    isEnabled: !viewModel.subtitleTracks.isEmpty
                ) {
                    viewModel.showSubtitlePicker = true
                }
                .disabled(viewModel.subtitleTracks.isEmpty)

                tvTrackButton(
                    icon: "speaker.wave.2",
                    title: context.audioControlTitle,
                    isEnabled: !viewModel.audioTracks.isEmpty
                ) {
                    viewModel.showAudioPicker = true
                }
                .disabled(viewModel.audioTracks.isEmpty)
            }
        }
    }

    private func transportButton(
        systemImage: String,
        font: Font = .system(size: 34, weight: .medium),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(font)
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .duskSuppressTVOSButtonChrome()
        .duskTVOSFocusEffectShape(Circle())
    }

    private func tvTrackButton(
        icon: String,
        title: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.72))
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .duskSuppressTVOSButtonChrome()
        .duskTVOSFocusEffectShape(Capsule())
    }
}
#endif
