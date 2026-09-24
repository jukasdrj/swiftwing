import FoundationModels

/// Structured title and author from the on-device language model.
@Generable
struct BookExtraction: Sendable {
    var title: String
    var author: String
}
