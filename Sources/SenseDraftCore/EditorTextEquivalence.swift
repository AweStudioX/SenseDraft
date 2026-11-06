import Foundation

public enum EditorTextEquivalence {
    /// Separate Copy operations can normalize line endings or omit an editor's
    /// trailing zero-width placeholder without changing the visible draft.
    public static func matchesRepeatedCopies(_ first: String, _ second: String) -> Bool {
        repeatedCopyDifference(first, second) != "content"
    }

    public static func repeatedCopyDifference(_ first: String, _ second: String) -> String {
        if first == second { return "exact" }
        let firstLines = normalizedLineEndings(first)
        let secondLines = normalizedLineEndings(second)
        if firstLines == secondLines { return "lineEndings" }
        let firstVisible = withoutTrailingPlaceholders(firstLines)
        let secondVisible = withoutTrailingPlaceholders(secondLines)
        if firstVisible == secondVisible { return "trailingPlaceholder" }
        if firstVisible.precomposedStringWithCanonicalMapping
            == secondVisible.precomposedStringWithCanonicalMapping { return "unicodeNormalization" }
        return "content"
    }

    private static func normalizedLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Chromium contenteditable fields may expose trailing zero-width placeholder
    /// lines through Accessibility that are absent from Select All / Copy.
    public static func matchesAccessibilityAndCopy(accessibility: String, copied: String) -> Bool {
        if accessibility == copied { return true }
        return withoutTrailingPlaceholders(accessibility) == copied
    }

    /// Use only after a fresh Accessibility read has already confirmed that the
    /// editor still contains the captured source. Some rich editors append one
    /// copy-only paragraph terminator to Select All / Copy.
    public static func matchesVerifiedAccessibilityAndCopy(accessibility: String,
                                                           copied: String) -> Bool {
        if matchesAccessibilityAndCopy(accessibility: accessibility, copied: copied) { return true }
        let visible = withoutTrailingPlaceholders(normalizedLineEndings(accessibility))
        return normalizedLineEndings(copied) == visible + "\n"
    }

    public static func matchesAccessibilityValues(_ first: String, _ second: String) -> Bool {
        if first == second { return true }
        return withoutTrailingPlaceholders(first) == withoutTrailingPlaceholders(second)
    }

    private static func withoutTrailingPlaceholders(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var end = scalars.count
        var removedPlaceholder = false
        while end > 0 {
            if scalars[end - 1] == "\u{200B}" {
                end -= 1
                removedPlaceholder = true
            } else if scalars[end - 1] == "\n", end > 1, scalars[end - 2] == "\u{200B}" {
                end -= 1
            } else {
                break
            }
        }
        guard removedPlaceholder else { return text }
        return String(String.UnicodeScalarView(scalars.prefix(end)))
    }
}
