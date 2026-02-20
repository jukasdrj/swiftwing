import SwiftUI
import Combine

///
/// Asynchronous image loader to prevent blocking the main thread.
///
class ImageLoader: ObservableObject {
    @Published var image: UIImage?

    private var cancellable: AnyCancellable?

    /// Load image data asynchronously
    func load(from data: Data) {
        cancellable = Just(data)
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .map { UIImage(data: $0) }
            .replaceError(with: nil)
            .receive(on: DispatchQueue.main)
            .assign(to: \.image, on: self)
    }
}
