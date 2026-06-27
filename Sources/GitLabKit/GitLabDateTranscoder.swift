import Foundation
import OpenAPIRuntime

/// Decodes GitLab timestamps, which are ISO-8601 but inconsistently include fractional
/// seconds — e.g. `2024-06-25T08:00:00.000Z` on most resources, but `2024-06-25T08:00:00Z`
/// (and timezone offsets like `+02:00`) on others. The runtime's default `.iso8601`
/// transcoder rejects the fractional form and `.iso8601WithFractionalSeconds` rejects the
/// plain form, so a GitLab client needs one that accepts both.
///
/// Layered like `YandexDeliveryExpress`'s `FlexibleISO8601Transcoder`: a modern,
/// value-type `Date.ISO8601FormatStyle` (Sendable, no per-call allocation) is tried first,
/// with an `ISO8601DateFormatter` fallback that reliably handles numeric timezone offsets.
/// GitLabKit's iOS 16 floor means no legacy `DateFormatter` path is needed.
public struct GitLabDateTranscoder: DateTranscoder {
    public init() {}

    private static let isoFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let isoPlain = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    public func decode(_ string: String) throws -> Date {
        if let date = try? Self.isoFractional.parse(string) { return date }
        if let date = try? Self.isoPlain.parse(string) { return date }
        // Fallback: numeric-offset forms (`+02:00`) the format styles above may reject.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "Expected an ISO-8601 date, received '\(string)'.")
        )
    }

    public func encode(_ date: Date) throws -> String {
        Self.isoFractional.format(date)
    }
}
