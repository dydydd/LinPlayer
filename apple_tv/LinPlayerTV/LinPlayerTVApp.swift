import SwiftUI

@main
struct LinPlayerTVApp: App {
    @StateObject private var serverManager = ServerManager()
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(serverManager)
                .environmentObject(authManager)
                .preferredColorScheme(.dark)
        }
    }
}
