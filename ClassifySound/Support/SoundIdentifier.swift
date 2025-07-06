import Foundation

/// A sound that the app monitors.
struct SoundIdentifier: Hashable {
    /// An internal name that identifies a sound classification.
    var labelName: String

    /// A name suitable for displaying to a user.
    var displayName: String

    init(labelName: String) {
        self.labelName = labelName
        self.displayName = SoundIdentifier.displayNameForLabel(labelName)
    }

    static func displayNameForLabel(_ label: String) -> String {
        let localizationTable = "SoundNames"
        let unlocalized = label
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return Bundle.main.localizedString(
            forKey: unlocalized,
            value: unlocalized,
            table: localizationTable
        )
    }
}
