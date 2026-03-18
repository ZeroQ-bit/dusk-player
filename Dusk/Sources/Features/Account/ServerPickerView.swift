import SwiftUI

struct ServerPickerView: View {
    let servers: [PlexServer]
    let onSelect: (PlexServer) async throws -> Void
    var onSignOut: (() -> Void)? = nil
    @State private var connectingTo: String?
    @State private var connectionError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.duskBackground.ignoresSafeArea()

                serverPickerContent
            }
        }
    }

    @ViewBuilder
    private var serverPickerContent: some View {
        #if os(tvOS)
        tvServerPickerContent
        #else
        iosServerPickerContent
        #endif
    }

    private var iosServerPickerContent: some View {
        List {
            Section {
                connectionErrorRow

                ForEach(servers) { server in
                    serverButton(server)
                        .listRowBackground(Color.duskSurface)
                }

                if let onSignOut {
                    Button("Sign Out", role: .destructive, action: onSignOut)
                        .duskSuppressTVOSButtonChrome()
                        .listRowBackground(Color.duskSurface)
                }
            } header: {
                serverPickerDescription
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
            }
        }
        .duskScrollContentBackgroundHidden()
        .duskNavigationTitle("Choose Server")
    }

    private var tvServerPickerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose Server")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.duskTextPrimary)

                    serverPickerDescription
                        .frame(maxWidth: 780, alignment: .leading)
                }

                if let connectionError {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color.duskTextSecondary)
                        Text(connectionError)
                            .font(.body)
                            .foregroundStyle(Color.duskTextSecondary)
                    }
                    .padding(20)
                    .background(Color.duskSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }

                VStack(spacing: 16) {
                    ForEach(servers) { server in
                        serverButton(server)
                    }
                }

                if let onSignOut {
                    Button("Sign Out", role: .destructive, action: onSignOut)
                        .font(.headline)
                        .foregroundStyle(.red)
                        .duskSuppressTVOSButtonChrome()
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 60)
            .padding(.vertical, 48)
        }
    }

    @ViewBuilder
    private var connectionErrorRow: some View {
        if let connectionError {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.duskTextSecondary)

                Text(connectionError)
                    .font(.callout)
                    .foregroundStyle(Color.duskTextSecondary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.duskSurface)
        }
    }

    private var serverPickerDescription: some View {
        Text("Your Plex account has access to multiple servers. Pick the one you'd like to use — you can switch anytime from Settings.")
            .font(.subheadline)
            .foregroundStyle(Color.duskTextSecondary)
            .textCase(nil)
    }

    private func serverButton(_ server: PlexServer) -> some View {
        Button {
            connect(to: server)
        } label: {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(server.name)
                        .font(.headline)
                        .foregroundStyle(Color.duskTextPrimary)

                    Text(server.owned ? "Your server" : "Shared by \(server.sourceTitle ?? "Unknown")")
                        .font(.subheadline)
                        .foregroundStyle(Color.duskTextSecondary)
                }

                Spacer()

                if connectingTo == server.clientIdentifier {
                    ProgressView()
                        .tint(Color.duskAccent)
                } else {
                    Circle()
                        .fill(server.presence ? Color.duskAccent : Color.duskTextSecondary)
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.duskSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .duskTVOSFocusEffectShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .disabled(connectingTo != nil)
        .duskSuppressTVOSButtonChrome()
    }

    private func connect(to server: PlexServer) {
        connectionError = nil
        connectingTo = server.clientIdentifier

        Task {
            do {
                try await onSelect(server)
            } catch {
                connectionError = "Could not connect to \(server.name): \(error.localizedDescription)"
                connectingTo = nil
            }
        }
    }
}
