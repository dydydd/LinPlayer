import SwiftUI

struct LibraryListView: View {
    let apiClient: EmbyApiClient
    @State private var libraries: [MediaLibrary] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(AppTheme.brandColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 400), spacing: AppTheme.Spacing.xl)
                            ],
                            spacing: AppTheme.Spacing.xl
                        ) {
                            ForEach(libraries) { lib in
                                NavigationLink(destination: LibraryDetailView(library: lib, apiClient: apiClient)) {
                                    LibraryCard(library: lib, apiClient: apiClient)
                                }
                                .buttonStyle(TVCardButtonStyle())
                            }
                        }
                        .padding(AppTheme.Spacing.xxl)
                    }
                }
            }
            .background(AppTheme.background)
            .task {
                do {
                    libraries = try await apiClient.getLibraries()
                } catch {}
                isLoading = false
            }
        }
    }
}

struct LibraryCard: View {
    let library: MediaLibrary
    let apiClient: EmbyApiClient

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: apiClient.primaryImageURL(library.id, tag: library.primaryImageTag, maxWidth: 800)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle().fill(AppTheme.cardColor)
                }
            }
            .frame(height: 220)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))

            VStack(alignment: .leading, spacing: 4) {
                Text(library.name)
                    .font(.system(size: AppTheme.FontSize.title3, weight: .bold))
                    .foregroundColor(.white)
                Text(libraryTypeLabel)
                    .font(.system(size: AppTheme.FontSize.caption))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .padding(AppTheme.Spacing.lg)
        }
        .frame(height: 220)
    }

    private var libraryTypeLabel: String {
        switch library.collectionType {
        case "movies": return "电影"
        case "tvshows": return "剧集"
        case "music": return "音乐"
        case "homevideos": return "家庭视频"
        default: return "媒体"
        }
    }
}

struct LibraryDetailView: View {
    let library: MediaLibrary
    let apiClient: EmbyApiClient

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var currentPage = 0
    @State private var hasMore = true
    private let pageSize = 50

    @State private var sortBy = "SortName"
    @State private var sortOrder = "Ascending"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack {
                    Text(library.name)
                        .font(.system(size: AppTheme.FontSize.title1, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()

                    Menu {
                        Button("名称") { changeSortBy("SortName") }
                        Button("日期添加") { changeSortBy("DateCreated") }
                        Button("评分") { changeSortBy("CommunityRating") }
                        Button("年份") { changeSortBy("ProductionYear") }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(sortLabel)
                        }
                        .font(.system(size: AppTheme.FontSize.caption))
                        .foregroundColor(AppTheme.textSecondary)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.top, AppTheme.Spacing.lg)

                if isLoading && items.isEmpty {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(AppTheme.brandColor)
                        .frame(maxWidth: .infinity, minHeight: 400)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 250), spacing: AppTheme.Spacing.xl)
                        ],
                        spacing: AppTheme.Spacing.xl
                    ) {
                        ForEach(items) { item in
                            NavigationLink(destination: DetailView(itemId: item.id, apiClient: apiClient)) {
                                PosterCard(item: item, apiClient: apiClient, width: 250)
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .onAppear {
                                if item.id == items.last?.id && hasMore {
                                    Task { await loadMore() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.xxl)

                    if isLoading {
                        ProgressView()
                            .tint(AppTheme.brandColor)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
            }
        }
        .background(AppTheme.background)
        .task { await loadItems() }
    }

    private var sortLabel: String {
        switch sortBy {
        case "SortName": return "名称"
        case "DateCreated": return "日期添加"
        case "CommunityRating": return "评分"
        case "ProductionYear": return "年份"
        default: return "排序"
        }
    }

    private func changeSortBy(_ newSort: String) {
        sortBy = newSort
        sortOrder = newSort == "SortName" ? "Ascending" : "Descending"
        items = []
        currentPage = 0
        hasMore = true
        Task { await loadItems() }
    }

    private func loadItems() async {
        isLoading = true
        do {
            let newItems = try await apiClient.getLibraryItems(
                libraryId: library.id,
                sortBy: sortBy,
                sortOrder: sortOrder,
                startIndex: 0,
                limit: pageSize
            )
            await MainActor.run {
                items = newItems
                currentPage = 1
                hasMore = newItems.count >= pageSize
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    private func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        do {
            let newItems = try await apiClient.getLibraryItems(
                libraryId: library.id,
                sortBy: sortBy,
                sortOrder: sortOrder,
                startIndex: currentPage * pageSize,
                limit: pageSize
            )
            await MainActor.run {
                items.append(contentsOf: newItems)
                currentPage += 1
                hasMore = newItems.count >= pageSize
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }
}
