package se.grenangen.audex.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import se.grenangen.audex.ui.screen.detail.BookDetailScreen
import se.grenangen.audex.ui.screen.library.LibraryScreen
import se.grenangen.audex.ui.screen.library.LibraryType
import se.grenangen.audex.ui.screen.login.LoginScreen
import se.grenangen.audex.ui.screen.player.PlayerScreen
import se.grenangen.audex.ui.screen.search.SearchScreen

@Composable
fun AudexNavGraph(
    navController: NavHostController,
    startDestination: String,
    modifier: Modifier = Modifier
) {
    NavHost(
        navController = navController,
        startDestination = startDestination,
        modifier = modifier
    ) {
        composable(Screen.Login.route) {
            LoginScreen(
                onLoginSuccess = {
                    navController.navigate(Screen.Library.route) {
                        popUpTo(Screen.Login.route) { inclusive = true }
                    }
                }
            )
        }
        composable(Screen.Library.route) {
            LibraryScreen(
                type = LibraryType.ALL,
                onBookClick = { bookId ->
                    navController.navigate(Screen.BookDetail.createRoute(bookId))
                }
            )
        }
        composable(Screen.Recents.route) {
            LibraryScreen(
                type = LibraryType.RECENTS,
                onBookClick = { bookId ->
                    navController.navigate(Screen.BookDetail.createRoute(bookId))
                }
            )
        }
        composable(Screen.Continue.route) {
            LibraryScreen(
                type = LibraryType.CONTINUE,
                onBookClick = { bookId ->
                    navController.navigate(Screen.BookDetail.createRoute(bookId))
                }
            )
        }
        composable(Screen.Favorites.route) {
            LibraryScreen(
                type = LibraryType.FAVORITES,
                onBookClick = { bookId ->
                    navController.navigate(Screen.BookDetail.createRoute(bookId))
                }
            )
        }
        composable(
            route = Screen.BookDetail.route,
            arguments = listOf(navArgument("bookId") { type = NavType.IntType })
        ) {
            BookDetailScreen(
                onBackClick = { navController.popBackStack() },
                onPlayClick = {
                    navController.navigate(Screen.Player.route)
                }
            )
        }
        composable(Screen.Player.route) {
            PlayerScreen(
                onBackClick = { navController.popBackStack() }
            )
        }
        composable(Screen.Search.route) {
            SearchScreen(
                onBookClick = { bookId ->
                    navController.navigate(Screen.BookDetail.createRoute(bookId))
                }
            )
        }
    }
}
