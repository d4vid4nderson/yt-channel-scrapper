import Foundation

/// 4_270_000 -> "4.3M". View counts and subscriber counts are abbreviated the same way
/// on YouTube, so both go through here.
func compactCount(_ value: Int) -> String {
    switch value {
    case 1_000_000...:
        return trimmedDecimal(Double(value) / 1_000_000) + "M"
    case 1_000...:
        return trimmedDecimal(Double(value) / 1_000) + "K"
    default:
        return String(value)
    }
}

/// One decimal place below ten, none above — "4.3M", but "127K".
private func trimmedDecimal(_ value: Double) -> String {
    value < 10
        ? String(format: "%.1f", value).replacingOccurrences(of: ".0", with: "")
        : String(Int(value.rounded()))
}
