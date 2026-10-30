import Foundation

enum Subtitles {
    /// Index of the subtitle option to show: the first viewer-preferred language offered, else the first option.
    static func option(languages: [String?], preferred: [String], enabled: Bool) -> Int? {
        guard enabled, !languages.isEmpty else { return nil }
        let offered = languages.map { $0.map(base) }
        for language in preferred {
            if let index = offered.firstIndex(of: base(language)) { return index }
        }
        return 0
    }
    /// Collapses "eng", "en" and "en-US" to "en"; unknown codes compare as written.
    private static func base(_ code: String) -> String {
        Locale.Language(identifier: code).languageCode?.identifier(.alpha2) ?? code.lowercased()
    }
}
