package se.grenangen.audex

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import dagger.hilt.android.AndroidEntryPoint
import se.grenangen.audex.data.repository.AuthRepository
import se.grenangen.audex.playback.PlaybackManager
import se.grenangen.audex.ui.component.MiniPlayer
import se.grenangen.audex.ui.navigation.AudexNavGraph
import se.grenangen.audex.ui.navigation.Screen
import se.grenangen.audex.ui.theme.AudexTheme
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject
    lateinit var authRepository: AuthRepository

    @Inject
    lateinit var playbackManager: PlaybackManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AudexTheme {
                val navController = rememberNavController()
                val navBackStackEntry by navController.currentBackStackEntryAsState()
                val currentDestination = navBackStackEntry?.destination

                val startDestination = if (authRepository.isLoggedIn()) {
                    Screen.Library.route
                } else {
                    Screen.Login.route
                }

                val showBottomBar = currentDestination?.route != null && 
                        Screen.NavItems.bottomNavItems.any { it.route == currentDestination.route }

                Scaffold(
                    modifier = Modifier.fillMaxSize(),
                    bottomBar = {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom))
                        ) {
                            if (currentDestination?.route != Screen.Player.route) {
                                MiniPlayer(
                                    playbackManager = playbackManager,
                                    onClick = { navController.navigate(Screen.Player.route) }
                                )
                            }
                            if (showBottomBar) {
                                NavigationBar(
                                    windowInsets = WindowInsets(0, 0, 0, 0)
                                ) {
                                    Screen.NavItems.bottomNavItems.forEach { screen ->
                                        NavigationBarItem(
                                            icon = { screen.icon?.let { Icon(it, contentDescription = null) } },
                                            label = { Text(screen.title) },
                                            selected = currentDestination?.hierarchy?.any { it.route == screen.route } == true,
                                            onClick = {
                                                navController.navigate(screen.route) {
                                                    popUpTo(navController.graph.findStartDestination().id) {
                                                        saveState = true
                                                    }
                                                    launchSingleTop = true
                                                    restoreState = true
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                ) { innerPadding ->
                    AudexNavGraph(
                        navController = navController,
                        startDestination = startDestination,
                        modifier = Modifier.padding(innerPadding)
                    )
                }
            }
        }
    }
}
