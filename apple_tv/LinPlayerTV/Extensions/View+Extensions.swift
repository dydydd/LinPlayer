import SwiftUI

extension View {
    func cardStyle() -> some View {
        self
            .background(AppTheme.cardColor)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    func brandButton() -> some View {
        self
            .font(.system(size: AppTheme.FontSize.body, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(AppTheme.brandColor)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}

extension Int {
    var formattedRuntime: String {
        let totalMinutes = self / 10_000_000 / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var formattedDuration: String {
        let totalSeconds = self / 10_000_000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
