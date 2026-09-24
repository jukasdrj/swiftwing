@testable import swiftwing
import Testing
import UIKit

@Suite("On-device scanner")
struct OnDeviceScannerTests {
    @Test func assembleKeepsCompleteResultInReview() {
        let outcome = OnDeviceMetadataAssembler.assemble(
            title: "Local Title",
            author: "Local Author",
            isbn: "978-0-7432-7356-5",
            ocrLines: ["Local Title", "Local Author"]
        )

        #expect(outcome.metadata.title == "Local Title")
        #expect(outcome.metadata.author == "Local Author")
        #expect(outcome.metadata.isbn == "9780743273565")
        #expect(outcome.metadata.confidence == nil)
        #expect(outcome.metadata.enrichmentStatus == .success)
        #expect(outcome.ocrText == "Local Title\nLocal Author")
    }

    @Test func assemblePrefersACompleteModelExtraction() {
        let outcome = OnDeviceMetadataAssembler.assemble(
            title: "Heuristic Title",
            author: "Heuristic Author",
            isbn: nil,
            ocrLines: ["Heuristic Title", "Heuristic Author"],
            extraction: BookExtraction(title: "Model Title", author: "Model Author")
        )

        #expect(outcome.metadata.title == "Model Title")
        #expect(outcome.metadata.author == "Model Author")
        #expect(outcome.metadata.confidence == nil)
        #expect(outcome.metadata.enrichmentStatus == .success)
    }

    @Test func assembleMarksMissingAuthorForReview() {
        let outcome = OnDeviceMetadataAssembler.assemble(
            title: "Local Title",
            author: "  ",
            isbn: nil,
            ocrLines: ["Local Title"]
        )

        #expect(outcome.metadata.title == "Local Title")
        #expect(outcome.metadata.author == nil)
        #expect(outcome.metadata.confidence == nil)
        #expect(outcome.metadata.enrichmentStatus == .reviewNeeded)
    }

    @Test func heuristicUsesByLineAndLongestTitle() {
        let guessed = SpineHeuristic.titleAndAuthor(from: [
            "by Jane",
            "A Much Longer Title",
        ])
        #expect(guessed.title == "A Much Longer Title")
        #expect(guessed.author == "Jane")
    }

    @Test func heuristicUsesTheLineAfterTheTitle() {
        let guessed = SpineHeuristic.titleAndAuthor(from: [
            "The Longest Title Line",
            "Ada Lovelace",
        ])
        #expect(guessed.title == "The Longest Title Line")
        #expect(guessed.author == "Ada Lovelace")
    }

    @MainActor
    @Test func recognizeTextFindsRenderedWord() async throws {
        let data = try #require(renderedPNG("GATSBY"))
        let lines = try await OnDeviceScanner().recognizeText(in: data)
        #expect(!lines.isEmpty)
        #expect(lines.contains { $0.text.localizedCaseInsensitiveContains("GATSBY") })
    }

    @MainActor
    private func renderedPNG(_ text: String) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 220))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 220))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 84),
                .foregroundColor: UIColor.black,
            ]
            text.draw(at: CGPoint(x: 40, y: 60), withAttributes: attributes)
        }
        return image.pngData()
    }
}
