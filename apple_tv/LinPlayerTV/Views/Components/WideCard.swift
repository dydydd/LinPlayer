import SwiftUI

struct WideCard: View {
    let item: MediaItem
    let apiClient: EmbyApiClient
    var width: CGFloat = 480
    var height: CGFloat = 270

    private var imageURL: URL? {
        if let tag = item.backdropImageTag {
            return apiClient.backdropImageURL(item.id, tag: tag, maxWidth: Int(width * 2))
        }
        if let tag = item.thumbImageTag {
            return apiClient.thumbImageURL(item.id, tag: tag, maxWidth: Int(width * 2))
        }
        if let thumbId = item.parentThumbItemId, let tag = item.parentThumbImageTag {
            return apiClient.thumbImageURL(thumbId, tag: tag, maxWidth: Int(width * 2))
        }
        if let tag = item.primaryImageTag {
            return apiClient.primaryImageURL(item.id, tag: tag, maxWidth: Int(width * 2))
        }
        return apiClient.primaryImageURL(item.id, maxWidth: Int(width * 2))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder
                case .empty:
                    placeholder
                        .overlay(ProgressView().tint(.white))
                @unknown default:
                    placeholder
                }
            }
            .frame(width: width, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))

            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))

            VStack(alignment: .leading, spacing: 4) {
                if let seriesName = item.seriesName {
                    Text(seriesName)
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                }

                Text(displayTitle)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let progress = item.progress, progress > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 4)
                            Capsule()
                                .fill(AppTheme.brandColor)
                                .frame(width: geo.size.width * CGFloat(progress), height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 4)
                }
            }
            .padding(AppTheme.Spacing.md)
        }
        .frame(width: width, height: height)
    }

    private var displayTitle: String {
        if item.isEpisode {
            var parts: [String] = []
            if let s = item.parentIndexNumber { parts.append("S\(s)") }
            if let e = item.indexNumber { parts.append("E\(e)") }
            if !parts.isEmpty {
                return "\(parts.joined()) · \(item.name)"
            }
        }
        return item.name
    }

    private var placeholder: some View {
        Rectangle()
            .fill(AppTheme.surfaceColor)
            .frame(width: width, height: height)
            .overlay(
                Image(systemName: "film")
                    .font(.system(size: 40))
                    .foregroundColor(AppTheme.textTertiary)
            )
    }
}
