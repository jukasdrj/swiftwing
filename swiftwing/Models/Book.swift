import Foundation
import SwiftData

@Model
final class Book {
    @Attribute(.unique) var isbn: String
    var id: UUID
    var title: String
    var author: String

    init(id: UUID = UUID(), title: String, author: String, isbn: String) {
        self.id = id
        self.title = title
        self.author = author
        self.isbn = isbn
    }
}
