package se.grenangen.audex.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.graphics.vector.ImageVector

sealed class Screen(val route: String, val title: String = "", val icon: ImageVector? = null) {
    object ServerSettings : Screen("server_settings")
    object Login : Screen("login")
    object Library : Screen("library", "Library", Icons.AutoMirrored.Filled.LibraryBooks)
    object Recents : Screen("recents", "Recents", Icons.Default.NewReleases)
    object Continue : Screen("continue", "Continue", Icons.Default.PlayCircleOutline)
    object Favorites : Screen("favorites", "Favorites", Icons.Default.Favorite)
    object BookDetail : Screen("book_detail/{bookId}") {
        fun createRoute(bookId: Int) = "book_detail/$bookId"
    }
    object Player : Screen("player")
    object Search : Screen("search", "Search", Icons.Default.Search)
    object Settings : Screen("settings", "Settings", Icons.Default.Settings)

    object NavItems {
        val bottomNavItems = listOf(Library, Recents, Continue, Favorites, Search, Settings)
    }
}
