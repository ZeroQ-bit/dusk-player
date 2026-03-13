import SwiftUI
#if os(iOS)
import UIKit
#endif

struct HomeView: View {
    @Environment(PlexService.self) private var plexService
    @Binding var path: NavigationPath
    @State private var viewModel: HomeViewModel?

    private let continueWatchingCardWidth: CGFloat = 280
    private let continueWatchingAspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.duskBackground.ignoresSafeArea()

                if let viewModel {
                    if viewModel.isLoading, viewModel.hubs.isEmpty {
                        ProgressView()
                            .tint(Color.duskAccent)
                    } else if let error = viewModel.error, viewModel.hubs.isEmpty {
                        errorView(error)
                    } else {
                        contentView(viewModel)
                    }
                }
            }
            .task(id: plexService.connectedServer?.clientIdentifier) {
                if viewModel == nil {
                    viewModel = HomeViewModel(plexService: plexService)
                }
                await viewModel?.load()
            }
            .refreshable {
                await viewModel?.load()
            }
            .duskNavigationTitle("Home")
            .duskNavigationBarTitleDisplayModeLarge()
            .duskAppNavigationDestinations()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func contentView(_ vm: HomeViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsHomeServerSubtitle, let serverName = plexService.connectedServer?.name {
                    homeSubtitle(serverName)
                        .padding(.bottom, 12)
                }

                LazyVStack(alignment: .leading, spacing: 18) {
                    // Continue Watching (Task B) — top of home
                    if !vm.continueWatching.isEmpty {
                        continueWatchingSection(vm)
                    }

                    // Hub carousels (Task A) — Recently Added, etc.
                    ForEach(vm.hubs) { hub in
                        let items = vm.inlineItems(in: hub)
                        if !items.isEmpty {
                            hubSection(hub, items: items, vm: vm)
                        }
                    }
                }
            }
            .padding(.top, showsHomeServerSubtitle ? -10 : 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 88)
        }
    }

    // MARK: - Continue Watching

    @ViewBuilder
    private func continueWatchingSection(_ vm: HomeViewModel) -> some View {
        let imageWidth = Int(continueWatchingCardWidth.rounded(.up))
        let imageHeight = Int((continueWatchingCardWidth / continueWatchingAspectRatio).rounded(.up))

        MediaCarousel(title: "Continue Watching") {
            ForEach(vm.continueWatching) { item in
                #if os(tvOS)
                VStack(alignment: .leading, spacing: 6) {
                    NavigationLink(value: AppNavigationRoute.destination(for: item)) {
                        PosterArtwork(
                            imageURL: vm.landscapeImageURL(for: item, width: imageWidth, height: imageHeight),
                            progress: vm.progress(for: item),
                            width: continueWatchingCardWidth,
                            imageAspectRatio: continueWatchingAspectRatio
                        )
                    }
                    .buttonStyle(.plain)
                    .duskSuppressTVOSButtonChrome()

                    PosterCardText(
                        title: vm.displayTitle(for: item),
                        subtitle: vm.displaySubtitle(for: item),
                        width: continueWatchingCardWidth
                    )
                }
                .frame(width: continueWatchingCardWidth, alignment: .topLeading)
                #else
                NavigationLink(value: AppNavigationRoute.destination(for: item)) {
                    PosterCard(
                        imageURL: vm.landscapeImageURL(for: item, width: imageWidth, height: imageHeight),
                        title: vm.displayTitle(for: item),
                        subtitle: vm.displaySubtitle(for: item),
                        progress: vm.progress(for: item),
                        width: continueWatchingCardWidth,
                        imageAspectRatio: continueWatchingAspectRatio
                    )
                }
                .buttonStyle(.plain)
                .duskSuppressTVOSButtonChrome()
                #endif
            }
        }
    }

    // MARK: - Hub Section

    @ViewBuilder
    private func hubSection(_ hub: PlexHub, items: [PlexItem], vm: HomeViewModel) -> some View {
        let imageWidth = 130
        let imageHeight = 195
        let showsShowAll = vm.shouldShowAll(for: hub)

        MediaCarousel(
            title: hub.title,
            headerAccessory: {
                if showsShowAll {
                    NavigationLink(value: AppNavigationRoute.hub(hub)) {
                        Text("Show all")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.duskAccent)
                    }
                    .buttonStyle(.plain)
                    .duskSuppressTVOSButtonChrome()
                }
            }
        ) {
            ForEach(items) { item in
                #if os(tvOS)
                VStack(alignment: .leading, spacing: 6) {
                    NavigationLink(value: AppNavigationRoute.destination(for: item)) {
                        PosterArtwork(
                            imageURL: vm.posterURL(for: item, width: imageWidth, height: imageHeight),
                            width: 130,
                            imageAspectRatio: 2.0 / 3.0
                        )
                    }
                    .buttonStyle(.plain)
                    .duskSuppressTVOSButtonChrome()

                    PosterCardText(
                        title: item.title,
                        subtitle: item.year.map(String.init),
                        width: 130
                    )
                }
                .frame(width: 130, alignment: .topLeading)
                #else
                NavigationLink(value: AppNavigationRoute.destination(for: item)) {
                    PosterCard(
                        imageURL: vm.posterURL(for: item, width: imageWidth, height: imageHeight),
                        title: item.title,
                        subtitle: item.year.map(String.init)
                    )
                }
                .buttonStyle(.plain)
                .duskSuppressTVOSButtonChrome()
                #endif
            }
        }
    }

    // MARK: - Error

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.duskTextSecondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(Color.duskTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Retry") {
                Task { await viewModel?.load() }
            }
            .foregroundStyle(Color.duskAccent)
            .duskSuppressTVOSButtonChrome()
        }
    }

    private func homeSubtitle(_ serverName: String) -> some View {
        Text(serverName)
            .font(.subheadline)
            .foregroundStyle(Color.duskTextSecondary)
            .lineLimit(1)
            .padding(.horizontal, 20)
    }

    private var showsHomeServerSubtitle: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
}

struct HomeHubItemsView: View {
    @State private var viewModel: HomeHubItemsViewModel

    private let horizontalPadding: CGFloat = 12
    private let gridSpacing: CGFloat = 12
    private let gridRowSpacing: CGFloat = 18
    private let preferredPosterWidth: CGFloat = 104
    private let minimumColumnCount = 2

    init(hub: PlexHub, plexService: PlexService) {
        _viewModel = State(initialValue: HomeHubItemsViewModel(
            hub: hub,
            plexService: plexService
        ))
    }

    var body: some View {
        ZStack {
            Color.duskBackground.ignoresSafeArea()

            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView()
                    .tint(Color.duskAccent)
            } else if let error = viewModel.error, viewModel.items.isEmpty {
                errorView(error)
            } else if viewModel.items.isEmpty {
                emptyView
            } else {
                itemsGrid
            }
        }
        .duskNavigationTitle(viewModel.navigationTitle)
        .duskNavigationBarTitleDisplayModeLarge()
        .task {
            await viewModel.loadItems()
        }
    }

    private var itemsGrid: some View {
        GeometryReader { geometry in
            let layout = gridLayout(for: geometry.size.width)
            let imageWidth = Int(layout.posterWidth.rounded(.up))
            let imageHeight = Int((layout.posterWidth * 1.5).rounded(.up))

            ScrollView {
                LazyVGrid(columns: layout.columns, spacing: gridRowSpacing) {
                    ForEach(viewModel.items) { item in
                        #if os(tvOS)
                        VStack(alignment: .leading, spacing: 6) {
                            NavigationLink(value: AppNavigationRoute.destination(for: item)) {
                                PosterArtwork(
                                    imageURL: viewModel.posterURL(for: item, width: imageWidth, height: imageHeight),
                                    progress: viewModel.progress(for: item),
                                    width: layout.posterWidth
                                )
                            }
                            .buttonStyle(.plain)
                            .duskSuppressTVOSButtonChrome()

                            PosterCardText(
                                title: item.title,
                                subtitle: viewModel.subtitle(for: item),
                                width: layout.posterWidth
                            )
                        }
                        .frame(width: layout.posterWidth, alignment: .topLeading)
                        #else
                        NavigationLink(value: AppNavigationRoute.destination(for: item)) {
                            PosterCard(
                                imageURL: viewModel.posterURL(for: item, width: imageWidth, height: imageHeight),
                                title: item.title,
                                subtitle: viewModel.subtitle(for: item),
                                progress: viewModel.progress(for: item),
                                width: layout.posterWidth
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .duskSuppressTVOSButtonChrome()
                        #endif
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func gridLayout(for containerWidth: CGFloat) -> (columns: [GridItem], posterWidth: CGFloat) {
        let availableWidth = max(containerWidth - (horizontalPadding * 2), preferredPosterWidth)
        let rawColumnCount = Int((availableWidth + gridSpacing) / (preferredPosterWidth + gridSpacing))
        let columnCount = max(rawColumnCount, minimumColumnCount)
        let totalSpacing = CGFloat(columnCount - 1) * gridSpacing
        let posterWidth = floor((availableWidth - totalSpacing) / CGFloat(columnCount))
        let columns = Array(
            repeating: GridItem(.fixed(posterWidth), spacing: gridSpacing, alignment: .top),
            count: columnCount
        )

        return (columns, posterWidth)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.largeTitle)
                .foregroundStyle(Color.duskTextSecondary)
            Text("No items found")
                .foregroundStyle(Color.duskTextSecondary)
        }
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(Color.duskTextSecondary)
            Text(message)
                .foregroundStyle(Color.duskTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Retry") {
                Task { await viewModel.loadItems() }
            }
            .foregroundStyle(Color.duskAccent)
            .duskSuppressTVOSButtonChrome()
        }
    }
}
