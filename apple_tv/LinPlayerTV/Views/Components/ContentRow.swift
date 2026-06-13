import SwiftUI

struct ContentRow<Destination: View>: View {
    let title: String
    let items: [MediaItem]
    let apiClient: EmbyApiClient
    let destination: (MediaItem) -> Destination

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text(title)
                .font(.system(size: AppTheme.FontSize.title3, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
                .padding(.leading, AppTheme.Spacing.xxl)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AppTheme.Spacing.lg) {
                    ForEach(items) { item in
                        NavigationLink(destination: destination(item)) {
                            PosterCard(item: item, apiClient: apiClient)
                        }
                        .buttonStyle(TVCardButtonStyle())
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.vertical, AppTheme.Spacing.md)
            }
        }
    }
}

struct WideContentRow<Destination: View>: View {
    let title: String
    let items: [MediaItem]
    let apiClient: EmbyApiClient
    let destination: (MediaItem) -> Destination

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text(title)
                .font(.system(size: AppTheme.FontSize.title3, weight: .bold))
                .foregroundColor(AppTheme.textPrimary)
                .padding(.leading, AppTheme.Spacing.xxl)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AppTheme.Spacing.lg) {
                    ForEach(items) { item in
                        NavigationLink(destination: destination(item)) {
                            WideCard(item: item, apiClient: apiClient)
                        }
                        .buttonStyle(TVCardButtonStyle())
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.vertical, AppTheme.Spacing.md)
            }
        }
    }
}

struct TVCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
