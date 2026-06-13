import SwiftUI

struct HomeView: View {
    let apiClient: EmbyApiClient
    @State private var resumeItems: [MediaItem] = []
    @State private var nextUpItems: [MediaItem] = []
    @State private var recommendations: [MediaItem] = []
    @State private var libraries: [MediaLibrary] = []
    @State private var latestByLibrary: [String: [MediaItem]] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedPlayItem: MediaItem?
    @State private var showPlayer = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else {
                    contentView
                }
            }
            .background(AppTheme.background)
            .task { await loadData() }
            .fullScreenCover(isPresented: $showPlayer) {
                if let item = selectedPlayItem {
                    PlayerView(item: item, apiClient: apiClient)
                }
            }
        }
    }

    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                let heroItems = heroContent
                if !heroItems.isEmpty {
                    HeroBanner(
                        items: heroItems,
                        apiClient: apiClient,
                        onPlay: { item in
                            selectedPlayItem = item
                            showPlayer = true
                        }
                    )
                }

                let continueWatching = Array(Set(resumeItems + nextUpItems))
                    .sorted { ($0.userData?.playbackPositionTicks ?? 0) > ($1.userData?.playbackPositionTicks ?? 0) }

                if !continueWatching.isEmpty {
                    WideContentRow(
                        title: "继续观看",
                        items: continueWatching,
                        apiClient: apiClient,
                        destination: { item in detailDestination(for: item) }
                    )
                }

                ForEach(libraries) { lib in
                    if let items = latestByLibrary[lib.id], !items.isEmpty {
                        ContentRow(
                            title: lib.name,
                            items: items,
                            apiClient: apiClient,
                            destination: { item in detailDestination(for: item) }
                        )
                    }
                }

                if !recommendations.isEmpty {
                    ContentRow(
                        title: "推荐",
                        items: recommendations,
                        apiClient: apiClient,
                        destination: { item in detailDestination(for: item) }
                    )
                }

                Spacer(minLength: AppTheme.Spacing.xxxl)
            }
            .padding(.top, AppTheme.Spacing.lg)
        }
    }

    private func detailDestination(for item: MediaItem) -> some View {
        DetailView(itemId: item.seriesId ?? item.id, apiClient: apiClient)
    }

    private var heroContent: [MediaItem] {
        if !resumeItems.isEmpty {
            return Array(resumeItems.prefix(5))
        }
        return Array(recommendations.prefix(5))
    }

    private var loadingView: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(AppTheme.brandColor)
            Text("加载中...")
                .foregroundColor(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.brandColor)
            Text(message)
                .foregroundColor(AppTheme.textSecondary)
            Button("重试") {
                Task { await loadData() }
            }
            .brandButton()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            async let resumeTask = apiClient.getResumeItems()
            async let nextUpTask = apiClient.getNextUp()
            async let recsTask = apiClient.getRandomRecommendations()
            async let libsTask = apiClient.getLibraries()

            let (resume, nextUp, recs, libs) = try await (resumeTask, nextUpTask, recsTask, libsTask)

            await MainActor.run {
                resumeItems = resume
                nextUpItems = nextUp
                recommendations = recs
                libraries = libs
            }

            for lib in libs {
                if let latest = try? await apiClient.getLatestItems(libraryId: lib.id, limit: 16) {
                    await MainActor.run {
                        latestByLibrary[lib.id] = latest
                    }
                }
            }

            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
