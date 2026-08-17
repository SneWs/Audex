package se.grenangen.audex.data.local

interface TokenProvider {
    fun getToken(): String?
}
