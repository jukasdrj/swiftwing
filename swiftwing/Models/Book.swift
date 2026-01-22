import Foundation
import SwiftData

@Model
final class Book {
    var title: String
    var author: String
    var publishedYear: Int

    init(title: String = "", author: String = "", publishedYear: Int = 2024) {
        self.title = title
        self.author = author
        self.publishedYear = publishedYear
    }
}
