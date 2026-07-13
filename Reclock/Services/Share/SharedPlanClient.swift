import Foundation
import ReclockKit

/// A shared plan as fetched by invite code.
struct FetchedSharedPlan {
    var code: String
    var title: String
    var ownerID: String
    var trip: Trip
    var plan: JetLagPlan
}

struct PlanMember: Identifiable, Hashable {
    var userID: String
    var displayName: String
    var id: String { userID }
}

struct MemberProgressRow: Hashable {
    var userID: String
    var actionID: UUID
    var status: String
}

struct ReceivedKudo: Identifiable, Hashable {
    var id: Int
    var fromName: String
    var emoji: String
    var createdAt: Date
}

/// Travel-buddy endpoints, in the same thin-URLSession style as the auth client.
extension SupabaseAuthClient {

    private func rest(_ path: String, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(
            url: SupabaseConfig.url.appendingPathComponent("rest/v1/\(path)"),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }
        return URLRequest(url: components.url!)
    }

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func createSharedPlan(
        code: String,
        title: String,
        trip: Trip,
        plan: JetLagPlan,
        session: AuthSession
    ) async throws {
        var request = rest("shared_plans")
        request.httpMethod = "POST"
        decorate(&request, bearer: session.accessToken)
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let row: [String: Any] = [
            "code": code,
            "owner_id": session.userID,
            "title": title,
            "trip": try JSONSerialization.jsonObject(with: Self.jsonEncoder.encode(trip)),
            "plan": try JSONSerialization.jsonObject(with: Self.jsonEncoder.encode(plan)),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: [row])
        let (data, response) = try await urlSession.data(for: request)
        try Self.expectOK(response, data: data)
    }

    func fetchSharedPlan(code: String, session: AuthSession) async throws -> FetchedSharedPlan? {
        var request = rest("shared_plans", query: [
            URLQueryItem(name: "code", value: "eq.\(code)"),
            URLQueryItem(name: "select", value: "code,title,owner_id,trip,plan"),
        ])
        decorate(&request, bearer: session.accessToken)
        let (data, response) = try await urlSession.data(for: request)
        try Self.expectOK(response, data: data)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first,
              let title = row["title"] as? String,
              let ownerID = row["owner_id"] as? String,
              let tripObject = row["trip"], let planObject = row["plan"] else { return nil }
        let trip = try Self.jsonDecoder.decode(
            Trip.self, from: JSONSerialization.data(withJSONObject: tripObject)
        )
        let plan = try Self.jsonDecoder.decode(
            JetLagPlan.self, from: JSONSerialization.data(withJSONObject: planObject)
        )
        return FetchedSharedPlan(code: code, title: title, ownerID: ownerID, trip: trip, plan: plan)
    }

    func joinSharedPlan(code: String, displayName: String, session: AuthSession) async throws {
        var request = rest("plan_members")
        request.httpMethod = "POST"
        decorate(&request, bearer: session.accessToken)
        request.setValue("resolution=ignore-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let row: [String: Any] = [
            "plan_code": code,
            "user_id": session.userID,
            "display_name": displayName,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: [row])
        let (data, response) = try await urlSession.data(for: request)
        try Self.expectOK(response, data: data)
    }

    func fetchMembers(code: String, session: AuthSession) async throws -> [PlanMember] {
        var request = rest("plan_members", query: [
            URLQueryItem(name: "plan_code", value: "eq.\(code)"),
            URLQueryItem(name: "select", value: "user_id,display_name"),
            URLQueryItem(name: "order", value: "joined_at.asc"),
        ])
        decorate(&request, bearer: session.accessToken)
        let (data, response) = try await urlSession.data(for: request)
        try Self.expectOK(response, data: data)
        let rows = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return rows.compactMap { row in
            guard let userID = row["user_id"] as? String,
                  let name = row["display_name"] as? String else { return nil }
            return PlanMember(userID: userID, displayName: name)
        }
    }

    func fetchProgress(code: String, session: AuthSession) async throws -> [MemberProgressRow] {
        var request = rest("member_progress", query: [
            URLQueryItem(name: "plan_code", value: "eq.\(code)"),
            URLQueryItem(name: "select", value: "user_id,action_id,status"),
        ])
        decorate(&request, bearer: session.accessToken)
        let (data, response) = try await urlSession.data(for: request)
        try Self.expectOK(response, data: data)
        let rows = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return rows.compactMap { row in
            guard let userID = row["user_id"] as? String,
                  let actionString = row["action_id"] as? String,
                  let actionID = UUID(uuidString: actionString),
                  let status = row["status"] as? String else { return nil }
            return MemberProgressRow(userID: userID, actionID: actionID, status: status)
        }
    }

    func upsertProgress(
        code: String,
        actionID: UUID,
        status: String,
        session: AuthSession
    ) async throws {
        var request = rest("member_progress", query: [
            URLQueryItem(name: "on_conflict", value: "plan_code,user_id,action_id"),
        ])
        request.httpMethod = "POST"
        decorate(&request, bearer: session.accessToken)
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let row: [String: Any] = [
            "plan_code": code,
            "user_id": session.userID,
            "action_id": actionID.uuidString.lowercased(),
            "status": status,
            "completed_at": ISO8601DateFormatter().string(from: Date()),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: [row])
        let (data, response) = try await urlSession.data(for: request)
        try Self.expectOK(response, data: data)
    }

    func deleteProgress(code: String, actionID: UUID, session: AuthSession) async throws {
        var request = rest("member_progress", query: [
            URLQueryItem(name: "plan_code", value: "eq.\(code)"),
            URLQueryItem(name: "user_id", value: "eq.\(session.userID)"),
            URLQueryItem(name: "action_id", value: "eq.\(actionID.uuidString.lowercased())"),
        ])
        request.httpMethod = "DELETE"
        decorate(&request, bearer: session.accessToken)
        let (data, response) = try await urlSession.data(for: request)
        try Self.expectOK(response, data: data)
    }

    func sendKudos(
        code: String,
        toUser: String,
        fromName: String,
        emoji: String,
        session: AuthSession
    ) async throws {
        var request = rest("kudos")
        request.httpMethod = "POST"
        decorate(&request, bearer: session.accessToken)
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let row: [String: Any] = [
            "plan_code": code,
            "from_user": session.userID,
            "from_name": fromName,
            "to_user": toUser,
            "emoji": emoji,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: [row])
        let (data, response) = try await urlSession.data(for: request)
        try Self.expectOK(response, data: data)
    }

    /// Kudos sent to me on this plan since a marker date.
    func fetchKudos(code: String, since: Date, session: AuthSession) async throws -> [ReceivedKudo] {
        let formatter = ISO8601DateFormatter()
        var request = rest("kudos", query: [
            URLQueryItem(name: "plan_code", value: "eq.\(code)"),
            URLQueryItem(name: "to_user", value: "eq.\(session.userID)"),
            URLQueryItem(name: "created_at", value: "gt.\(formatter.string(from: since))"),
            URLQueryItem(name: "select", value: "id,from_name,emoji,created_at"),
            URLQueryItem(name: "order", value: "created_at.desc"),
        ])
        decorate(&request, bearer: session.accessToken)
        let (data, response) = try await urlSession.data(for: request)
        try Self.expectOK(response, data: data)
        let rows = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return rows.compactMap { row in
            guard let id = row["id"] as? Int,
                  let fromName = row["from_name"] as? String,
                  let emoji = row["emoji"] as? String,
                  let createdString = row["created_at"] as? String else { return nil }
            let created = parser.date(from: createdString)
                ?? ISO8601DateFormatter().date(from: createdString) ?? Date()
            return ReceivedKudo(id: id, fromName: fromName, emoji: emoji, createdAt: created)
        }
    }
}
