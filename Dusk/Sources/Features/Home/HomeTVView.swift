import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HomeTVView: View {
    @FocusState private var focusedTarget: FocusTarget?
    @State private var heroPrimaryFocusView: UIView?

    @Binding var path: NavigationPath

    let viewModel: HomeViewModel
    let serverName: String?
    let recentlyAddedInlineItemLimit: Int
    let play: (PlexItem) -> Void

    private enum FocusTarget: Hashable {
        case heroPrimaryAction
    }

    var body: some View {
        GeometryReader { geometry in
            let heroItems = viewModel.heroItems()
            let heroItemIDs = heroItems.map(\.id)
            let globalFrame = geometry.frame(in: .global)
            let screenWidth = max(fullDisplayWidth(fallback: geometry.size.width), geometry.size.width)
            let leadingContentInset = max(globalFrame.minX, 0)
            let trailingContentInset = max(screenWidth - globalFrame.maxX, 0)
            let heroContainerSize = CGSize(
                width: screenWidth,
                height: geometry.size.height
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !heroItems.isEmpty {
                        HomeCinematicHero(
                            items: heroItems,
                            viewModel: viewModel,
                            containerSize: heroContainerSize,
                            topInset: geometry.safeAreaInsets.top,
                            contentLeadingInset: leadingContentInset,
                            contentTrailingInset: trailingContentInset,
                            layout: .tv,
                            autoRotates: true,
                            supportsDragNavigation: false,
                            primaryAction: { item, callbacks in
                                AnyView(
                                    Button {
                                        callbacks.restartRotation()
                                        play(item)
                                    } label: {
                                        HomeHeroActionButtonLabel(
                                            title: viewModel.heroPrimaryActionTitle(for: item),
                                            systemImage: "play.fill"
                                        )
                                    }
                                    #if os(tvOS)
                                    .buttonStyle(.glassProminent)
                                    .tint(Color.duskAccent)
                                    .focused($focusedTarget, equals: .heroPrimaryAction)
                                    .background(
                                        TVRemoteSwipeCapture(
                                            isEnabled: focusedTarget == .heroPrimaryAction,
                                            onResolvedFocusView: { view in
                                                heroPrimaryFocusView = view
                                            },
                                            onSwipeLeft: callbacks.showPrevious,
                                            onSwipeRight: callbacks.showNext
                                        )
                                    )
                                    #endif
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
                                        .onAppear {
                                            callbacks.pauseRotation()
                                        }
                                        .onDisappear {
                                            callbacks.restartRotation()
                                        }
                                    }
                                    .accessibilityAddTraits(.isButton)
                                )
                            }
                        )
                        .frame(width: heroContainerSize.width)
                        .offset(x: -leadingContentInset)
                        .ignoresSafeArea(edges: .top)
                        #if os(tvOS)
                        .focusSection()
                        #endif
                    } else if let serverName {
                        homeHeader(serverName: serverName)
                            .padding(.horizontal, DuskPosterMetrics.carouselHorizontalPadding)
                            .padding(.top, DuskPosterMetrics.pageSectionSpacing)
                    }

                    LazyVStack(alignment: .leading, spacing: DuskPosterMetrics.pageSectionSpacing) {
                        ForEach(viewModel.hubs) { hub in
                            let items = viewModel.inlineItems(
                                in: hub,
                                maxRecentlyAddedItems: recentlyAddedInlineItemLimit
                            )

                            if !items.isEmpty {
                                HomeHubCarouselSection(
                                    hub: hub,
                                    items: items,
                                    posterWidth: DuskPosterMetrics.carouselPosterWidth,
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

                        ForEach(viewModel.personalizedShelves) { shelf in
                            if !shelf.items.isEmpty {
                                HomePersonalizedCarouselSection(
                                    shelf: shelf,
                                    posterWidth: DuskPosterMetrics.carouselPosterWidth,
                                    showAllRoute: viewModel.showAllRoute(for: shelf),
                                    subtitle: { item in
                                        viewModel.subtitle(for: item)
                                    },
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
                    .padding(.top, heroItems.isEmpty ? 56 : 44)
                    .padding(.bottom, DuskPosterMetrics.pageBottomPadding)
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
                .frame(width: geometry.size.width, alignment: .leading)
                .padding(.top, heroItems.isEmpty ? 24 : -geometry.safeAreaInsets.top)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.zero, for: .scrollContent)
            .contentMargins(.zero, for: .scrollIndicators)
            .scrollIndicators(.hidden)
            #if os(tvOS)
            .scrollClipDisabled()
            #endif
            .background(
                TVHomeTopFocusGuide(targetView: heroPrimaryFocusView)
            )
            .defaultFocus($focusedTarget, .heroPrimaryAction)
            .task(id: heroItemIDs) {
                await requestHeroPrimaryFocusIfNeeded(hasHeroItems: !heroItems.isEmpty)
            }
        }
    }

    @MainActor
    private func requestHeroPrimaryFocusIfNeeded(hasHeroItems: Bool) async {
        guard hasHeroItems else { return }

        // tvOS initially lands on the tab bar; yielding once lets the home content
        // enter the hierarchy before we redirect focus to the hero action.
        focusedTarget = nil
        await Task.yield()
        focusedTarget = .heroPrimaryAction
    }

    private func fullDisplayWidth(fallback: CGFloat) -> CGFloat {
        #if canImport(UIKit)
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) {
            return windowScene.screen.bounds.width
        }

        return fallback
        #else
        fallback
        #endif
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

#if os(tvOS)
private struct TVRemoteSwipeCapture: UIViewRepresentable {
    let isEnabled: Bool
    let onResolvedFocusView: (UIView?) -> Void
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    func makeUIView(context: Context) -> SwipeCaptureView {
        let view = SwipeCaptureView()
        view.backgroundColor = .clear
        view.update(
            isEnabled: isEnabled,
            onResolvedFocusView: onResolvedFocusView,
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight
        )
        return view
    }

    func updateUIView(_ uiView: SwipeCaptureView, context: Context) {
        uiView.update(
            isEnabled: isEnabled,
            onResolvedFocusView: onResolvedFocusView,
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight
        )
    }
}

private final class SwipeCaptureView: UIView, UIGestureRecognizerDelegate {
    private weak var attachedView: UIView?
    private lazy var swipeLeftRecognizer: UISwipeGestureRecognizer = {
        let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        recognizer.direction = .left
        recognizer.delegate = self
        return recognizer
    }()
    private lazy var swipeRightRecognizer: UISwipeGestureRecognizer = {
        let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        recognizer.direction = .right
        recognizer.delegate = self
        return recognizer
    }()

    private var isSwipeCaptureEnabled = false
    private var onResolvedFocusView: (UIView?) -> Void = { _ in }
    private var onSwipeLeft: () -> Void = {}
    private var onSwipeRight: () -> Void = {}

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        attachRecognizersIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachRecognizersIfNeeded()
    }

    override func willMove(toSuperview newSuperview: UIView?) {
        if newSuperview == nil {
            detachRecognizers()
        }

        super.willMove(toSuperview: newSuperview)
    }

    func update(
        isEnabled: Bool,
        onResolvedFocusView: @escaping (UIView?) -> Void,
        onSwipeLeft: @escaping () -> Void,
        onSwipeRight: @escaping () -> Void
    ) {
        isSwipeCaptureEnabled = isEnabled
        self.onResolvedFocusView = onResolvedFocusView
        self.onSwipeLeft = onSwipeLeft
        self.onSwipeRight = onSwipeRight
        attachRecognizersIfNeeded()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc
    private func handleSwipe(_ recognizer: UISwipeGestureRecognizer) {
        guard isSwipeCaptureEnabled else { return }

        switch recognizer.direction {
        case .left:
            onSwipeLeft()
        case .right:
            onSwipeRight()
        default:
            break
        }
    }

    private func attachRecognizersIfNeeded() {
        guard let targetView = superview else { return }
        guard attachedView !== targetView else { return }

        detachRecognizers()
        targetView.addGestureRecognizer(swipeLeftRecognizer)
        targetView.addGestureRecognizer(swipeRightRecognizer)
        attachedView = targetView
        onResolvedFocusView(targetView)
    }

    private func detachRecognizers() {
        attachedView?.removeGestureRecognizer(swipeLeftRecognizer)
        attachedView?.removeGestureRecognizer(swipeRightRecognizer)
        attachedView = nil
        onResolvedFocusView(nil)
    }
}

private struct TVHomeTopFocusGuide: UIViewRepresentable {
    let targetView: UIView?

    func makeUIView(context: Context) -> HomeTopFocusGuideView {
        let view = HomeTopFocusGuideView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.updateTargetView(targetView)
        return view
    }

    func updateUIView(_ uiView: HomeTopFocusGuideView, context: Context) {
        uiView.updateTargetView(targetView)
    }
}

private final class HomeTopFocusGuideView: UIView {
    private weak var guideContainerView: UIView?
    private weak var targetView: UIView?
    private let focusGuide = UIFocusGuide()
    private var focusGuideConstraints: [NSLayoutConstraint] = []

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        installFocusGuideIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installFocusGuideIfNeeded()
    }

    override func willMove(toSuperview newSuperview: UIView?) {
        if newSuperview == nil {
            uninstallFocusGuide()
        }

        super.willMove(toSuperview: newSuperview)
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        updateGuideEnabled(for: context.nextFocusedView)
    }

    func updateTargetView(_ targetView: UIView?) {
        self.targetView = targetView
        installFocusGuideIfNeeded()
        focusGuide.preferredFocusEnvironments = targetView.map { [$0] } ?? []
        focusGuide.isEnabled = targetView != nil
    }

    private func installFocusGuideIfNeeded() {
        guard let containerView = superview else { return }

        if guideContainerView !== containerView {
            uninstallFocusGuide()

            containerView.addLayoutGuide(focusGuide)
            focusGuideConstraints = [
                focusGuide.topAnchor.constraint(equalTo: containerView.topAnchor),
                focusGuide.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                focusGuide.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                focusGuide.heightAnchor.constraint(equalToConstant: 220)
            ]
            NSLayoutConstraint.activate(focusGuideConstraints)
            guideContainerView = containerView
        }

        focusGuide.preferredFocusEnvironments = targetView.map { [$0] } ?? []
    }

    private func uninstallFocusGuide() {
        NSLayoutConstraint.deactivate(focusGuideConstraints)
        focusGuideConstraints.removeAll()

        if let guideContainerView {
            guideContainerView.removeLayoutGuide(focusGuide)
        }

        guideContainerView = nil
    }

    private func updateGuideEnabled(for nextFocusedView: UIView?) {
        guard let guideContainerView else {
            focusGuide.isEnabled = targetView != nil
            return
        }

        let nextIsInsideHome = nextFocusedView?.isDescendant(of: guideContainerView) ?? false
        focusGuide.isEnabled = targetView != nil && !nextIsInsideHome
    }
}
#endif
