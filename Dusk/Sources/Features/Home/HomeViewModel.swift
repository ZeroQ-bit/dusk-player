import Foundation

@MainActor @Observable
final class HomeViewModel {
    private let maxInlineRecentlyAddedItems = 10

    private(set) var hubs: [PlexHub] = []
    private(set) var continueWatching: [PlexItem] = []
    private(set) var isLoading = false
    private(set) var error: String?

    private let plexService: PlexService

    init(plexService: PlexService) {
        self.plexService = plexService
    }

    func load() async {
        isLoading = true
        error = nil

        do {
            async let fetchedHubs = plexService.getHubs()
            async let fetchedOnDeck = plexService.getContinueWatching()

            hubs = try await fetchedHubs.filter { !shouldHideHomeHub($0) }
            continueWatching = try await fetchedOnDeck.filter { !shouldHideHomeItem($0) }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func setWatched(_ watched: Bool, for item: PlexItem) async {
        do {
            if watched {
                try await plexService.scrobble(ratingKey: item.ratingKey)
            } else {
                try await plexService.unscrobble(ratingKey: item.ratingKey)
            }
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Resolve the best poster URL for an item.
    func posterURL(for item: PlexItem, width: Int, height: Int) -> URL? {
        plexService.imageURL(for: item.preferredPosterPath, width: width, height: height)
    }

    /// Resolve the best landscape artwork URL for continue watching cards.
    func landscapeImageURL(for item: PlexItem, width: Int, height: Int) -> URL? {
        plexService.imageURL(for: item.preferredLandscapePath, width: width, height: height)
    }

    /// Progress fraction (0–1) for partially watched items. Nil if unwatched.
    func progress(for item: PlexItem) -> Double? {
        guard let offset = item.viewOffset, offset > 0,
              let duration = item.duration, duration > 0 else { return nil }
        return Double(offset) / Double(duration)
    }

    /// Display title for continue watching items.
    /// Episodes show the series title; movies just show the title.
    func displayTitle(for item: PlexItem) -> String {
        if item.type == .episode, let show = item.grandparentTitle {
            return show
        }
        return item.title
    }

    /// Subtitle for continue watching: natural-language episode label or year.
    func displaySubtitle(for item: PlexItem) -> String? {
        if item.type == .episode {
            return formatEpisode(season: item.parentIndex, episode: item.index) ?? item.title
        }
        return item.year.map(String.init)
    }

    func visibleItems(in hub: PlexHub) -> [PlexItem] {
        hub.items.filter { !shouldHideHomeItem($0) }
    }

    func inlineItems(in hub: PlexHub) -> [PlexItem] {
        let items = visibleItems(in: hub)

        guard isRecentlyAddedHub(hub) else { return items }
        return Array(items.prefix(maxInlineRecentlyAddedItems))
    }

    func shouldShowAll(for hub: PlexHub) -> Bool {
        guard isRecentlyAddedHub(hub), hub.key != nil else { return false }

        let visibleCount = visibleItems(in: hub).count
        return visibleCount > maxInlineRecentlyAddedItems ||
            hub.more == true ||
            (hub.size ?? 0) > maxInlineRecentlyAddedItems
    }

    func isRecentlyAddedHub(_ hub: PlexHub) -> Bool {
        let normalizedTitle = hub.title.lowercased()

        guard normalizedTitle.contains("recently added") else { return false }

        let itemTypes = Set(visibleItems(in: hub).map(\.type))
        return !itemTypes.isEmpty && itemTypes.isSubset(of: [.movie, .show, .season, .episode])
    }

    private func formatEpisode(season: Int?, episode: Int?) -> String? {
        switch (season, episode) {
        case let (s?, e?):
            return "Season \(s) · Episode \(e)"
        case let (nil, e?):
            return "Episode \(e)"
        default:
            return nil
        }
    }

    private func shouldHideHomeHub(_ hub: PlexHub) -> Bool {
        let fields = [hub.title, hub.key, hub.hubIdentifier]
            .compactMap { $0?.lowercased() }

        return fields.contains(where: { value in
            value.contains("continue watching") ||
            value.contains("continuewatching") ||
            value.contains("on deck") ||
            value.contains("ondeck") ||
            value.contains("playlist") ||
            value.contains("playlists")
        })
    }

    private func shouldHideHomeItem(_ item: PlexItem) -> Bool {
        let normalizedKey = item.key.lowercased()

        switch item.type {
        case .artist, .album, .track, .unknown:
            return true
        default:
            return normalizedKey.contains("/playlists/")
        }
    }
}

@MainActor
@Observable
final class HomeHubItemsViewModel {
    let hub: PlexHub

    private let plexService: PlexService

    private(set) var items: [PlexItem] = []
    private(set) var isLoading = false
    private(set) var error: String?

    init(hub: PlexHub, plexService: PlexService) {
        self.hub = hub
        self.plexService = plexService
    }

    var navigationTitle: String {
        normalizedTitle(for: hub.title)
    }

    func loadItems() async {
        guard items.isEmpty else { return }
        await reloadItems()
    }

    func reloadItems() async {
        isLoading = true
        error = nil

        do {
            if let hubKey = hub.key {
                items = try await plexService.getHubItems(hubKey: hubKey)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func setWatched(_ watched: Bool, for item: PlexItem) async {
        do {
            if watched {
                try await plexService.scrobble(ratingKey: item.ratingKey)
            } else {
                try await plexService.unscrobble(ratingKey: item.ratingKey)
            }
            await reloadItems()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func posterURL(for item: PlexItem, width: Int, height: Int) -> URL? {
        plexService.imageURL(for: item.preferredPosterPath, width: width, height: height)
    }

    func progress(for item: PlexItem) -> Double? {
        guard let offset = item.viewOffset, offset > 0,
              let duration = item.duration, duration > 0
        else { return nil }
        return Double(offset) / Double(duration)
    }

    func subtitle(for item: PlexItem) -> String? {
        switch item.type {
        case .movie:
            return item.year.map(String.init)
        case .show:
            if let childCount = item.childCount {
                return "\(childCount) season\(childCount == 1 ? "" : "s")"
            }
            return item.year.map(String.init)
        case .episode:
            return formatEpisode(season: item.parentIndex, episode: item.index) ?? item.grandparentTitle
        default:
            return item.year.map(String.init)
        }
    }

    private func formatEpisode(season: Int?, episode: Int?) -> String? {
        switch (season, episode) {
        case let (s?, e?):
            return "Season \(s) · Episode \(e)"
        case let (nil, e?):
            return "Episode \(e)"
        default:
            return nil
        }
    }

    private func normalizedTitle(for title: String) -> String {
        guard title.lowercased().contains("recently added") else { return title }

        let suffix = title.replacingOccurrences(
            of: "Recently Added",
            with: "",
            options: [.caseInsensitive]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        return suffix.isEmpty ? "Recently added" : "Recently added \(suffix)"
    }
}
