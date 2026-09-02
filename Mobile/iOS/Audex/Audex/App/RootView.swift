import SwiftUI

struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            if session.serverURL == nil {
                ServerSetupView()
            } else if !session.isLoggedIn {
                LoginView()
            } else {
                MainTabView()
            }
        }
        .tint(AudexColor.primary)
        .preferredColorScheme(session.prefersDarkMode ? .dark : .light)
    }
}

enum AppTab: Hashable {
    case library
    case continueListening
    case recents
    case favorites
    case search
    case settings
}

struct MainTabView: View {
    @Environment(AppSession.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback
    @State private var tab: AppTab = .library

    private var showsMiniPlayer: Bool {
        playback.currentBook != nil && !playback.isNowPlayingPresented
    }

    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                tabHost
                if showsMiniPlayer {
                    MiniPlayerBar()
                }
            }
            #else
            tabHost
                .tabViewBottomAccessory(isEnabled: showsMiniPlayer) {
                    MiniPlayerBar()
                }
            #endif
        }
        .audexNowPlayingCover(isPresented: Binding(
            get: { playback.isNowPlayingPresented },
            set: { playback.isNowPlayingPresented = $0 }
        )) {
            NowPlayingView()
                .preferredColorScheme(session.prefersDarkMode ? .dark : .light)
                .tint(AudexColor.primary)
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 560)
                #endif
        }
        .task {
            await library.refresh()
            await session.loadAccount()
        }
    }

    private var tabHost: some View {
        TabView(selection: $tab) {
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryView(filter: .all)
            }
            Tab("Continue", systemImage: "play.circle", value: AppTab.continueListening) {
                LibraryView(filter: .continueListening)
            }
            Tab("Recents", systemImage: "clock", value: AppTab.recents) {
                LibraryView(filter: .recents)
            }
            Tab("Favorites", systemImage: "heart", value: AppTab.favorites) {
                LibraryView(filter: .favorites)
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
