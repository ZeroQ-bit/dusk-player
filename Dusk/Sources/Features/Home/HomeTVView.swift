import SwiftUI

struct HomeTVView: View {
    let viewModel: HomeViewModel
    let serverName: String?
    let recentlyAddedInlineItemLimit: Int
    let play: (PlexItem) -> Void

    @State private var selectedFeaturedIndex = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if !featuredItems.isEmpty {
                    featuredSection(items: featuredItems)
                } else if let serverName {
                    homeHeader(serverName: serverName)
                }

                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(viewModel.hubs) { hub in
                        let items = viewModel.inlineItems(
                            in: hub,
                            maxRecentlyAddedItems: recentlyAddedInlineItemLimit
                        )

                        if !items.isEmpty {
                            HomeHubCarouselSection(
                                hub: hub,
                                items: items,
                                posterWidth: 180,
                                showsShowAll: viewModel.shouldShowAll(
                                    for: hub,
                                    maxRecentlyAddedItems: recentlyAddedInlineItemLimit
                                ),
                                subtitle: { $0.year.map(String.init) },
                                posterURL: { item, width, height in
                                    viewModel.posterURL(for: item, width: width, height: height)
                                },
                                onMarkWatched: { item in
                                    Task { await viewModel.setWatched(true, for: item) }
                                },
                                onMarkUnwatched: { item in
                                    Task { await viewModel.setWatched(false, for: item) }
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func featuredSection(items: [PlexItem]) -> some View {
        let item = items[resolvedFeaturedIndex(for: items)]
        let metadata = viewModel.heroMetadata(for: item)
        let backdropURL = viewModel.heroBackgroundURL(for: item, width: 1920, height: 720)

        ZStack(alignment: .bottomLeading) {
            DetailHeroBackdrop(imageURL: backdropURL, height: 440)

            ZStack {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.16),
                        Color.black.opacity(0.82),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.86),
                        Color.black.opacity(0.42),
                        .clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    if let serverName, resolvedFeaturedIndex(for: items) == 0 {
                        Text(serverName)
                            .font(.headline.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.76))
                    }

                    Text(viewModel.displayTitle(for: item))
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.24), radius: 10, y: 4)

                    if let episodeTitle = viewModel.heroEpisodeTitle(for: item) {
                        Text(episodeTitle)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .lineLimit(2)
                    }

                    if !metadata.isEmpty {
                        Text(metadata.joined(separator: " · "))
                            .font(.headline.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.76))
                    }
                }

                if let summary = viewModel.heroSummary(for: item) {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.86))
                        .lineLimit(3)
                        .frame(maxWidth: 720, alignment: .leading)
                }

                HStack(spacing: 16) {
                    Button {
                        play(item)
                    } label: {
                        HomeHeroActionButtonLabel(
                            title: viewModel.heroPrimaryActionTitle(for: item),
                            systemImage: "play.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .duskSuppressTVOSButtonChrome()
                    .duskTVOSFocusEffectShape(Capsule())

                    NavigationLink(value: AppNavigationRoute.destination(for: item)) {
                        TVFeaturedSecondaryActionLabel(title: heroDetailsLabel(for: item))
                    }
                    .buttonStyle(.plain)
                    .duskSuppressTVOSButtonChrome()
                    .duskTVOSFocusEffectShape(Capsule())
                }

                if items.count > 1 {
                    HStack(spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, featuredItem in
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    selectedFeaturedIndex = index
                                }
                            } label: {
                                HomeHeroPagerPill(
                                    isActive: index == resolvedFeaturedIndex(for: items),
                                    progress: index == resolvedFeaturedIndex(for: items) ? 1 : 0
                                )
                                .accessibilityLabel(Text(viewModel.displayTitle(for: featuredItem)))
                            }
                            .buttonStyle(.plain)
                            .duskSuppressTVOSButtonChrome()
                        }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 34)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func homeHeader(serverName: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Home")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(Color.duskTextPrimary)

            Text(serverName)
                .font(.title3)
                .foregroundStyle(Color.duskTextSecondary)
        }
    }

    private var featuredItems: [PlexItem] {
        viewModel.heroItems()
    }

    private func resolvedFeaturedIndex(for items: [PlexItem]) -> Int {
        guard !items.isEmpty else { return 0 }
        return min(selectedFeaturedIndex, items.count - 1)
    }

    private func heroDetailsLabel(for item: PlexItem) -> String {
        switch item.type {
        case .episode:
            return "Episode Details"
        case .season:
            return "Season Details"
        case .show:
            return "Show Details"
        case .movie:
            return "Movie Details"
        default:
            return "View Details"
        }
    }
}

private struct TVFeaturedSecondaryActionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}
