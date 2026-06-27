import Foundation
import GitLabOpenAPI

// Sample data for SwiftUI previews, tests, and docs — mirroring YandexDeliveryExpress's
// `Types+examples.swift`. All entity fields are optional, so an example sets only what's
// meaningful for display.

public extension Components.Schemas.APIEntitiesUserBasic {
    static let example = Self(
        id: 7,
        username: "octocat",
        name: "The Octocat",
        state: "active"
    )
}

public extension Components.Schemas.APIEntitiesNote {
    static let example = Self(
        id: 1,
        body: "Looks good to me 🚀",
        author: .example,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        system: false
    )

    static let systemExample = Self(
        id: 2,
        body: "changed the description",
        author: .example,
        createdAt: Date(timeIntervalSince1970: 1_700_000_100),
        system: true
    )
}

public extension [Components.Schemas.APIEntitiesNote] {
    static let example: Self = [.example, .systemExample]
}
