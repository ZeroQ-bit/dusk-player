import SwiftUI

enum SettingsSupport {
    static let maxSubtitleLanguagePreferenceCount = 5
    static let playbackDefaultsFooterText = "Choose preferred stream quality, default audio, and up to five subtitle languages. Dusk tries subtitle languages from top to bottom. Forced Only limits automatic subtitle selection to forced tracks."
    static let subtitlePreferencesEditorFooterText = "Choose up to five subtitle languages. Dusk tries them in order from top to bottom. To change priority, remove a language and add it again."
    static let subtitlePreferencesSelectionFooterText = "Tap a language to add it. Tap it again to remove it."
    static let subtitlePreferencesSelectionLimitFooterText = "Maximum of five subtitle languages selected. Remove one to add another."

    #if os(tvOS)
    static let playbackBehaviorFooterText = "Auto-Skip automatically skips intros and credits after a brief countdown. Continuous Play shows an Up Next screen after TV episodes finish and can auto-start the next one after the configured delay. Pause After counts the current episode too, then pauses autoplay until you confirm."
    #else
    static let playbackBehaviorFooterText = "Auto-Skip automatically skips intros and credits after a brief countdown. Continuous Play shows an Up Next screen after TV episodes finish and can auto-start the next one after the configured delay. Pause After counts the current episode too, then pauses autoplay until you confirm. Double-Tap to Seek adds left and right double-tap seek zones in the player."
    #endif

    static let playbackAdvancedFooterText = "Force AVPlayer and Force VLCKit bypass automatic engine selection. Enabling one disables the other. Force AVPlayer may fail on formats it cannot handle. Player Debug Overlay shows stream stats during playback."
    static let appearanceFooterText = "System follows your device appearance. Light and Dark override it for the whole app."
    static let aboutFooterText = "Dusk is open source. Visit the repository, learn more about Marvin, or send feedback by email."
    static let accountFooterText = "Clears the saved Plex session and returns to the sign-in flow."
    static let accountManagementFooterText = "Opens your Plex account settings inside Dusk. Plex account deletion is available there."
    static let githubURL = URL(string: "https://github.com/marvinvr/dusk-player")!
    static let aboutMeURL = URL(string: "https://marvinvr.ch")!
    static let feedbackURL = URL(string: "mailto:info@getdusk.app")!
    static let plexAccountURL = URL(string: "https://app.plex.tv/desktop/#!/settings/account")!

    static var subtitleLanguageOptions: [String] {
        var options = [""] + CommonLanguage.allCases.map(\.code)

        if let systemLanguageCode = UserPreferences.systemPreferredSubtitleLanguageCode,
           !options.contains(systemLanguageCode) {
            options.insert(systemLanguageCode, at: 1)
        }

        return options
    }

    static var subtitleSelectableLanguageOptions: [String] {
        subtitleLanguageOptions.filter { !$0.isEmpty }
    }

    static var audioLanguageOptions: [String] {
        CommonLanguage.allCases.map(\.code)
    }

    static var passoutProtectionEpisodeOptions: [Int?] {
        [nil] + Array(1...10).map(Optional.some)
    }

    static func subtitlePreferenceSummary(for languageCodes: [String]) -> String {
        let selectedLanguages = Array(languageCodes.prefix(maxSubtitleLanguagePreferenceCount))
        guard !selectedLanguages.isEmpty else { return "None" }
        return selectedLanguages
            .map(languageDisplayName(for:))
            .joined(separator: " > ")
    }

    static func subtitleDisplayName(for code: String) -> String {
        code.isEmpty ? "None" : languageDisplayName(for: code)
    }

    static func languageDisplayName(for code: String) -> String {
        if let commonLanguage = CommonLanguage(rawValue: code) {
            return commonLanguage.displayName
        }

        return Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    static func passoutProtectionDisplayName(for episodeLimit: Int?) -> String {
        guard let episodeLimit else { return "Disabled" }
        return episodeLimit == 1 ? "1 Episode" : "\(episodeLimit) Episodes"
    }
}

struct SubtitleLanguagePreferencesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguages: [String]
    private let onSave: @MainActor ([String]) -> Void

    init(
        selectedLanguages: [String],
        onSave: @escaping @MainActor ([String]) -> Void
    ) {
        _selectedLanguages = State(
            initialValue: Array(selectedLanguages.prefix(SettingsSupport.maxSubtitleLanguagePreferenceCount))
        )
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if selectedLanguages.isEmpty {
                        Text("No subtitle languages selected")
                            .foregroundStyle(Color.duskTextSecondary)
                    } else {
                        ForEach(Array(selectedLanguages.enumerated()), id: \.element) { index, languageCode in
                            HStack(spacing: 12) {
                                SubtitleLanguagePriorityBadge(rank: index + 1)

                                Text(SettingsSupport.languageDisplayName(for: languageCode))
                                    .foregroundStyle(Color.duskTextPrimary)

                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text("Selected")
                        .foregroundStyle(Color.duskTextSecondary)
                } footer: {
                    Text(SettingsSupport.subtitlePreferencesEditorFooterText)
                        .foregroundStyle(Color.duskTextSecondary)
                }
                .listRowBackground(Color.duskSurface)

                Section {
                    ForEach(SettingsSupport.subtitleSelectableLanguageOptions, id: \.self) { languageCode in
                        Button {
                            toggleSelection(for: languageCode)
                        } label: {
                            HStack(spacing: 12) {
                                Text(SettingsSupport.languageDisplayName(for: languageCode))
                                    .foregroundStyle(Color.duskTextPrimary)

                                Spacer()

                                if let selectedIndex = selectedLanguages.firstIndex(of: languageCode) {
                                    SubtitleLanguagePriorityBadge(rank: selectedIndex + 1)

                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Color.duskAccent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .disabled(!canSelect(languageCode))
                    }
                } header: {
                    Text("All Languages")
                        .foregroundStyle(Color.duskTextSecondary)
                } footer: {
                    Text(selectionFooterText)
                        .foregroundStyle(Color.duskTextSecondary)
                }
                .listRowBackground(Color.duskSurface)
            }
            #if !os(tvOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(Color.duskBackground.ignoresSafeArea())
            .duskNavigationTitle("Subtitles")
            .duskNavigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(selectedLanguages)
                        dismiss()
                    }
                }
            }
        }
        #if !os(tvOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private var selectionFooterText: String {
        if selectedLanguages.count >= SettingsSupport.maxSubtitleLanguagePreferenceCount {
            return SettingsSupport.subtitlePreferencesSelectionLimitFooterText
        }

        return SettingsSupport.subtitlePreferencesSelectionFooterText
    }

    private func canSelect(_ languageCode: String) -> Bool {
        selectedLanguages.contains(languageCode)
            || selectedLanguages.count < SettingsSupport.maxSubtitleLanguagePreferenceCount
    }

    private func toggleSelection(for languageCode: String) {
        if let selectedIndex = selectedLanguages.firstIndex(of: languageCode) {
            selectedLanguages.remove(at: selectedIndex)
        } else if selectedLanguages.count < SettingsSupport.maxSubtitleLanguagePreferenceCount {
            selectedLanguages.append(languageCode)
        }
    }
}

private struct SubtitleLanguagePriorityBadge: View {
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.duskAccent)
            .frame(minWidth: 26, minHeight: 26)
            .background(Color.duskAccent.opacity(0.14), in: Capsule())
    }
}

enum CommonLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case russian = "ru"
    case japanese = "ja"
    case korean = "ko"
    case chinese = "zh"
    case arabic = "ar"
    case hindi = "hi"
    case swedish = "sv"
    case norwegian = "no"
    case danish = "da"
    case finnish = "fi"
    case polish = "pl"
    case czech = "cs"
    case croatian = "hr"
    case serbian = "sr"
    case bosnian = "bs"
    case turkish = "tr"
    case thai = "th"
    case vietnamese = "vi"
    case indonesian = "id"
    case malay = "ms"
    case hebrew = "he"

    var id: String { rawValue }
    var code: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .spanish: "Spanish"
        case .french: "French"
        case .german: "German"
        case .italian: "Italian"
        case .portuguese: "Portuguese"
        case .dutch: "Dutch"
        case .russian: "Russian"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .chinese: "Chinese"
        case .arabic: "Arabic"
        case .hindi: "Hindi"
        case .swedish: "Swedish"
        case .norwegian: "Norwegian"
        case .danish: "Danish"
        case .finnish: "Finnish"
        case .polish: "Polish"
        case .czech: "Czech"
        case .croatian: "Croatian"
        case .serbian: "Serbian"
        case .bosnian: "Bosnian"
        case .turkish: "Turkish"
        case .thai: "Thai"
        case .vietnamese: "Vietnamese"
        case .indonesian: "Indonesian"
        case .malay: "Malay"
        case .hebrew: "Hebrew"
        }
    }
}
