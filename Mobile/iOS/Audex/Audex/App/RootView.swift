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
        .preferredColorScheme(session.isDarkMode ? .dark : .light)
    }
}

enum AppTab: Hashable {
    case library
    case continueListening
    case recents
    case favorites
    case series
    case search
    case settings
}

struct MainTabView: View {
    @Environment(AppSession.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback

    @State private var tab: AppTab = .library
    @State private var didSelectInitialTab = false

    var body: some View {
        @Bindable var playback = playback

        TabView(selection: $tab) {
            Tab("Library", systemImage: "books.vertical.fill", value: .library) {
                LibraryView(filter: .all)
            }

            Tab("Continue", systemImage: "play.circle.fill", value: .continueListening) {
                LibraryView(filter: .continueListening)
            }

            Tab("Recents", systemImage: "sparkles", value: .recents) {
                LibraryView(filter: .recents)
            }

            Tab("Favorites", systemImage: "heart.fill", value: .favorites) {
                LibraryView(filter: .favorites)
            }

            Tab("Series", systemImage: "music.note.list", value: .series) {
                SeriesListView()
            }

            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchView()
            }

            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
        }
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .tabViewStyle(.sidebarAdaptable)
        .tabViewBottomAccessory(isEnabled: playback.currentBook != nil) {
            MiniPlayerBar()
        }
        .audexNowPlayingCover(isPresented: $playback.isPresentingNowPlaying) {
            NowPlayingView()
        }
        .task {
            await library.refresh()
            if !didSelectInitialTab {
                didSelectInitialTab = true
                if !library.books(for: .continueListening).isEmpty {
                    tab = .continueListening
                }
            }
            await session.loadAccount()
        }
    }
}
