import SwiftUI

struct ServerListView: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var authManager: AuthManager
    @State private var showAddServer = false

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.xxl) {
                Spacer()

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(AppTheme.brandColor)

                Text("LinPlayer")
                    .font(.system(size: AppTheme.FontSize.largeTitle, weight: .bold))
                    .foregroundColor(.white)

                Text("选择或添加一个 Emby 服务器")
                    .font(.system(size: AppTheme.FontSize.body))
                    .foregroundColor(AppTheme.textSecondary)

                if serverManager.servers.isEmpty {
                    Button(action: { showAddServer = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("添加服务器")
                        }
                        .brandButton()
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(spacing: AppTheme.Spacing.md) {
                        ForEach(serverManager.servers, id: \.url) { server in
                            Button(action: {
                                serverManager.selectServer(server)
                                if server.isAuthenticated {
                                    authManager.restoreSession(
                                        serverURL: server.url,
                                        token: server.accessToken!,
                                        userId: server.userId!
                                    )
                                }
                            }) {
                                HStack {
                                    Image(systemName: "server.rack")
                                        .font(.system(size: 30))
                                        .foregroundColor(AppTheme.brandColor)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(server.name)
                                            .font(.system(size: AppTheme.FontSize.body, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text(server.url)
                                            .font(.system(size: AppTheme.FontSize.caption))
                                            .foregroundColor(AppTheme.textSecondary)
                                    }
                                    Spacer()
                                    if server.isAuthenticated {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(AppTheme.Spacing.lg)
                                .frame(maxWidth: 600)
                                .background(AppTheme.surfaceColor)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    serverManager.removeServer(server)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }

                        Button(action: { showAddServer = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text("添加服务器")
                            }
                            .font(.system(size: AppTheme.FontSize.body))
                            .foregroundColor(AppTheme.brandColor)
                            .padding(AppTheme.Spacing.lg)
                            .frame(maxWidth: 600)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .background(AppTheme.background)
            .sheet(isPresented: $showAddServer) {
                AddServerView()
            }
        }
    }
}

struct AddServerView: View {
    @EnvironmentObject var serverManager: ServerManager
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Text("添加服务器")
                .font(.system(size: AppTheme.FontSize.title2, weight: .bold))
                .foregroundColor(.white)

            TextField("服务器地址 (例: http://192.168.1.100:8096)", text: $serverURL)
                .font(.system(size: AppTheme.FontSize.body))
                .padding(AppTheme.Spacing.lg)
                .background(AppTheme.surfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .frame(maxWidth: 700)

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: AppTheme.FontSize.caption))
                    .foregroundColor(.red)
            }

            HStack(spacing: AppTheme.Spacing.lg) {
                Button("取消") { dismiss() }
                    .font(.system(size: AppTheme.FontSize.body))
                    .foregroundColor(AppTheme.textSecondary)

                Button(action: connect) {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("连接")
                    }
                }
                .brandButton()
                .disabled(isLoading || serverURL.isEmpty)
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .background(AppTheme.background)
    }

    private func connect() {
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "http://\(url)"
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                let info = try await EmbyApiClient.testConnection(url: url)
                let config = ServerConfig(url: url, name: info.serverName)
                await MainActor.run {
                    serverManager.addServer(config)
                    serverManager.selectServer(config)
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "连接失败: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}
