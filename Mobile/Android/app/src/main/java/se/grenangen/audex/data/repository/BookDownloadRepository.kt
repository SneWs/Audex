package se.grenangen.audex.data.repository

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import se.grenangen.audex.data.local.SettingsManager
import se.grenangen.audex.data.local.TokenProvider
import se.grenangen.audex.data.model.BookDetailDto
import java.io.File
import java.io.IOException
import java.net.URL
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class BookDownloadRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    private val settingsManager: SettingsManager,
    private val tokenProvider: TokenProvider,
    private val okHttpClient: OkHttpClient
) {
    suspend fun downloadBook(book: BookDetailDto, onProgress: (downloaded: Int, total: Int) -> Unit) = withContext(Dispatchers.IO) {
        val chapters = book.chapters.orEmpty()
            .sortedBy { it.trackNumber }
            .filter { it.downloadUrl.isNotBlank() }
        val total = chapters.size
        if (total == 0) return@withContext

        val safeBookName = sanitizeFileName(book.title.ifBlank { "book-${book.id}" })
        val targetDir = File(context.filesDir, "offline-books/$safeBookName")
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            throw IOException("Failed to create offline directory for ${book.title}")
        }

        var completed = 0
        coroutineScope {
            chapters.map { chapter ->
                async {
                    val extension = chapterExtensionFromUrl(chapter.downloadUrl)
                    val chapterBaseName = "${chapter.trackNumber.toString().padStart(3, '0')}-${sanitizeFileName(chapter.title)}"
                    val targetFile = File(targetDir, "$chapterBaseName$extension")
                    if (!targetFile.exists() || targetFile.length() == 0L) {
                        downloadFile(chapter.downloadUrl, targetFile)
                    }
                    synchronized(this@BookDownloadRepository) {
                        completed += 1
                        onProgress(completed, total)
                    }
                }
            }.awaitAll()
        }
    }

    private fun downloadFile(relativeUrl: String, targetFile: File) {
        val baseUri = settingsManager.getServerUri()
            ?: throw IllegalStateException("Server URI is not configured")
        val absoluteUrl = URL(URL(baseUri), relativeUrl).toString()
        val requestBuilder = Request.Builder().url(absoluteUrl)
        tokenProvider.getToken()?.let { token ->
            requestBuilder.addHeader("Authorization", "Bearer $token")
        }

        okHttpClient.newCall(requestBuilder.build()).execute().use { response ->
            if (!response.isSuccessful) {
                throw IOException("Download failed (${response.code}) for $absoluteUrl")
            }
            val body = response.body ?: throw IOException("Empty response body for $absoluteUrl")
            targetFile.outputStream().use { output ->
                body.byteStream().use { input ->
                    input.copyTo(output)
                }
            }
        }
    }

    private fun sanitizeFileName(name: String): String =
        name.replace(Regex("[^a-zA-Z0-9._-]"), "_")

    private fun chapterExtensionFromUrl(url: String): String {
        val ext = File(url.substringBefore('?')).extension
        return if (ext.isBlank()) ".mp3" else ".${ext.lowercase()}"
    }
}
