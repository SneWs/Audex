import SwiftUI

struct CoverImage: View {
    let bookID: Int
    var hasCover: Bool = true
    var cornerRadius: CGFloat = 8

    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            if hasCover, let url = session.api.coverURL(for: bookID) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder.overlay { ProgressView().controlSize(.small) }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AudexColor.primary.opacity(0.18))
            Image(systemName: "headphones")
                .font(.title2)
                .foregroundStyle(AudexColor.primary)
        }
    }
}
