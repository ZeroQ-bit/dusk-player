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

    private let heroRotationInterval: UInt64 = 5_000_000_000

    var body: some View {
        applyNavigationChrome(to: content, showsHero: showsCinematicHero)
            .onChange(of: heroItemIDs) { _, ids in
                guard !ids.isEmpty else {
                    currentHeroIndex = 0
                    return
                }

                if currentHeroIndex >= ids.count {
                    currentHeroIndex = 0
                }

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
        let item = items[index]
        let heroWidth = containerSize.width
        let heroHeight = min(max(containerSize.height * 0.72, 520), 760) + topInset
        let backdropWidth = Int(heroWidth.rounded(.up))
        let backdropHeight = Int(heroHeight.rounded(.up))
        let contentWidth = min(max(heroWidth - 40, 0), 620)
        let metadata = viewModel.heroMetadata(for: item)

        ZStack(alignment: .bottomLeading) {
            DetailHeroBackdrop(
                imageURL: viewModel.heroBackgroundURL(
                    for: item,
                    width: backdropWidth,
                    height: backdropHeight
                ),
                height: heroHeight
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

                if items.count > 1 {
                    heroPager(items: items, currentIndex: index)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .padding(.top, topInset + 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: heroHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    handleHeroDrag(value.translation)
                }
        )
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

            withAnimation(.easeInOut(duration: 0.7)) {
                currentHeroIndex = (currentHeroIndex + 1) % heroItemIDs.count
            }
            restartHeroRotation()
        }
    }

    private func selectHero(at index: Int) {
        guard index != currentHeroIndex else {
            restartHeroRotation()
            return
        }

        restartHeroRotation()
        withAnimation(.easeInOut(duration: 0.5)) {
            currentHeroIndex = index
        }
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

        withAnimation(.easeInOut(duration: 0.45)) {
            currentHeroIndex = nextIndex
        }
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
}
#endif
