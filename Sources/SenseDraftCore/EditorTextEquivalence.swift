public enum EditorTextEquivalence {
    /// Chromium contenteditable fields may expose trailing zero-width placeholder
    /// lines through Accessibility that are absent from Select All / Copy.
    public static func matchesAccessibilityAndCopy(accessibility: String, copied: String) -> Bool {
        if accessibility == copied { return true }
        return withoutTrailingPlaceholders(accessibility) == copied
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
