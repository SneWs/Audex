package se.grenangen.audex

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.window.core.layout.WindowWidthSizeClass
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.launch
import se.grenangen.audex.data.local.SettingsManager
import se.grenangen.audex.data.repository.AuthRepository
import se.grenangen.audex.ui.composition.LocalServerUri
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
    lateinit var settingsManager: SettingsManager

    @Inject
    lateinit var playbackManager: PlaybackManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val serverUri by settingsManager.serverUri.collectAsState()
            CompositionLocalProvider(LocalServerUri provides (serverUri ?: "")) {
                AudexTheme {
                val navController = rememberNavController()
                val navBackStackEntry by navController.currentBackStackEntryAsState()
                val currentDestination = navBackStackEntry?.destination

                val startDestination = when {
                    !settingsManager.isValidUri(settingsManager.getServerUri()) -> Screen.ServerSettings.route
                    authRepository.isLoggedIn() -> Screen.Library.route
                    else -> Screen.Login.route
                }

                val adaptiveInfo = currentWindowAdaptiveInfo()
                val isExpanded = adaptiveInfo.windowSizeClass.windowWidthSizeClass == WindowWidthSizeClass.EXPANDED
                
                val topLevelRoutes = Screen.NavItems.topLevelDestinations.map { it.route }
                val isTopLevelDestination = currentDestination?.route in topLevelRoutes

                val drawerState = rememberDrawerState(DrawerValue.Closed)
                val scope = rememberCoroutineScope()

                val navigationContent = @Composable {
                    Spacer(Modifier.height(12.dp))
                    Screen.NavItems.topLevelDestinations.forEach { screen ->
                        NavigationDrawerItem(
                            icon = { screen.icon?.let { Icon(it, contentDescription = null) } },
                            label = { Text(screen.title) },
                            selected = currentDestination?.hierarchy?.any { it.route == screen.route } == true,
                            onClick = {
                                scope.launch { drawerState.close() }
                                navController.navigate(screen.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            modifier = Modifier.padding(NavigationDrawerItemDefaults.ItemPadding)
                        )
                    }
                }

                if (isExpanded && isTopLevelDestination) {
                    PermanentNavigationDrawer(
                        drawerContent = {
                            PermanentDrawerSheet(
                                modifier = Modifier.width(240.dp),
                                windowInsets = WindowInsets.safeDrawing.only(WindowInsetsSides.Start + WindowInsetsSides.Vertical)
                            ) {
                                navigationContent()
                            }
                        }
                    ) {
                        Box(Modifier.consumeWindowInsets(WindowInsets.safeDrawing.only(WindowInsetsSides.Start))) {
                            AppContent(
                                navController = navController,
                                playbackManager = playbackManager,
                                startDestination = startDestination,
                                currentDestination = currentDestination,
                                onMenuClick = null
                            )
                        }
                    }
                } else {
                    ModalNavigationDrawer(
                        drawerState = drawerState,
                        gesturesEnabled = isTopLevelDestination,
                        drawerContent = {
                            if (isTopLevelDestination) {
                                ModalDrawerSheet(
                                    modifier = Modifier.width(240.dp),
                                    windowInsets = WindowInsets.safeDrawing.only(WindowInsetsSides.Start + WindowInsetsSides.Vertical)
                                ) {
                                    navigationContent()
                                }
                            }
                        }
                    ) {
                        AppContent(
                            navController = navController,
                            playbackManager = playbackManager,
                            startDestination = startDestination,
                            currentDestination = currentDestination,
                            onMenuClick = if (isTopLevelDestination) {
                                { scope.launch { drawerState.open() } }
                            } else null
                        )
                    }
                }
                }
            }
        }
    }
}

@Composable
fun AppContent(
    navController: androidx.navigation.NavHostController,
    playbackManager: PlaybackManager,
    startDestination: String,
    currentDestination: androidx.navigation.NavDestination?,
    onMenuClick: (() -> Unit)?
) {
    Scaffold(
        modifier = Modifier.fillMaxSize(),
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            if (currentDestination?.route != Screen.Player.route) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom))
                ) {
                    MiniPlayer(
                        playbackManager = playbackManager,
                        onClick = { navController.navigate(Screen.Player.route) }
                    )
                }
            }
        }
    ) { innerPadding ->
        AudexNavGraph(
            navController = navController,
            startDestination = startDestination,
            onMenuClick = onMenuClick,
            modifier = Modifier.padding(innerPadding)
        )
    }
}
