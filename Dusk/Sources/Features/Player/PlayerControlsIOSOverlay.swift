import SwiftUI

struct PlayerControlsIOSOverlay: View {
    let viewModel: PlayerViewModel
    let context: PlayerControlsContext
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let showsTrackLabels = geometry.size.width > geometry.size.height

            ZStack {
                PlayerControlsGradientBackdrop()

                VStack {
                    topBar
                    Spacer()
                    centerControls
                    Spacer()
                    bottomBar(showsTrackLabels: showsTrackLabels)
                }
                .padding(.horizontal, PlayerOverlayLayout.controlsHorizontalPadding)
                .padding(.vertical, 16)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }

            if let header = context.mediaHeader {
                PlayerMediaHeaderView(header: header)
            }

            Spacer()
        }
    }

    private var centerControls: some View {
        let isPlaying = viewModel.state == .playing

        return HStack {
            Spacer()
            Button { viewModel.togglePlayPause() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .contentTransition(.symbolEffect(.replace, options: .speed(2)))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
        }
    }

    private func bottomBar(showsTrackLabels: Bool) -> some View {
        VStack(spacing: 8) {
            PlayerSeekBar(viewModel: viewModel, isInteractive: true)

            HStack {
                PlayerTimeStatusView(viewModel: viewModel)

                Spacer()

                Button { viewModel.showSubtitlePicker = true } label: {
                    trackButtonLabel(
                        icon: viewModel.selectedSubtitleTrack == nil ? "captions.bubble" : "captions.bubble.fill",
                        title: context.subtitleControlTitle,
                        showsTitle: showsTrackLabels,
                        isEnabled: !viewModel.subtitleTracks.isEmpty
                    )
                }
                .disabled(viewModel.subtitleTracks.isEmpty)

                Button { viewModel.showAudioPicker = true } label: {
                    trackButtonLabel(
                        icon: "speaker.wave.2",
                        title: context.audioControlTitle,
                        showsTitle: showsTrackLabels,
                        isEnabled: !viewModel.audioTracks.isEmpty
                    )
                }
                .disabled(viewModel.audioTracks.isEmpty)
            }
        }
    }

    private func trackButtonLabel(
        icon: String,
        title: String,
        showsTitle: Bool,
        isEnabled: Bool
    ) -> some View {
        HStack(spacing: showsTitle ? 8 : 0) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 16, height: 16, alignment: .center)

            if showsTitle {
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.white.opacity(isEnabled ? 1.0 : 0.72))
        .padding(.horizontal, showsTitle ? 10 : 0)
        .frame(
            width: showsTitle ? 132 : 36,
            height: 36,
            alignment: showsTitle ? .leading : .center
        )
        .background(.white.opacity(0.12), in: Capsule())
    }
}
