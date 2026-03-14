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

                List {
                    Section {
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

                        ForEach(servers) { server in
                            Button {
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
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(server.name)
                                            .font(.headline)
                                            .foregroundStyle(Color.duskTextPrimary)

                                        Text(server.owned ? "Your server" : "Shared by \(server.sourceTitle ?? "Unknown")")
                                            .font(.caption)
                                            .foregroundStyle(Color.duskTextSecondary)
                                    }

                                    Spacer()

                                    if connectingTo == server.clientIdentifier {
                                        ProgressView()
                                            .tint(Color.duskAccent)
                                    } else {
                                        Circle()
                                            .fill(server.presence ? Color.duskAccent : Color.duskTextSecondary)
                                            .frame(width: 8, height: 8)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .disabled(connectingTo != nil)
                            .duskSuppressTVOSButtonChrome()
                            .listRowBackground(Color.duskSurface)
                        }

                        if let onSignOut {
                            Button("Sign Out", role: .destructive, action: onSignOut)
                                .duskSuppressTVOSButtonChrome()
                                .listRowBackground(Color.duskSurface)
                        }
                    } header: {
                        Text("Your Plex account has access to multiple servers. Pick the one you'd like to use — you can switch anytime from Settings.")
                            .font(.subheadline)
                            .foregroundStyle(Color.duskTextSecondary)
                            .textCase(nil)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                    }
                }
                .duskScrollContentBackgroundHidden()
                .duskNavigationTitle("Choose Server")
            }
        }
    }
}
