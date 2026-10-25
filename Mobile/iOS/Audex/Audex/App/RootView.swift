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
        .tint(AudexColor.coral)
    }
}

enum AppTab: Hashable {
    case all
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

    @State private var selectedTab: AppTab = .all
    @State private var didSelectInitialTab = false

    var body: some View {
        @Bindable var playback = playback

        tabContainer
            .sheet(isPresented: $playback.isPresentingNowPlaying) {
                NowPlayingView()
                    .presentationDragIndicator(.visible)
            }
            .task {
                if library.books.isEmpty {
                    await library.refresh()
                }
                if !didSelectInitialTab {
                    didSelectInitialTab = true
                    if !library.books(for: .continueListening).isEmpty {
                        selectedTab = .continueListening
                    }
                }
                if library.playlists.isEmpty {
                    await library.loadPlaylists()
                }
                await session.loadAccount()
            }
    }

    @ViewBuilder
    private var tabContainer: some View {
        if #available(iOS 26.1, *) {
            baseTabView
                .tabViewBottomAccessory(isEnabled: playback.currentBook != nil) {
                    MiniPlayerBar()
                }
        } else {
            baseTabView
                .tabViewBottomAccessory {
                    MiniPlayerBar()
                }
        }
    }

    private var baseTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Library", systemImage: "books.vertical.fill", value: AppTab.all) {
                LibraryView(filter: .all)
            }

            Tab("Continue", systemImage: "play.circle.fill", value: AppTab.continueListening) {
                LibraryView(filter: .continueListening)
            }

            Tab("Recents", systemImage: "clock.fill", value: AppTab.recents) {
                LibraryView(filter: .recents)
            }

            Tab("Favorites", systemImage: "heart.fill", value: AppTab.favorites) {
                LibraryView(filter: .favorites)
            }

            Tab("Series", systemImage: "rectangle.stack.fill", value: AppTab.series) {
                SeriesListView()
            }

            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchView()
            }

            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
    }
}
