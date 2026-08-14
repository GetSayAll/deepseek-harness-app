import AppKit
import SwiftUI

enum DSTheme {
    static let backgroundBase = Color(red: 247 / 255, green: 249 / 255, blue: 252 / 255)
    static let sidebarFill = Color(red: 237 / 255, green: 242 / 255, blue: 248 / 255)
    static let surfacePrimary = Color.white
    static let surfaceSecondary = Color(red: 243 / 255, green: 246 / 255, blue: 250 / 255)
    static let brandPrimary = Color(red: 65 / 255, green: 118 / 255, blue: 230 / 255)
    static let brandHighlight = Color(red: 53 / 255, green: 207 / 255, blue: 232 / 255)
    static let textPrimary = Color(red: 24 / 255, green: 32 / 255, blue: 44 / 255)
    static let textSecondary = Color(red: 102 / 255, green: 113 / 255, blue: 132 / 255)
    static let borderSubtle = Color(red: 24 / 255, green: 32 / 255, blue: 44 / 255).opacity(0.10)
    static let selectionFill = brandPrimary.opacity(0.10)
    static let success = Color(red: 53 / 255, green: 184 / 255, blue: 107 / 255)
    static let warning = Color(red: 233 / 255, green: 154 / 255, blue: 50 / 255)
    static let danger = Color(red: 228 / 255, green: 88 / 255, blue: 88 / 255)

    static let sidebarMinimum = 264.0
    static let sidebarDefault = 280.0
    static let sidebarMaximum = 420.0
    static let sidebarCompact = 56.0
    static let detailsMinimum = 300.0
    static let detailsDefault = 360.0
    static let detailsMaximum = 520.0
    static let contentMaximum = 748.0
    static let composerMaximum = 780.0
}

struct BrandMark: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct CardBackground: ViewModifier {
    let cornerRadius: CGFloat
    var fill = DSTheme.surfacePrimary
    var border = DSTheme.borderSubtle
    var shadow = false

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
            .shadow(color: shadow ? Color(red: 30 / 255, green: 55 / 255, blue: 90 / 255).opacity(0.10) : .clear,
                    radius: shadow ? 12 : 0, y: shadow ? 8 : 0)
    }
}

extension View {
    func dsCard(
        cornerRadius: CGFloat = 12,
        fill: Color = DSTheme.surfacePrimary,
        border: Color = DSTheme.borderSubtle,
        shadow: Bool = false
    ) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius, fill: fill, border: border, shadow: shadow))
    }
}
