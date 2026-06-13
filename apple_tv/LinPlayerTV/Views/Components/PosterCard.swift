import SwiftUI

struct PosterCard: View {
    let item: MediaItem
    let apiClient: EmbyApiClient
    var width: CGFloat = 300
    var showTitle: Bool = true
    var aspectRatio: CGFloat = 2/3

    private var imageURL: URL? {
        if let tag = item.primaryImageTag {
            return apiClient.primaryImageURL(item.id, tag: tag, maxWidth: Int(width * 2))
        }
        if let seriesId = item.seriesId, let tag = item.seriesPrimaryImageTag {
            return apiClient.primaryImageURL(seriesId, tag: tag, maxWidth: Int(width * 2))
        }
        return apiClient.primaryImageURL(item.id, maxWidth: Int(width * 2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
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
                .frame(width: width, height: width / aspectRatio)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.posterCornerRadius))

                if let progress = item.progress, progress > 0, progress < 1 {
                    ProgressBarOverlay(progress: progress)
                }

                if item.isWatched {
                    WatchedBadge()
                }
            }

            if showTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)

                    if let year = item.productionYear {
                        Text("\(year)")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .frame(width: width, alignment: .leading)
            }
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(AppTheme.surfaceColor)
            .frame(width: width, height: width / aspectRatio)
            .overlay(
                Image(systemName: "film")
                    .font(.system(size: 40))
                    .foregroundColor(AppTheme.textTertiary)
            )
    }
}

struct ProgressBarOverlay: View {
    let progress: Double

    var body: some View {
        VStack {
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 4)
                    Rectangle()
                        .fill(AppTheme.brandColor)
                        .frame(width: geo.size.width * CGFloat(progress), height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

struct WatchedBadge: View {
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.brandColor)
                    .padding(8)
            }
            Spacer()
        }
    }
}
