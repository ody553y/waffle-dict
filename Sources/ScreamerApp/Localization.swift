import Foundation

@inline(__always)
func localized(
    _ key: StaticString,
    default defaultValue: String.LocalizationValue,
    comment: StaticString
) -> String {
    String(localized: key, defaultValue: defaultValue, comment: comment)
}

@inline(__always)
func localizedFormat(
    _ key: StaticString,
    default defaultValue: String.LocalizationValue,
    comment: StaticString,
    _ arguments: CVarArg...
) -> String {
    let format = String(localized: key, defaultValue: defaultValue, comment: comment)
    return String(format: format, locale: Locale.current, arguments: arguments)
}
