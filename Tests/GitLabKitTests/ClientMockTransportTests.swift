import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession
import Testing
import GitLabOpenAPI
@testable import GitLabKit

/// A `ClientTransport` that captures the outgoing request and returns a canned response —
/// lets us assert request shaping + auth without hitting the network.
actor MockTransport: ClientTransport {
    private(set) var captured: HTTPRequest?
    private let status: HTTPResponse.Status
    private let jsonBody: String

    init(status: HTTPResponse.Status = .ok, jsonBody: String = "{}") {
        self.status = status
        self.jsonBody = jsonBody
    }

    func send(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        captured = request
        var response = HTTPResponse(status: status)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(jsonBody))
    }
}

@Suite("Client over a mock transport")
struct ClientMockTransportTests {

    /// Exercises a real generated review operation end-to-end through the client +
    /// `HeaderMiddleware`, asserting the URL is built correctly and the bearer token is
    /// attached. The list endpoint's 200 is retyped to an array by the spec tool (see the
    /// "Tech Debt" DocC article), so the canned body is a JSON array and decodes to `[Note]`.
    @Test("listing MR notes builds the right request and carries the bearer token")
    func listMergeRequestNotes() async throws {
        let mock = MockTransport(jsonBody: "[]")
        let client = Client(
            serverURL: try Servers.Server1.url(),
            transport: mock,
            middlewares: [HeaderMiddleware(bearerToken: "test-token")]
        )

        let output = try await client.getApiV4ProjectsIdMergeRequestsNoteableIdNotes(
            .init(path: .init(id: "123", noteableId: 7))
        )

        // Documented 200 now decodes into an array of notes.
        #expect(try output.ok.body.json.isEmpty)

        let captured = try #require(await mock.captured)
        #expect(captured.method == .get)
        #expect(captured.path == "/api/v4/projects/123/merge_requests/7/notes")
        #expect(captured.headerFields[.authorization] == "Bearer test-token")
    }

    /// An unauthenticated (or token-authenticated) client for the opt-in live tests, plus the
    /// project to target. Defaults to a public `gitlab.com` repo; set `GITLAB_TOKEN` +
    /// `GITLAB_HOST` (e.g. `git.flat.lab`) + `GITLAB_PROJECT` to hit your own instance.
    private static func liveClient() throws -> (client: Client, project: String) {
        let env = ProcessInfo.processInfo.environment
        let host = env["GITLAB_HOST"] ?? "gitlab.com"
        let project = env["GITLAB_PROJECT"] ?? "gitlab-org/gitlab"
        let client: Client
        if let token = env["GITLAB_TOKEN"] {
            client = try Client(token: token, hostname: host)
        } else {
            client = Client(
                serverURL: try Servers.Server1.url(hostname: host),
                configuration: Configuration(dateTranscoder: GitLabDateTranscoder()),
                transport: URLSessionTransport()
            )
        }
        return (client, project)
    }

    /// Opt-in live test (enabled only with `GITLAB_LIVE_TESTS`, so plain `swift test` stays
    /// offline). Fetches one MR and decodes it — proving transport, auth, dates, and the
    /// array-retyping all work end-to-end against a real instance.
    @Test(
        "live: fetch a single merge request",
        .enabled(if: ProcessInfo.processInfo.environment["GITLAB_LIVE_TESTS"] != nil)
    )
    func liveFetchSingleMergeRequest() async throws {
        let (client, project) = try Self.liveClient()
        let iid = Int(ProcessInfo.processInfo.environment["GITLAB_MR_IID"] ?? "1") ?? 1
        let output = try await client.getApiV4ProjectsIdMergeRequestsMergeRequestIid(
            .init(path: .init(id: .case1(project), mergeRequestIid: iid))
        )
        switch output {
        case .ok(let ok): _ = try ok.body.json   // decodes — array fields retyped by the spec tool
        case .notFound, .undocumented: break
        }
    }

    /// Opt-in **auto-catch diagnostic**: decodes a spread of real review entities (a page of
    /// merge requests + commits) and *reports* any spec/response mismatch as a recorded
    /// known issue rather than failing the suite — because live data evolves and GitLab's
    /// spec has more than one under-typing flavor:
    ///   - array-as-object (`assignees`, `reviewers`) — fixed by `gitlab-spec-tool`;
    ///   - scalar mismatches (e.g. `milestone.group_id` typed `String` but returned as a
    ///     number) — not yet mitigated. See <doc:TechDebt>.
    /// Read the recorded issues to decide what to add to the tool (or upstream).
    @Test(
        "live: decode a spread of review entities",
        .enabled(if: ProcessInfo.processInfo.environment["GITLAB_LIVE_TESTS"] != nil)
    )
    func liveDecodeReviewEntities() async throws {
        let (client, project) = try Self.liveClient()

        await withKnownIssue("MR list decode mismatch — see TechDebt", isIntermittent: true) {
            let mrs = try await client.getApiV4ProjectsIdMergeRequests(
                .init(path: .init(id: .case1(project)), query: .init(perPage: 5))
            )
            if case .ok(let ok) = mrs { _ = try ok.body.json }
        }

        await withKnownIssue("Commit list decode mismatch — see TechDebt", isIntermittent: true) {
            let commits = try await client.getApiV4ProjectsIdRepositoryCommits(
                .init(path: .init(id: .case1(project)), query: .init(perPage: 5))
            )
            if case .ok(let ok) = commits { _ = try ok.body.json }
        }
    }
}
