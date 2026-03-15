import Foundation

struct LibraryGenreOption: Hashable, Identifiable {
    static let all = LibraryGenreOption(title: "All Genres", value: nil)

    var id: String { value ?? "__all__" }

    let title: String
    let value: String?
}

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case titleAscending
    case titleDescending
    case yearDescending
    case yearAscending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .titleAscending:
            "Title A-Z"
        case .titleDescending:
            "Title Z-A"
        case .yearDescending:
            "Year Newest"
        case .yearAscending:
            "Year Oldest"
        }
    }

    var plexValue: String {
        switch self {
        case .titleAscending:
            "titleSort"
        case .titleDescending:
            "titleSort:desc"
        case .yearDescending:
            "year:desc"
        case .yearAscending:
            "year"
        }
    }
}

private struct LibraryItemsQuery: Equatable {
    let genreValue: String?
    let sort: LibrarySortOption
}

@MainActor
@Observable
final class LibraryItemsViewModel {
    private let plexService: PlexService
    let library: PlexLibrary

    private(set) var items: [PlexItem] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var error: String?
    private(set) var hasMoreItems = true
    private(set) var availableGenres: [LibraryGenreOption] = [.all]
    private(set) var selectedGenre: LibraryGenreOption = .all
    private(set) var selectedSort: LibrarySortOption = .titleAscending

    private let pageSize = 50
    private var hasLoadedBrowseOptions = false
    private var queryGeneration = 0

    init(library: PlexLibrary, plexService: PlexService) {
        self.library = library
        self.plexService = plexService
    }

    var showsBrowseControls: Bool {
        !items.isEmpty || selectedGenre != .all || availableGenres.count > 1
    }

    var emptyStateTitle: String {
        selectedGenre == .all ? "This library is empty" : "No matching titles"
    }

    var emptyStateMessage: String? {
        guard selectedGenre != .all else { return nil }
        return "Try another genre or switch back to all titles."
    }

    func loadItems() async {
        await loadBrowseOptionsIfNeeded()

        guard items.isEmpty else { return }
        await reloadItems()
    }

    func reloadItems() async {
        let generation = beginNewQuery()
        isLoading = true
        error = nil

        do {
            let fetched = try await fetchItems(start: 0, query: currentQuery)
            guard generation == queryGeneration else { return }

            items = fetched
            hasMoreItems = fetched.count >= pageSize
        } catch {
            guard generation == queryGeneration else { return }

            items = []
            hasMoreItems = false
            self.error = error.localizedDescription
        }

        guard generation == queryGeneration else { return }
        isLoading = false
    }

    func selectGenre(_ genre: LibraryGenreOption) async {
        guard selectedGenre != genre else { return }
        selectedGenre = genre
        await reloadItems()
    }

    func selectSort(_ sort: LibrarySortOption) async {
        guard selectedSort != sort else { return }
        selectedSort = sort
        await reloadItems()
    }

    func setWatched(_ watched: Bool, for item: PlexItem) async {
        do {
            try await plexService.setWatched(watched, ratingKey: item.ratingKey)
            await reloadItems()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentItem: PlexItem) async {
        guard hasMoreItems, !isLoadingMore,
              let index = items.firstIndex(where: { $0.id == currentItem.id }),
              index >= items.count - 10
        else { return }

        let generation = queryGeneration
        let start = items.count
        let query = currentQuery

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let fetched = try await fetchItems(start: start, query: query)
            guard generation == queryGeneration else { return }

            items.append(contentsOf: fetched)
            hasMoreItems = fetched.count >= pageSize
        } catch {
            guard generation == queryGeneration else { return }
            hasMoreItems = false
        }
    }

    func posterURL(for item: PlexItem, width: Int, height: Int) -> URL? {
        plexService.imageURL(for: item.preferredPosterPath, width: width, height: height)
    }

    func progress(for item: PlexItem) -> Double? {
        MediaTextFormatter.progress(durationMs: item.duration, offsetMs: item.viewOffset)
    }

    func subtitle(for item: PlexItem) -> String? {
        switch item.type {
        case .movie:
            return item.year.map(String.init)
        case .show:
            if let childCount = item.childCount {
                return MediaTextFormatter.seasonCount(childCount)?.lowercased()
            }
            return item.year.map(String.init)
        default:
            return item.year.map(String.init)
        }
    }

    private var currentQuery: LibraryItemsQuery {
        LibraryItemsQuery(genreValue: selectedGenre.value, sort: selectedSort)
    }

    private func beginNewQuery() -> Int {
        queryGeneration += 1
        hasMoreItems = true
        isLoadingMore = false
        return queryGeneration
    }

    private func fetchItems(start: Int, query: LibraryItemsQuery) async throws -> [PlexItem] {
        var filters: [String: String] = [:]

        if let genreValue = query.genreValue {
            filters["genre"] = genreValue
        }

        return try await plexService.getLibraryItems(
            sectionId: library.key,
            start: start,
            size: pageSize,
            sort: query.sort.plexValue,
            filters: filters
        )
    }

    private func loadBrowseOptionsIfNeeded() async {
        guard !hasLoadedBrowseOptions else { return }
        hasLoadedBrowseOptions = true

        do {
            let filters = try await plexService.getLibraryFilters(sectionId: library.key)

            guard let genreFilter = filters.first(where: {
                $0.filter.localizedCaseInsensitiveCompare("genre") == .orderedSame
            }) else {
                return
            }

            let values = try await plexService.getLibraryFilterValues(path: genreFilter.key)
            let genres = values
                .compactMap { Self.genreOption(from: $0, parameterName: genreFilter.filter) }
                .sorted {
                    $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }

            if !genres.isEmpty {
                availableGenres = [.all] + genres
            }
        } catch {
            availableGenres = [.all]
        }
    }

    private static func genreOption(
        from filterValue: PlexLibraryFilterValue,
        parameterName: String
    ) -> LibraryGenreOption? {
        guard let value = extractFilterValue(from: filterValue.key, parameterName: parameterName),
              !value.isEmpty else {
            return nil
        }

        return LibraryGenreOption(title: filterValue.title, value: value)
    }

    private static func extractFilterValue(from key: String, parameterName: String) -> String? {
        if let components = URLComponents(string: key),
           let queryItems = components.queryItems,
           let value = queryItems.first(where: { $0.name == parameterName })?.value {
            return value
        }

        if key.hasPrefix("/") {
            return key.split(separator: "/").last.map(String.init)
        }

        return key.isEmpty ? nil : key
    }
}
