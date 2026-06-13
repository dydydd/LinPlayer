import SwiftUI

struct MainTabView: View {
    let apiClient: EmbyApiClient
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(apiClient: apiClient)
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
                .tag(0)

            SearchView(apiClient: apiClient)
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .tag(1)

            LibraryListView(apiClient: apiClient)
                .tabItem {
                    Label("媒体库", systemImage: "rectangle.stack.fill")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
    }
}
