package com.isabelle.accessibility

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import java.io.File

/**
 * Isolated cleanup helper for retry functionality - inspired by ChatGPT patterns
 * Provides clean state reset without affecting other components
 */
object ServiceCleanupHelper {
    private const val TAG = "ServiceCleanupHelper"
    
    /**
     * Clean up download state for retry
     */
    fun cleanupDownloadState(context: Context) {
        Log.i(TAG, "🧹 Cleaning up download state for retry...")
        
        try {
            // Clear SharedPreferences
            val prefs = context.getSharedPreferences("gemma_download", Context.MODE_PRIVATE)
            prefs.edit().apply {
                remove("download_completed")
                remove("model_status")
                remove("model_path")
                remove("last_error")
                remove("last_update")
                remove("model_size")
                apply()
            }
            Log.i(TAG, "✅ Cleared download preferences")
            
            // Remove incomplete model files
            val appDocDir = File(context.filesDir, "app_flutter")
            val modelDir = File(appDocDir, "isabelle_models")
            val modelFile = File(modelDir, "gemma-3n-E4B-it-int4.task")
            
            if (modelFile.exists()) {
                val deleted = modelFile.delete()
                Log.i(TAG, if (deleted) "✅ Removed incomplete model file" else "⚠️ Failed to remove model file")
            }
            
            // Clear any temporary files
            val tempFiles = modelDir.listFiles { file -> file.name.contains("temp") || file.name.contains("partial") }
            tempFiles?.forEach { tempFile ->
                val deleted = tempFile.delete()
                Log.d(TAG, "Removed temp file: ${tempFile.name} - success: $deleted")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error during cleanup", e)
        }
    }
    
    /**
     * Clean up call state for retry
     */
    fun cleanupCallState(context: Context) {
        Log.i(TAG, "📞 Cleaning up call state for retry...")
        
        try {
            val prefs = context.getSharedPreferences("call_state", Context.MODE_PRIVATE)
            prefs.edit().apply {
                remove("active_call_id")
                remove("call_start_time")
                remove("emergency_call_active")
                remove("transcription_active")
                apply()
            }
            Log.i(TAG, "✅ Cleared call state preferences")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error during call cleanup", e)
        }
    }
    
    /**
     * Clean up service state for retry
     */
    fun cleanupServiceState(context: Context) {
        Log.i(TAG, "🔧 Cleaning up service state for retry...")
        
        try {
            // Clear service-specific preferences
            val servicePrefs = context.getSharedPreferences("service_state", Context.MODE_PRIVATE)
            servicePrefs.edit().apply {
                remove("audio_service_running")
                remove("transcription_service_running")
                remove("emergency_service_running")
                remove("last_service_error")
                apply()
            }
            Log.i(TAG, "✅ Cleared service state preferences")
            
            // Clear any cached audio files
            val audioDir = File(context.cacheDir, "audio_cache")
            if (audioDir.exists()) {
                val deleted = audioDir.deleteRecursively()
                Log.i(TAG, if (deleted) "✅ Cleared audio cache" else "⚠️ Failed to clear audio cache")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error during service cleanup", e)
        }
    }
    
    /**
     * Full cleanup for complete retry
     */
    fun performFullCleanup(context: Context) {
        Log.w(TAG, "🧹 Performing FULL cleanup for retry...")
        
        cleanupDownloadState(context)
        cleanupCallState(context)
        cleanupServiceState(context)
        
        // Clear general app state
        try {
            val appPrefs = context.getSharedPreferences("app_state", Context.MODE_PRIVATE)
            appPrefs.edit().apply {
                remove("initialization_failed")
                remove("critical_error")
                remove("retry_count")
                putLong("last_cleanup_time", System.currentTimeMillis())
                apply()
            }
            Log.i(TAG, "✅ Full cleanup completed")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error during full cleanup", e)
        }
    }
    
    /**
     * Check if cleanup is needed based on error conditions
     */
    fun isCleanupNeeded(context: Context): Boolean {
        try {
            val prefs = context.getSharedPreferences("gemma_download", Context.MODE_PRIVATE)
            val hasError = prefs.getString("last_error", "")?.isNotEmpty() ?: false
            val isIncomplete = prefs.getString("model_status", "") == "FAILED"
            
            return hasError || isIncomplete
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error checking cleanup need", e)
            return true // Assume cleanup needed on error
        }
    }
    
    /**
     * Get retry count and increment it
     */
    fun getAndIncrementRetryCount(context: Context): Int {
        try {
            val prefs = context.getSharedPreferences("app_state", Context.MODE_PRIVATE)
            val currentCount = prefs.getInt("retry_count", 0)
            val newCount = currentCount + 1
            
            prefs.edit().putInt("retry_count", newCount).apply()
            Log.i(TAG, "🔄 Retry count: $newCount")
            
            return newCount
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error managing retry count", e)
            return 1
        }
    }
    
    /**
     * Reset retry count after successful operation
     */
    fun resetRetryCount(context: Context) {
        try {
            val prefs = context.getSharedPreferences("app_state", Context.MODE_PRIVATE)
            prefs.edit().remove("retry_count").apply()
            Log.i(TAG, "✅ Reset retry count")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error resetting retry count", e)
        }
    }
}