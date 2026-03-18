import SwiftUI

struct HomeHubCarouselSection: View {
    let hub: PlexHub
    let items: [PlexItem]
    let posterWidth: CGFloat
    let showsShowAll: Bool
    let subtitle: (PlexItem) -> String?
    let posterURL: (PlexItem, Int, Int) -> URL?
    let onMarkWatched: (PlexItem) -> Void
    let onMarkUnwatched: (PlexItem) -> Void

    var body: some View {
        let imageWidth = Int(posterWidth.rounded(.up))
        let imageHeight = Int((posterWidth * 1.5).rounded(.up))

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
                PosterNavigationCard(
                    route: AppNavigationRoute.destination(for: item),
                    imageURL: posterURL(item, imageWidth, imageHeight),
                    title: item.title,
                    subtitle: subtitle(item),
                    width: posterWidth
                ) {
                    PlexItemContextMenuContent(
                        item: item,
                        onMarkWatched: {
                            onMarkWatched(item)
                        },
                        onMarkUnwatched: {
                            onMarkUnwatched(item)
                        }
                    )
                }
            }
        }
    }
}

struct HomeItemContextMenu: View {
    let item: PlexItem
    let detailsLabel: String
    let onMarkWatched: () -> Void
    let onMarkUnwatched: () -> Void
    let onSelectRoute: (AppNavigationRoute) -> Void

    var body: some View {
        if item.canMarkWatchedFromContextMenu {
            Button("Mark Watched", systemImage: "eye", action: onMarkWatched)
        }

        if item.canMarkUnwatchedFromContextMenu {
            Button("Mark Unwatched", systemImage: "eye.slash", action: onMarkUnwatched)
        }

        Button(detailsLabel, systemImage: "info.circle") {
            onSelectRoute(AppNavigationRoute.destination(for: item))
        }

        if let seasonRoute = item.contextMenuSeasonRoute {
            Button("Go to Season", systemImage: "rectangle.stack") {
                onSelectRoute(seasonRoute)
            }
        }

        if let showRoute = item.contextMenuShowRoute {
            Button("Go to Show", systemImage: "tv") {
                onSelectRoute(showRoute)
            }
        }
    }
}

struct HomeHeroActionButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))

            Text(title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.duskAccent, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }
}

struct HomeHeroPagerPill: View {
    let isActive: Bool
    let progress: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(isActive ? Color.white.opacity(0.24) : Color.white.opacity(0.28))
                .frame(width: isActive ? 28 : 10, height: 10)

            if isActive {
                Capsule()
                    .fill(Color.duskAccent)
                    .frame(width: 28 * min(max(progress, 0), 1), height: 10)
            }
        }
        .overlay {
            if isActive {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
        }
    }
}

struct HeroPauseAwareButtonStyle: ButtonStyle {
    let onPress: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    onPress()
                }
            }
    }
}
