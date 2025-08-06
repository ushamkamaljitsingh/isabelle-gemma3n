package com.isabelle.accessibility

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import java.io.File
import java.util.concurrent.CompletionException

/**
 * GemmaRuntime - Singleton for managing Gemma initialization
 * Provides a ready gate to prevent race conditions
 */
object GemmaRuntime {
    private const val TAG = "GemmaRuntime"
    
    private var ready = CompletableDeferred<Boolean>()
    val isReady get() = ready.isCompleted && try { ready.getCompleted() } catch (e: Exception) { false }
    
    @Volatile
    private var isInitializing = false
    
    @Volatile
    private var gemmaProcessor: Gemma3nProcessor? = null
    
    @Volatile
    private var hasBeenInitialized = false
    
    /**
     * Ensure Gemma is initialized before use
     */
    suspend fun ensureInit(context: Context, modelPath: String): Boolean {
        // Check if we have a valid initialized processor
        if (hasBeenInitialized && gemmaProcessor != null) {
            val processor = Gemma3nProcessor.getInstance(context)
            val modelInfo = processor.getModelInfo()
            if (modelInfo["initialized"] == true) {
                Log.d(TAG, "✅ Gemma already initialized and ready (reusing existing instance)")
                if (!ready.isCompleted) {
                    ready.complete(true)
                }
                return true
            }
        }
        
        if (isReady) {
            Log.d(TAG, "✅ Gemma already ready")
            return true
        }
        
        if (isInitializing) {
            Log.d(TAG, "⏳ Gemma initialization in progress, waiting...")
            return awaitReady()
        }
        
        isInitializing = true
        
        return withContext(Dispatchers.IO) {
            try {
                Log.i(TAG, "🚀 Initializing Gemma runtime...")
                Log.i(TAG, "⏰ Start time: ${java.text.SimpleDateFormat("HH:mm:ss.SSS").format(java.util.Date())}")
                
                // Check if model file exists
                val modelFile = File(modelPath)
                if (!modelFile.exists()) {
                    Log.e(TAG, "❌ Model file not found: $modelPath")
                    val error = IllegalArgumentException("Model file not found: $modelPath")
                    ready.completeExceptionally(error)
                    return@withContext false
                }
                
                Log.i(TAG, "📁 Model file found: ${modelFile.length() / (1024 * 1024)}MB")
                
                // Initialize Gemma3nProcessor singleton
                if (gemmaProcessor == null) {
                    gemmaProcessor = Gemma3nProcessor.getInstance(context)
                }
                
                Log.i(TAG, "🔄 Starting Gemma3nProcessor initialization...")
                val initStartTime = System.currentTimeMillis()
                
                val success = try {
                    gemmaProcessor!!.initialize(modelPath)
                } catch (e: OutOfMemoryError) {
                    Log.e(TAG, "❌ Out of memory during model initialization", e)
                    ready.completeExceptionally(e)
                    throw e
                } catch (e: RuntimeException) {
                    if (e.message?.contains("Timeout loading .task file") == true) {
                        Log.e(TAG, "❌ Model loading timed out - file may be too large or corrupted", e)
                        ready.completeExceptionally(e)
                    } else {
                        Log.e(TAG, "❌ Runtime error during initialization", e)
                        ready.completeExceptionally(e)
                    }
                    throw e
                }
                
                val initTime = System.currentTimeMillis() - initStartTime
                
                if (success) {
                    Log.i(TAG, "✅ Gemma runtime initialized successfully in ${initTime}ms")
                    Log.i(TAG, "⏰ End time: ${java.text.SimpleDateFormat("HH:mm:ss.SSS").format(java.util.Date())}")
                    hasBeenInitialized = true
                    ready.complete(true)
                } else {
                    Log.e(TAG, "❌ Gemma3nProcessor initialization returned false after ${initTime}ms")
                    gemmaProcessor = null
                    val error = RuntimeException("Gemma3nProcessor initialization failed")
                    ready.completeExceptionally(error)
                }
                
                success
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Gemma initialization failed with exception: ${e.javaClass.simpleName}", e)
                Log.e(TAG, "💡 Error message: ${e.message}")
                
                // Provide specific error feedback
                when (e) {
                    is OutOfMemoryError -> {
                        Log.e(TAG, "💾 Insufficient memory to load model")
                        ready.completeExceptionally(e)
                    }
                    is IllegalStateException -> {
                        Log.e(TAG, "📱 Device compatibility issue")
                        ready.completeExceptionally(e)
                    }
                    is RuntimeException -> {
                        Log.e(TAG, "🔧 Runtime error during initialization")
                        ready.completeExceptionally(e)
                    }
                    else -> {
                        Log.e(TAG, "❓ Unexpected error type")
                        ready.completeExceptionally(e)
                    }
                }
                
                false
            } finally {
                isInitializing = false
                Log.i(TAG, "🔚 Gemma runtime initialization finished (success=${ready.isCompleted && ready.getCompleted()})")
            }
        }
    }
    
    /**
     * Wait for Gemma to be ready
     */
    suspend fun awaitReady(): Boolean {
        return try {
            ready.await()
        } catch (e: CompletionException) {
            // Extract the actual cause from CompletionException
            val cause = e.cause
            Log.e(TAG, "❌ Gemma initialization failed while waiting", cause ?: e)
            
            when (cause) {
                is OutOfMemoryError -> {
                    Log.e(TAG, "💾 Failed due to insufficient memory")
                }
                is IllegalStateException -> {
                    Log.e(TAG, "📱 Failed due to device compatibility")
                }
                is RuntimeException -> {
                    if (cause.message?.contains("Timeout") == true) {
                        Log.e(TAG, "⏱️ Failed due to timeout loading model")
                    } else {
                        Log.e(TAG, "🔧 Failed due to runtime error")
                    }
                }
                else -> {
                    Log.e(TAG, "❓ Failed with unexpected error")
                }
            }
            false
        } catch (e: CancellationException) {
            Log.e(TAG, "❌ Gemma initialization was cancelled", e)
            false
        } catch (e: Exception) {
            Log.e(TAG, "❌ Unexpected error waiting for Gemma ready", e)
            false
        }
    }
    
    /**
     * Check if Gemma is ready synchronously
     */
    fun isReadySync(): Boolean {
        return ready.isCompleted && ready.getCompleted()
    }
    
    /**
     * Reset the ready state (for testing or restart)
     */
    fun reset() {
        Log.w(TAG, "🔄 Resetting Gemma runtime state")
        gemmaProcessor?.cleanup()
        gemmaProcessor = null
        hasBeenInitialized = false
        isInitializing = false
        // Create a new CompletableDeferred since it can only be completed once
        ready = CompletableDeferred<Boolean>()
    }
    
    /**
     * Get the processor if ready
     */
    fun getProcessor(): Gemma3nProcessor? {
        return if (isReadySync()) {
            gemmaProcessor
        } else {
            Log.w(TAG, "⚠️ Attempted to get processor before ready")
            null
        }
    }
}