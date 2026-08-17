package se.grenangen.audex.ui.screen.login

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import se.grenangen.audex.data.model.LoginRequest
import se.grenangen.audex.data.repository.AuthRepository
import javax.inject.Inject

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authRepository: AuthRepository
) : ViewModel() {

    private val _email = MutableStateFlow("")
    val email = _email.asStateFlow()

    private val _password = MutableStateFlow("")
    val password = _password.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    fun onEmailChange(value: String) { _email.value = value }
    fun onPasswordChange(value: String) { _password.value = value }

    fun login(onSuccess: () -> Unit) {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            val result = authRepository.login(LoginRequest(_email.value, _password.value))
            _isLoading.value = false
            result.onSuccess {
                onSuccess()
            }.onFailure { e ->
                _error.value = when (e) {
                    is io.ktor.client.plugins.ClientRequestException -> {
                        if (e.response.status == io.ktor.http.HttpStatusCode.Unauthorized) {
                            "Invalid email or password"
                        } else {
                            "Login failed: ${e.response.status.description}"
                        }
                    }
                    else -> e.message ?: "An unexpected error occurred"
                }
            }
        }
    }
}
