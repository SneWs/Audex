import SwiftUI

enum AudexColor {
    static let primary = Color(red: 124 / 255, green: 77 / 255, blue: 255 / 255)
    static let secondary = Color(red: 199 / 255, green: 125 / 255, blue: 255 / 255)
    static let background = Color("AudexBackground")
    static let surface = Color("AudexSurface")
    static let onSurface = Color("AudexOnSurface")
    static let onSurfaceVariant = Color("AudexOnSurfaceVariant")
    static let favorite = Color.red
}

enum AudexTheme {
    static func apply<V: View>(_ content: V, darkMode: Bool) -> some View {
        content
            .tint(AudexColor.primary)
            .preferredColorScheme(darkMode ? .dark : .light)
    }
}

extension View {
    @ViewBuilder
    func audexNowPlayingCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented, content: content)
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }
}
