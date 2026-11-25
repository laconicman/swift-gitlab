import Foundation
import OpenAPIRuntime

/// Decodes GitLab timestamps, which are ISO-8601 but inconsistently include fractional
/// seconds — e.g. `2024-06-25T08:00:00.000Z` on most resources, but `2024-06-25T08:00:00Z`
/// (and timezone offsets like `+02:00`) on others. The runtime's default `.iso8601`
/// transcoder rejects the fractional form and `.iso8601WithFractionalSeconds` rejects the
/// plain form, so a GitLab client needs one that accepts both.
///
/// It also accepts a bare `YYYY-MM-DD` date, read as start-of-day UTC: GitLab `date`
/// columns serialize without a time component, but parts of the OpenAPI spec mistype
/// them `format: date-time` (e.g. `last_activity_on`, `marked_for_deletion_on`,
/// `expires_at` on token entities — see the "Tech Debt" DocC article). The spec can't
/// be trusted to label these, so the fallback covers every mistyped field, enumerated
/// or not.
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
        // Bare `YYYY-MM-DD` — a `date` column the spec mistyped `date-time`. ISO8601
        // interprets a date with no zone as GMT, i.e. start-of-day UTC.
        formatter.formatOptions = [.withFullDate]
        if let date = formatter.date(from: string) { return date }
        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "Expected an ISO-8601 date, received '\(string)'.")
        )
    }

    public func encode(_ date: Date) throws -> String {
        Self.isoFractional.format(date)
    }
}
