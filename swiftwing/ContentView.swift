import SwiftUI

struct ContentView: View {
    @State private var fetchedTitle: String = ""
    @State private var isLoading: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            LibraryView()

            Divider()

            VStack(spacing: 12) {
                Text("Network Test")
                    .font(.headline)

                Button("Fetch Test Data") {
                    Task {
                        isLoading = true
                        do {
                            let post = try await NetworkService.shared.fetchTestData()
                            fetchedTitle = post.title
                            print("Successfully fetched post: \(post.title)")
                        } catch {
                            print("Error fetching data: \(error)")
                            fetchedTitle = "Error: \(error.localizedDescription)"
                        }
                        isLoading = false
                    }
                }
                .disabled(isLoading)

                if isLoading {
                    ProgressView()
                } else if !fetchedTitle.isEmpty {
                    Text(fetchedTitle)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
