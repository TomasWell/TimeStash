import Foundation

/// Localization helpers.
///
/// SwiftUI's `Text` has two silent traps, and both of them print a raw key
/// on the screen instead of failing:
///
/// 1. **A key built at runtime.** `Text("category_\(rawValue)")` becomes a
///    `LocalizedStringKey` whose lookup key is the *format string*
///    `"category_%"` — not `"category_work"`. Nothing matches, so the
///    interpolated text is shown verbatim: the user sees `category_work`.
/// 2. **A key passed in as a `String` variable.** `Text(someString)` picks the
///    *verbatim* initializer, which never looks anything up. A
///    `Text(milestone.titleKey)` prints `milestone_30m`.
///
/// Neither crashes, neither warns — the key just appears on screen. So every
/// runtime key and every formatted string goes through these two helpers,
/// which look the key up first and only then format it.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Localized string with arguments.
///
/// The lookup happens **before** the formatting — `String(format: "some_key", …)`
/// would use the key as the format string and print `some_key` on screen.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
