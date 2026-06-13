import SwiftUI

struct RootView: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        Group {
            if authManager.isAuthenticated, let client = authManager.apiClient {
                MainTabView(apiClient: client)
            } else if let server = serverManager.currentServer {
                LoginView(server: server)
            } else {
                ServerListView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
    }
}
