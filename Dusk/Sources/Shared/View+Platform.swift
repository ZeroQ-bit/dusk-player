import SwiftUI

extension View {
    @ViewBuilder
    func duskNavigationTitle(_ title: String) -> some View {
        #if os(tvOS)
        self
        #else
        self.navigationTitle(title)
        #endif
    }

    @ViewBuilder
    func duskNavigationBarTitleDisplayModeInline() -> some View {
        #if os(tvOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    func duskNavigationBarTitleDisplayModeLarge() -> some View {
        #if os(tvOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.large)
        #endif
    }

    @ViewBuilder
    func duskScrollContentBackgroundHidden() -> some View {
        #if os(tvOS)
        self
        #else
        self.scrollContentBackground(.hidden)
        #endif
    }

    @ViewBuilder
    func duskListRowSeparatorHidden() -> some View {
        #if os(tvOS)
        self
        #else
        self.listRowSeparator(.hidden)
        #endif
    }

    @ViewBuilder
    func duskStatusBarHidden() -> some View {
        #if os(tvOS)
        self
        #else
        self.statusBarHidden()
        #endif
    }

    @ViewBuilder
    func duskSuppressTVOSButtonChrome() -> some View {
        #if os(tvOS)
        self.buttonStyle(.plain)
        #else
        self
        #endif
    }

    @ViewBuilder
    func duskTVOSFocusEffectShape<S: Shape>(_ shape: S) -> some View {
        #if os(tvOS)
        self
            .contentShape(.interaction, shape)
            .contentShape(.hoverEffect, shape)
        #else
        self
        #endif
    }
}

struct DetailHeroBackdrop: View {
    let imageURL: URL?
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.duskSurface

                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: geometry.size.width,
                                    height: geometry.size.height,
                                    alignment: .center
                                )
                                .clipped()
                        default:
                            Color.clear
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            .clipped()
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}
