package se.grenangen.audex.ui.screen.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import io.ktor.client.*
import io.ktor.client.request.*
import io.ktor.http.*
import kotlinx.coroutines.launch
import se.grenangen.audex.data.local.SettingsManager
import se.grenangen.audex.data.repository.AuthRepository
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsManager: SettingsManager,
    private val authRepository: AuthRepository,
    private val httpClient: HttpClient
) : ViewModel() {
    var serverUri by mutableStateOf(settingsManager.getServerUri() ?: "")
    var error by mutableStateOf<String?>(null)
    var successMessage by mutableStateOf<String?>(null)
    var isValidating by mutableStateOf(false)
    val darkMode = settingsManager.darkMode

    fun setDarkMode(enabled: Boolean) {
        settingsManager.setDarkMode(enabled)
    }

    fun saveServerUri(onSuccess: (() -> Unit)? = null) {
        viewModelScope.launch {
            error = null
            successMessage = null
            
            if (!settingsManager.isValidUri(serverUri)) {
                error = "Invalid Server URI"
                return@launch
            }

            val cleanUri = if (serverUri.endsWith("/")) serverUri else "$serverUri/"

            if (authRepository.isLoggedIn()) {
                isValidating = true
                try {
                    // Test the URI by fetching books. Since we pass a full URL, 
                    // the interceptor won't overwrite the host, but the Auth plugin 
                    // will still try to add the bearer token.
                    val response = httpClient.get("${cleanUri}books")
                    if (response.status.isSuccess()) {
                        settingsManager.saveServerUri(cleanUri)
                        successMessage = "Settings saved and validated"
                        onSuccess?.invoke()
                    } else {
                        error = "Server validation failed (HTTP ${response.status.value})"
                    }
                } catch (e: Exception) {
                    error = "Connection failed: ${e.localizedMessage}"
                } finally {
                    isValidating = false
                }
            } else {
                settingsManager.saveServerUri(cleanUri)
                successMessage = "Settings saved"
                onSuccess?.invoke()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onSuccess: (() -> Unit)? = null,
    onMenuClick: (() -> Unit)? = null,
    viewModel: SettingsViewModel = hiltViewModel()
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    if (onMenuClick != null) {
                        IconButton(onClick = onMenuClick) {
                            Icon(Icons.Default.Menu, contentDescription = "Menu")
                        }
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(padding)
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "Server Configuration",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.align(Alignment.Start)
            )
            Spacer(modifier = Modifier.height(16.dp))
            TextField(
                value = viewModel.serverUri,
                onValueChange = { 
                    viewModel.serverUri = it
                    viewModel.error = null
                    viewModel.successMessage = null
                },
                label = { Text("Server URI") },
                placeholder = { Text("https://your-server.com/api") },
                modifier = Modifier.fillMaxWidth(),
                isError = viewModel.error != null,
                supportingText = {
                    if (viewModel.error != null) {
                        Text(viewModel.error!!)
                    } else if (viewModel.successMessage != null) {
                        Text(viewModel.successMessage!!, color = MaterialTheme.colorScheme.primary)
                    }
                }
            )
            Spacer(modifier = Modifier.height(24.dp))
            Button(
                onClick = { viewModel.saveServerUri(onSuccess) },
                modifier = Modifier.fillMaxWidth(),
                enabled = !viewModel.isValidating
            ) {
                if (viewModel.isValidating) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = MaterialTheme.colorScheme.onPrimary,
                        strokeWidth = 2.dp
                    )
                } else {
                    Text(if (onSuccess != null) "Save and Continue" else "Save Settings")
                }
            }
            Spacer(modifier = Modifier.height(32.dp))
            Text(
                text = "Appearance",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.align(Alignment.Start)
            )
            Spacer(modifier = Modifier.height(8.dp))
            val darkMode by viewModel.darkMode.collectAsState()
            ListItem(
                headlineContent = { Text("Dark mode") },
                supportingContent = { Text("Use the darker Audex color palette") },
                trailingContent = {
                    Switch(
                        checked = darkMode,
                        onCheckedChange = viewModel::setDarkMode
                    )
                },
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}
