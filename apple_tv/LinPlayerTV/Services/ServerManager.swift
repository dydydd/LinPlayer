import Foundation
import SwiftUI

final class ServerManager: ObservableObject {
    @Published var servers: [ServerConfig] = []
    @Published var currentServer: ServerConfig?

    private let storageKey = "linplayer_servers"
    private let currentServerKey = "linplayer_current_server"

    init() {
        loadServers()
    }

    func addServer(_ config: ServerConfig) {
        if let index = servers.firstIndex(where: { $0.url == config.url }) {
            servers[index] = config
        } else {
            servers.append(config)
        }
        saveServers()
    }

    func removeServer(at offsets: IndexSet) {
        let removedURLs = offsets.map { servers[$0].url }
        servers.remove(atOffsets: offsets)
        if let current = currentServer, removedURLs.contains(current.url) {
            currentServer = servers.first
        }
        saveServers()
    }

    func removeServer(_ config: ServerConfig) {
        servers.removeAll { $0.url == config.url }
        if currentServer?.url == config.url {
            currentServer = servers.first
        }
        saveServers()
    }

    func selectServer(_ config: ServerConfig) {
        currentServer = config
        UserDefaults.standard.set(config.url, forKey: currentServerKey)
    }

    func updateServerAuth(url: String, token: String, userId: String) {
        if let index = servers.firstIndex(where: { $0.url == url }) {
            servers[index].accessToken = token
            servers[index].userId = userId
            if currentServer?.url == url {
                currentServer = servers[index]
            }
            saveServers()
        }
    }

    private func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data) else {
            return
        }
        servers = decoded
        let savedURL = UserDefaults.standard.string(forKey: currentServerKey)
        currentServer = servers.first(where: { $0.url == savedURL }) ?? servers.first
    }

    private func saveServers() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
