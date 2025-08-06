package com.isabelle.accessibility

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.*
import okhttp3.*
import java.io.*
import java.util.concurrent.TimeUnit

/**
 * Fast native Android downloader using OkHttp for maximum speed
 * Based on proven high-performance architecture achieving 50-90 MB/s
 */
class FastNativeDownloader(private val context: Context) {
    
    companion object {
        private const val TAG = "FastNativeDownloader"
        private const val BUFFER_SIZE = 512 * 1024 // 512KB buffer for optimal I/O
        private const val PROGRESS_UPDATE_INTERVAL = 1000 // Update every 1 second
    }
    
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS) // No read timeout for large files
        .retryOnConnectionFailure(true)
        .build()
    
    private var currentJob: Job? = null
    private var eventSink: EventChannel.EventSink? = null
    
    fun setEventSink(sink: EventChannel.EventSink) {
        eventSink = sink
    }
    
    fun startDownload(url: String, targetPath: String) {
        currentJob = CoroutineScope(Dispatchers.IO).launch {
            try {
                downloadWithOkHttp(url, targetPath)
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    eventSink?.success(mapOf(
                        "status" to "error",
                        "error" to e.message
                    ))
                }
            }
        }
    }
    
    fun cancelDownload() {
        currentJob?.cancel()
        currentJob = null
    }
    
    private suspend fun downloadWithOkHttp(url: String, targetPath: String) {
        Log.d(TAG, "🚀 Starting OkHttp download from: $url")
        Log.d(TAG, "📁 Target: $targetPath")
        
        val request = Request.Builder()
            .url(url)
            .addHeader("User-Agent", "ISABELLE-Native-Android/1.0")
            .addHeader("Accept-Encoding", "identity") // Disable compression for raw speed
            .build()
        
        val call = client.newCall(request)
        val response = call.execute()
        
        if (!response.isSuccessful) {
            throw IOException("HTTP ${response.code}: ${response.message}")
        }
        
        val body = response.body ?: throw IOException("Response body is null")
        val totalSize = body.contentLength()
        
        if (totalSize <= 0) {
            throw IOException("Cannot determine file size")
        }
        
        Log.d(TAG, "📊 File size: ${totalSize / (1024 * 1024)} MB")
        
        // Create target file
        val targetFile = File(targetPath)
        Log.d(TAG, "📁 Target file path: $targetPath")
        Log.d(TAG, "📁 Target file parent: ${targetFile.parentFile?.absolutePath}")
        targetFile.parentFile?.mkdirs()
        
        // Download with progress tracking
        val startTime = System.currentTimeMillis()
        var lastProgressUpdate = 0L
        var downloadedBytes = 0L
        
        body.byteStream().use { input ->
            FileOutputStream(targetFile).use { output ->
                val buffer = ByteArray(BUFFER_SIZE)
                var bytesRead: Int
                
                while (input.read(buffer).also { bytesRead = it } != -1) {
                    // Check if cancelled
                    if (currentJob?.isCancelled == true) {
                        throw IOException("Download cancelled")
                    }
                    
                    output.write(buffer, 0, bytesRead)
                    downloadedBytes += bytesRead
                    
                    // Update progress periodically
                    val currentTime = System.currentTimeMillis()
                    if (currentTime - lastProgressUpdate >= PROGRESS_UPDATE_INTERVAL) {
                        val elapsedMs = currentTime - startTime
                        val speedBps = if (elapsedMs > 0) (downloadedBytes * 1000) / elapsedMs else 0
                        val percentage = ((downloadedBytes.toDouble() / totalSize) * 100).toInt()
                        
                        withContext(Dispatchers.Main) {
                            eventSink?.success(mapOf(
                                "downloaded" to downloadedBytes,  // Keep as Long to avoid overflow
                                "total" to totalSize,             // Keep as Long to avoid overflow
                                "percentage" to percentage,
                                "speedBps" to speedBps,           // Keep as Long to avoid overflow
                                "elapsedMs" to elapsedMs.toInt()
                            ))
                        }
                        
                        lastProgressUpdate = currentTime
                        Log.d(TAG, "📊 Progress: $percentage% @ ${speedBps / (1024 * 1024)} MB/s")
                    }
                }
            }
        }
        
        // Final verification
        val finalSize = targetFile.length()
        if (finalSize != totalSize) {
            throw IOException("Download incomplete: $finalSize / $totalSize bytes")
        }
        
        Log.d(TAG, "✅ Download completed successfully")
        
        // Send completion event
        withContext(Dispatchers.Main) {
            Log.d(TAG, "📤 Sending completion event to Flutter")
            eventSink?.success(mapOf(
                "status" to "complete",
                "filePath" to targetPath
            ))
            Log.d(TAG, "📤 Completion event sent")
        }
    }
}