import SwiftUI
#if os(iOS)
import UIKit
#endif

struct HomeView: View {
    @Environment(PlexService.self) private var plexService
    @Environment(PlaybackCoordinator.self) private var playback
    @Binding var path: NavigationPath
    @State private var viewModel: HomeViewModel?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.duskBackground.ignoresSafeArea()

                if let viewModel {
                    let hasHomeContent = !viewModel.hubs.isEmpty ||
                        !viewModel.continueWatching.isEmpty ||
                        !viewModel.personalizedShelves.isEmpty

                    if viewModel.isLoading, !hasHomeContent {
                        FeatureLoadingView()
                    } else if let error = viewModel.error, !hasHomeContent {
                        FeatureErrorView(message: error) {
                            Task { await viewModel.load(maxRecentlyAddedItems: recentlyAddedInlineItemLimit) }
                        }
                    } else {
                        platformContent(viewModel)
                    }
                } else {
                    FeatureLoadingView()
                }
            }
            .task(id: plexService.connectedServer?.clientIdentifier) {
                if viewModel == nil {
                    viewModel = HomeViewModel(plexService: plexService)
                }
                scheduleLoad()
            }
            .onAppear {
                guard viewModel != nil, !playback.showPlayer else { return }
                scheduleLoad()
            }
            .onChange(of: playback.showPlayer) { _, isShowing in
                if isShowing {
                    cancelLoad()
                } else {
                    scheduleLoad()
                }
            }
            .refreshable {
                cancelLoad()
                await viewModel?.load(maxRecentlyAddedItems: recentlyAddedInlineItemLimit)
            }
            .duskAppNavigationDestinations()
        }
    }

    @ViewBuilder
    private func platformContent(_ viewModel: HomeViewModel) -> some View {
        #if os(tvOS)
        HomeTVView(
            path: $path,
            viewModel: viewModel,
            serverName: plexService.connectedServer?.name,
            recentlyAddedInlineItemLimit: recentlyAddedInlineItemLimit,
            play: play
        )
        #else
        HomeIOSView(
            path: $path,
            viewModel: viewModel,
            serverName: plexService.connectedServer?.name,
            recentlyAddedInlineItemLimit: recentlyAddedInlineItemLimit,
            play: play
        )
        #endif
    }

    private var recentlyAddedInlineItemLimit: Int {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? 15 : 10
        #else
        10
        #endif
    }

    private func play(_ item: PlexItem) {
        cancelLoad()
        Task {
            await playback.play(ratingKey: item.ratingKey)
        }
    }

    private func scheduleLoad() {
        cancelLoad()

        guard let viewModel else { return }
        loadTask = Task {
            await viewModel.load(maxRecentlyAddedItems: recentlyAddedInlineItemLimit)
        }
    }

    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
    }
}
