#if os(iOS)
import SwiftUI
import UIKit

struct HomeIOSView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Binding var path: NavigationPath

    let viewModel: HomeViewModel
    let serverName: String?
    let recentlyAddedInlineItemLimit: Int
    let play: (PlexItem) -> Void

    @State private var currentHeroIndex = 0
    @State private var heroRotationRevision = 0
    @State private var isHeroRotationPaused = false
    @State private var heroRotationStartedAt = Date()
    @State private var pausedHeroRotationProgress: Double?
    @State private var transitioningHeroIndex: Int?
    @State private var heroSlideProgress: CGFloat = 1
    @State private var heroSlideRevision = 0
    @State private var heroTransitionDirection: HeroTransitionDirection = .forward
    @State private var preloadedHeroBackdropImages: [String: UIImage] = [:]

    private let heroRotationInterval: UInt64 = 6_000_000_000

    var body: some View {
        applyNavigationChrome(to: content, showsHero: showsCinematicHero)
            .onChange(of: heroItemIDs) { _, ids in
                guard !ids.isEmpty else {
                    resetHeroSlideState()
                    currentHeroIndex = 0
                    return
                }

                if currentHeroIndex >= ids.count {
                    currentHeroIndex = 0
                }

                resetHeroSlideState()
                restartHeroRotation()
            }
            .task(id: heroRotationSeed) {
                await rotateHeroIfNeeded()
            }
    }

    private var content: some View {
        GeometryReader { geometry in
            let heroItems = viewModel.heroItems()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !heroItems.isEmpty {
                        cinematicHeroSection(
                            items: heroItems,
                            containerSize: geometry.size,
                            topInset: geometry.safeAreaInsets.top
                        )
                    } else if showsHomeServerSubtitle, let serverName {
                        homeSubtitle(serverName)
                            .padding(.bottom, 12)
                    }

                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(viewModel.hubs) { hub in
                            let items = viewModel.inlineItems(
                                in: hub,
                                maxRecentlyAddedItems: recentlyAddedInlineItemLimit
                            )

                            if !items.isEmpty {
                                HomeHubCarouselSection(
                                    hub: hub,
                                    items: items,
                                    posterWidth: 130,
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
                    .padding(.top, heroItems.isEmpty ? 0 : 24)
                }
                .padding(.top, heroItems.isEmpty ? (showsHomeServerSubtitle ? -10 : 16) : -geometry.safeAreaInsets.top)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 88)
        }
    }

    @ViewBuilder
    private func cinematicHeroSection(
        items: [PlexItem],
        containerSize: CGSize,
        topInset: CGFloat
    ) -> some View {
        let index = resolvedHeroIndex(for: items)
        let heroWidth = containerSize.width
        let heroHeight = min(max(containerSize.height * 0.72, 520), 760) + topInset
        let backdropWidth = Int(heroWidth.rounded(.up))
        let backdropHeight = Int(heroHeight.rounded(.up))
        let contentWidth = min(max(heroWidth - 40, 0), 620)

        ZStack(alignment: .bottomLeading) {
            ZStack(alignment: .bottomLeading) {
                if let transitioningHeroIndex,
                   items.indices.contains(transitioningHeroIndex) {
                    cinematicHeroSlide(
                        item: items[transitioningHeroIndex],
                        heroHeight: heroHeight,
                        backdropWidth: backdropWidth,
                        backdropHeight: backdropHeight,
                        contentWidth: contentWidth,
                        topInset: topInset,
                        reservesPagerSpace: items.count > 1
                    )
                    .offset(
                        x: heroSlideOffset(
                            for: .outgoing,
                            width: heroWidth
                        )
                    )
                    .id("outgoing-\(items[transitioningHeroIndex].ratingKey)")
                    .zIndex(0)
                }

                if items.indices.contains(index) {
                    cinematicHeroSlide(
                        item: items[index],
                        heroHeight: heroHeight,
                        backdropWidth: backdropWidth,
                        backdropHeight: backdropHeight,
                        contentWidth: contentWidth,
                        topInset: topInset,
                        reservesPagerSpace: items.count > 1
                    )
                    .offset(
                        x: heroSlideOffset(
                            for: .incoming,
                            width: heroWidth
                        )
                    )
                    .id("incoming-\(items[index].ratingKey)")
                    .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if items.count > 1 {
                heroPager(items: items, currentIndex: index)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(height: heroHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .task(id: heroBackdropPrefetchSeed(items: items, width: backdropWidth, height: backdropHeight)) {
            await preloadHeroBackdropImages(
                for: items,
                width: backdropWidth,
                height: backdropHeight
            )
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    handleHeroDrag(value.translation)
                }
        )
    }

    private func cinematicHeroSlide(
        item: PlexItem,
        heroHeight: CGFloat,
        backdropWidth: Int,
        backdropHeight: Int,
        contentWidth: CGFloat,
        topInset: CGFloat,
        reservesPagerSpace: Bool
    ) -> some View {
        let metadata = viewModel.heroMetadata(for: item)

        return ZStack(alignment: .bottomLeading) {
            heroBackdrop(
                for: item,
                width: backdropWidth,
                height: backdropHeight,
                heroHeight: heroHeight
            )

            ZStack {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.86),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.86),
                        Color.black.opacity(0.48),
                        .clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                LinearGradient(
                    colors: [
                        .clear,
                        Color.duskBackground.opacity(0.26),
                        Color.duskBackground,
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.displayTitle(for: item))
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.24), radius: 10, y: 4)
                        .frame(maxWidth: contentWidth, alignment: .leading)

                    if let episodeTitle = viewModel.heroEpisodeTitle(for: item) {
                        Text(episodeTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .lineLimit(2)
                            .frame(maxWidth: contentWidth, alignment: .leading)
                    }

                    if !metadata.isEmpty {
                        Text(metadata.joined(separator: " · "))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.76))
                            .lineLimit(2)
                            .frame(maxWidth: contentWidth, alignment: .leading)
                    }
                }

                if let summary = viewModel.heroSummary(for: item) {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.84))
                        .lineLimit(3)
                        .lineSpacing(4)
                        .frame(maxWidth: contentWidth, alignment: .leading)
                }

                heroActionButton(item: item)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, reservesPagerSpace ? 52 : 28)
            .padding(.top, topInset + 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func heroActionButton(item: PlexItem) -> some View {
        Button {
            restartHeroRotation()
            play(item)
        } label: {
            HomeHeroActionButtonLabel(
                title: viewModel.heroPrimaryActionTitle(for: item),
                systemImage: "play.fill"
            )
        }
        .buttonStyle(HeroPauseAwareButtonStyle(onPress: pauseHeroRotation))
        .duskSuppressTVOSButtonChrome()
        .contextMenu {
            HomeItemContextMenu(
                item: item,
                detailsLabel: heroDetailsLabel(for: item),
                onMarkWatched: {
                    Task { await viewModel.setWatched(true, for: item) }
                },
                onMarkUnwatched: {
                    Task { await viewModel.setWatched(false, for: item) }
                },
                onSelectRoute: { route in
                    path.append(route)
                }
            )
        }
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func heroPager(items: [PlexItem], currentIndex: Int) -> some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { timeline in
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        selectHero(at: index)
                    } label: {
                        HomeHeroPagerPill(
                            isActive: index == currentIndex,
                            progress: index == currentIndex ? heroRotationProgress(at: timeline.date) : 0
                        )
                        .accessibilityLabel(Text(viewModel.displayTitle(for: item)))
                    }
                    .buttonStyle(.plain)
                    .duskSuppressTVOSButtonChrome()
                }
            }
        }
    }

    @ViewBuilder
    private func applyNavigationChrome<Content: View>(to content: Content, showsHero: Bool) -> some View {
        if showsHero {
            content
                .duskNavigationTitle("")
                .duskNavigationBarTitleDisplayModeInline()
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(.hidden, for: .navigationBar)
        } else {
            content
                .duskNavigationTitle("Home")
                .duskNavigationBarTitleDisplayModeLarge()
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func rotateHeroIfNeeded() async {
        guard heroItemIDs.count > 1,
              !accessibilityReduceMotion,
              scenePhase == .active,
              !isHeroRotationPaused else {
            return
        }

        do {
            try await Task.sleep(nanoseconds: remainingHeroRotationNanoseconds(at: Date()))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }

        await MainActor.run {
            guard heroItemIDs.count > 1,
                  !isHeroRotationPaused else { return }

            moveHero(
                to: (currentHeroIndex + 1) % heroItemIDs.count,
                direction: .forward,
                duration: 0.6
            )
            restartHeroRotation()
        }
    }

    private func selectHero(at index: Int) {
        guard index != currentHeroIndex else {
            restartHeroRotation()
            return
        }

        restartHeroRotation()
        moveHero(
            to: index,
            direction: resolvedHeroTransitionDirection(
                from: currentHeroIndex,
                to: index,
                itemCount: heroItemIDs.count
            ),
            duration: 0.5
        )
    }

    private func restartHeroRotation() {
        isHeroRotationPaused = false
        pausedHeroRotationProgress = nil
        heroRotationStartedAt = Date()
        heroRotationRevision += 1
    }

    private func pauseHeroRotation() {
        guard !isHeroRotationPaused else { return }
        isHeroRotationPaused = true
        pausedHeroRotationProgress = heroRotationProgress(at: Date())
        heroRotationRevision += 1
    }

    private func handleHeroDrag(_ translation: CGSize) {
        guard heroItemIDs.count > 1 else { return }
        guard abs(translation.width) > abs(translation.height),
              abs(translation.width) > 44 else {
            return
        }

        restartHeroRotation()

        let heroCount = heroItemIDs.count
        let nextIndex: Int
        if translation.width < 0 {
            nextIndex = (currentHeroIndex + 1) % heroCount
        } else {
            nextIndex = (currentHeroIndex - 1 + heroCount) % heroCount
        }

        moveHero(
            to: nextIndex,
            direction: translation.width < 0 ? .forward : .backward,
            duration: 0.5
        )
    }

    private func resolvedHeroIndex(for items: [PlexItem]) -> Int {
        guard !items.isEmpty else { return 0 }
        return min(currentHeroIndex, items.count - 1)
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

    private var showsCinematicHero: Bool {
        !viewModel.heroItems().isEmpty
    }

    private var heroItemIDs: [String] {
        viewModel.heroItems().map(\.ratingKey)
    }

    private var heroRotationSeed: String {
        [
            heroItemIDs.joined(separator: "|"),
            String(heroRotationRevision),
            String(accessibilityReduceMotion),
            String(scenePhase == .active),
            String(isHeroRotationPaused),
        ].joined(separator: "::")
    }

    private func heroDetailsLabel(for item: PlexItem) -> String {
        switch item.type {
        case .episode:
            return "Go to Episode"
        case .season:
            return "Go to Season"
        case .show:
            return "Go to Show"
        case .movie:
            return "Go to Movie"
        default:
            return "View Details"
        }
    }

    private var heroRotationDuration: TimeInterval {
        Double(heroRotationInterval) / 1_000_000_000
    }

    private func heroRotationProgress(at date: Date) -> Double {
        if let pausedHeroRotationProgress {
            return max(0, min(pausedHeroRotationProgress, 1))
        }

        let elapsed = date.timeIntervalSince(heroRotationStartedAt)
        guard heroRotationDuration > 0 else { return 0 }
        return max(0, min(elapsed / heroRotationDuration, 1))
    }

    private func remainingHeroRotationNanoseconds(at date: Date) -> UInt64 {
        let progress = heroRotationProgress(at: date)
        let remaining = max(0, 1 - progress) * heroRotationDuration
        return UInt64((remaining * 1_000_000_000).rounded())
    }

    private func resetHeroSlideState() {
        heroSlideRevision += 1
        transitioningHeroIndex = nil
        heroSlideProgress = 1
    }

    private func heroBackdropPrefetchSeed(items: [PlexItem], width: Int, height: Int) -> String {
        [
            items.map(\.ratingKey).joined(separator: "|"),
            "\(width)x\(height)"
        ].joined(separator: "::")
    }

    private func preloadHeroBackdropImages(
        for items: [PlexItem],
        width: Int,
        height: Int
    ) async {
        let backdropRequests = items.compactMap { item -> (String, URL)? in
            guard let url = viewModel.heroBackgroundURL(for: item, width: width, height: height) else {
                return nil
            }

            return (item.ratingKey, url)
        }

        let validKeys = Set(items.map(\.ratingKey))
        await MainActor.run {
            preloadedHeroBackdropImages = preloadedHeroBackdropImages.filter { validKeys.contains($0.key) }
        }

        guard !backdropRequests.isEmpty else { return }

        var loadedImages: [String: UIImage] = [:]

        await withTaskGroup(of: (String, UIImage?).self) { group in
            for (ratingKey, url) in backdropRequests {
                group.addTask {
                    do {
                        let image = try await DuskImageLoader.shared.image(for: url)
                        return (ratingKey, image)
                    } catch {
                        return (ratingKey, nil)
                    }
                }
            }

            for await (ratingKey, image) in group {
                if let image {
                    loadedImages[ratingKey] = image
                }
            }
        }

        guard !loadedImages.isEmpty else { return }

        await MainActor.run {
            for (ratingKey, image) in loadedImages {
                guard validKeys.contains(ratingKey) else { continue }
                preloadedHeroBackdropImages[ratingKey] = image
            }
        }
    }
}

private enum HeroTransitionDirection {
    case forward
    case backward
}

private enum HeroSlideRole {
    case outgoing
    case incoming
}

private extension HomeIOSView {
    @ViewBuilder
    func heroBackdrop(
        for item: PlexItem,
        width: Int,
        height: Int,
        heroHeight: CGFloat
    ) -> some View {
        if let image = preloadedHeroBackdropImages[item.ratingKey] {
            GeometryReader { geometry in
                ZStack {
                    Color.duskSurface

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height,
                            alignment: .center
                        )
                        .clipped()
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                .clipped()
            }
            .frame(height: heroHeight)
            .frame(maxWidth: .infinity)
        } else {
            DetailHeroBackdrop(
                imageURL: viewModel.heroBackgroundURL(
                    for: item,
                    width: width,
                    height: height
                ),
                height: heroHeight
            )
        }
    }

    func moveHero(to index: Int, direction: HeroTransitionDirection, duration: TimeInterval) {
        let previousIndex = currentHeroIndex
        let slideRevision = heroSlideRevision + 1

        heroSlideRevision = slideRevision
        heroTransitionDirection = direction
        transitioningHeroIndex = previousIndex
        currentHeroIndex = index
        heroSlideProgress = 0

        withAnimation(.easeInOut(duration: duration)) {
            heroSlideProgress = 1
        }

        Task {
            try? await Task.sleep(
                nanoseconds: UInt64((duration * 1_000_000_000).rounded())
            )

            await MainActor.run {
                guard heroSlideRevision == slideRevision else { return }
                transitioningHeroIndex = nil
                heroSlideProgress = 1
            }
        }
    }

    func heroSlideOffset(for role: HeroSlideRole, width: CGFloat) -> CGFloat {
        guard transitioningHeroIndex != nil else { return 0 }

        switch (heroTransitionDirection, role) {
        case (.forward, .outgoing):
            return -width * heroSlideProgress
        case (.forward, .incoming):
            return width * (1 - heroSlideProgress)
        case (.backward, .outgoing):
            return width * heroSlideProgress
        case (.backward, .incoming):
            return -width * (1 - heroSlideProgress)
        }
    }

    func resolvedHeroTransitionDirection(
        from currentIndex: Int,
        to nextIndex: Int,
        itemCount: Int
    ) -> HeroTransitionDirection {
        guard itemCount > 1, currentIndex != nextIndex else { return .forward }

        let forwardDistance = nextIndex >= currentIndex
            ? nextIndex - currentIndex
            : itemCount - currentIndex + nextIndex
        let backwardDistance = currentIndex >= nextIndex
            ? currentIndex - nextIndex
            : currentIndex + itemCount - nextIndex

        return forwardDistance <= backwardDistance ? .forward : .backward
    }
}
#endif
