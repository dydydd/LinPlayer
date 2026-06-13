import SwiftUI

struct SearchView: View {
    let apiClient: EmbyApiClient
    @State private var query = ""
    @State private var results: [MediaItem] = []
    @State private var isSearching = false
    @State private var hasSearched = false

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.xl) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundColor(AppTheme.textSecondary)

                    TextField("搜索电影、剧集...", text: $query)
                        .font(.system(size: AppTheme.FontSize.title3))
                        .foregroundColor(.white)
                        .onSubmit { performSearch() }
                }
                .padding(AppTheme.Spacing.lg)
                .background(AppTheme.surfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Spacing.xl)

                if isSearching {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(AppTheme.brandColor)
                    Spacer()
                } else if results.isEmpty && hasSearched {
                    Spacer()
                    VStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(AppTheme.textTertiary)
                        Text("未找到结果")
                            .font(.system(size: AppTheme.FontSize.body))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    Spacer()
                } else if !results.isEmpty {
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 250), spacing: AppTheme.Spacing.xl)
                            ],
                            spacing: AppTheme.Spacing.xl
                        ) {
                            ForEach(results) { item in
                                NavigationLink(destination: DetailView(itemId: item.id, apiClient: apiClient)) {
                                    PosterCard(item: item, apiClient: apiClient, width: 250)
                                }
                                .buttonStyle(TVCardButtonStyle())
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.xxl)
                    }
                } else {
                    Spacer()
                    VStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "tv")
                            .font(.system(size: 60))
                            .foregroundColor(AppTheme.textTertiary)
                        Text("输入关键词搜索")
                            .font(.system(size: AppTheme.FontSize.body))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    Spacer()
                }
            }
            .background(AppTheme.background)
        }
    }

    private func performSearch() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSearching = true
        hasSearched = true
        Task {
            do {
                let items = try await apiClient.search(query: query)
                await MainActor.run {
                    results = items
                    isSearching = false
                }
            } catch {
                await MainActor.run { isSearching = false }
            }
        }
    }
}
