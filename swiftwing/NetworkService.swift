import Foundation

struct TestPost: Codable {
    let id: Int
    let title: String
}

final class NetworkService: Sendable {
    static let shared = NetworkService()

    private init() {}

    func fetchTestData() async throws -> TestPost {
        let url = URL(string: "https://jsonplaceholder.typicode.com/posts/1")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let post = try JSONDecoder().decode(TestPost.self, from: data)
        return post
    }
}
