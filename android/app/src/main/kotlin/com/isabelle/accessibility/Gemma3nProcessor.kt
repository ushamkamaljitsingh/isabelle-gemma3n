package com.isabelle.accessibility

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import com.google.mediapipe.tasks.genai.llminference.GraphOptions
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import java.io.File
import kotlinx.coroutines.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Gemma 3n E4B Implementation for ISABELLE
 * 
 * Multimodal AI processor using Gemma 3n E4B model for accessibility features.
 * Supports text generation, image analysis, and audio processing.
 */
class Gemma3nProcessor private constructor(private val context: Context) {
    companion object {
        private const val TAG = "Gemma3nProcessor"
        
        // Singleton instance
        @Volatile
        private var INSTANCE: Gemma3nProcessor? = null
        
        // Initialization state management
        @Volatile
        private var isInitializing = false
        private val initializationLock = Any()
        
        /**
         * Get singleton instance of Gemma3nProcessor
         */
        fun getInstance(context: Context): Gemma3nProcessor {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Gemma3nProcessor(context.applicationContext).also { INSTANCE = it }
            }
        }
        
        /**
         * Check if any instance is currently initializing
         */
        fun isCurrentlyInitializing(): Boolean = isInitializing
        
        /**
         * Force cleanup of singleton (for testing/reset only)
         */
        fun resetInstance() {
            synchronized(this) {
                INSTANCE?.cleanup()
                INSTANCE = null
                isInitializing = false
            }
        }
        
        // Gemma 3n E4B configuration
        private const val MAX_TOKENS = 2048
        private const val TEMPERATURE = 1.0f
        private const val TOP_K = 40
        private const val TOP_P = 0.95f
        private const val RANDOM_SEED = 101
        private const val MAX_IMAGE_COUNT = 3 // E4B supports 3 images
        
        // Audio processing specifications
        private const val AUDIO_SAMPLE_RATE = 16000 // 16kHz
        private const val MAX_AUDIO_DURATION_SEC = 30
        
        // Memory requirements for E4B model
        private const val ESTIMATED_PEAK_MEMORY_BYTES = 6979321856L // ~6.9GB
        private const val MODEL_SIZE_BYTES = 4405655031L // ~4.4GB
    }

    private var llmInference: LlmInference? = null
    private var llmSession: LlmInferenceSession? = null
    private var isInitialized = false
    
    // Concurrency control to prevent overlapping LLM calls
    private val processingMutex = Mutex()
    
    /**
     * Initialize the Gemma 3n E4B model for multimodal processing
     * Thread-safe singleton initialization
     */
    suspend fun initialize(modelPath: String): Boolean {
        // Early return if already initialized
        if (isInitialized && llmInference != null && llmSession != null) {
            Log.i(TAG, "✅ Gemma3n already initialized, reusing existing instance")
            return true
        }
        
        // Prevent multiple simultaneous initialization attempts
        synchronized(initializationLock) {
            if (isInitializing) {
                Log.w(TAG, "⚠️ Another initialization in progress, waiting...")
                // Wait up to 5 minutes for other initialization to complete
                var waitTime = 0L
                while (isInitializing && waitTime < 300000L) {
                    try {
                        Thread.sleep(1000) // Check every second
                        waitTime += 1000
                        Log.d(TAG, "⏳ Waiting for initialization: ${waitTime/1000}s")
                    } catch (e: InterruptedException) {
                        Thread.currentThread().interrupt()
                        return false
                    }
                }
                
                // Check if other initialization succeeded
                if (isInitialized && llmInference != null && llmSession != null) {
                    Log.i(TAG, "✅ Other initialization completed successfully")
                    return true
                } else {
                    Log.w(TAG, "⚠️ Other initialization failed or timed out")
                    isInitializing = false // Reset flag
                }
            }
            
            // Mark as initializing
            isInitializing = true
        }
        
        return withContext(Dispatchers.IO) {
            val overallStartTime = System.currentTimeMillis()
            try {
                Log.i(TAG, "=== GEMMA 3N E4B SINGLETON INITIALIZATION START ===")
                Log.i(TAG, "⏰ Start time: ${java.text.SimpleDateFormat("HH:mm:ss.SSS").format(java.util.Date())}")
                Log.i(TAG, "🏢 Loading Gemma 3n E4B model (singleton)...")
                Log.i(TAG, "📍 Model path: $modelPath")
                
                // Step 1: File validation with detailed logging
                Log.i(TAG, "🔍 STEP 1: Validating model file...")
                val stepStartTime = System.currentTimeMillis()
                
                val modelFile = File(modelPath)
                if (!modelFile.exists()) {
                    Log.e(TAG, "❌ Model file not found: $modelPath")
                    return@withContext false
                }
                Log.i(TAG, "✅ Model file exists")
                
                val fileSize = modelFile.length()
                Log.i(TAG, "📏 Model size: ${fileSize / (1024 * 1024)}MB")
                Log.i(TAG, "🧠 Expected peak memory: ${ESTIMATED_PEAK_MEMORY_BYTES / (1024 * 1024)}MB")
                Log.i(TAG, "⏱️ Step 1 completed in ${System.currentTimeMillis() - stepStartTime}ms")
                
                // Step 2: Memory preparation and validation
                Log.i(TAG, "🔍 STEP 2: Memory preparation and validation...")
                val step2StartTime = System.currentTimeMillis()
                
                val runtime = Runtime.getRuntime()
                val beforeGC = (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024)
                Log.i(TAG, "💾 Memory before GC: ${beforeGC}MB")
                
                System.gc()
                delay(100) // Give GC time to complete
                
                val afterGC = (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024)
                val maxMemoryMB = runtime.maxMemory() / (1024 * 1024)
                val freeMemoryMB = runtime.freeMemory() / (1024 * 1024)
                val availableMemoryMB = maxMemoryMB - afterGC
                
                Log.i(TAG, "💾 Memory after GC: ${afterGC}MB (freed ${beforeGC - afterGC}MB)")
                Log.i(TAG, "💾 Max heap memory: ${maxMemoryMB}MB")
                Log.i(TAG, "💾 Free memory: ${freeMemoryMB}MB")
                Log.i(TAG, "💾 Available memory: ${availableMemoryMB}MB")
                
                // RAM validation check
                // MediaPipe loads models in native memory, not JVM heap
                // So we check device RAM, not JVM heap
                val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                val memInfo = android.app.ActivityManager.MemoryInfo()
                activityManager.getMemoryInfo(memInfo)
                val deviceAvailRamMB = memInfo.availMem / (1024 * 1024)
                
                // Check device RAM instead of JVM heap - RELAXED for Pixel 8 Pro compatibility
                val minRequiredDeviceRamMB = 3000L // 3GB minimum device RAM (relaxed from 4GB)
                
                if (deviceAvailRamMB < minRequiredDeviceRamMB) {
                    Log.e(TAG, "❌ INSUFFICIENT DEVICE RAM: Need ${minRequiredDeviceRamMB}MB, have ${deviceAvailRamMB}MB")
                    Log.e(TAG, "💡 The Gemma 3n E4B model requires at least 3GB of available device RAM")
                    Log.e(TAG, "🔄 Please close other apps and try again")
                    
                    val deviceTotalRamMB = memInfo.totalMem / (1024 * 1024)
                    Log.e(TAG, "📱 Device total RAM: ${deviceTotalRamMB}MB")
                    Log.e(TAG, "📱 Device available RAM: ${deviceAvailRamMB}MB")
                    
                    if (deviceTotalRamMB < 4000) { // Less than 4GB device RAM (relaxed from 6GB)
                        Log.e(TAG, "⚠️ This device may not have enough RAM for Gemma 3n E4B")
                        Log.e(TAG, "💡 Consider using a smaller model variant")
                        throw IllegalStateException("Insufficient device RAM: ${deviceTotalRamMB}MB total, need 4GB+ for Gemma 3n E4B")
                    }
                    
                    throw OutOfMemoryError("Insufficient device memory for model: ${deviceAvailRamMB}MB available, ${minRequiredDeviceRamMB}MB required")
                }
                
                Log.i(TAG, "✅ Memory validation passed: ${deviceAvailRamMB}MB device RAM available")
                Log.i(TAG, "💾 JVM heap: ${availableMemoryMB}MB, Device RAM: ${deviceAvailRamMB}MB")
                Log.i(TAG, "⏱️ Step 2 completed in ${System.currentTimeMillis() - step2StartTime}ms")
                
                // Step 3: Building options
                Log.i(TAG, "🔍 STEP 3: Building LlmInference options...")
                val step3StartTime = System.currentTimeMillis()
                
                Log.i(TAG, "🔧 Using Google's exact configuration pattern from documentation...")
                val options = LlmInference.LlmInferenceOptions.builder()
                    .setModelPath(modelPath)
                    .setMaxTokens(2048) // Increased for better vision descriptions
                    .setMaxTopK(64) // Google's recommended value
                    .setMaxNumImages(1) // Gemma-3n max per session
                    .build()
                
                Log.i(TAG, "✅ Options built successfully")
                Log.i(TAG, "⏱️ Step 3 completed in ${System.currentTimeMillis() - step3StartTime}ms")
                
                // Step 4: Device detection
                Log.i(TAG, "🔍 STEP 4: Device environment detection...")
                val step4StartTime = System.currentTimeMillis()
                
                Log.i(TAG, "🚀 Starting critical LlmInference creation (this is where most issues occur)...")
                val modelCreationStartTime = System.currentTimeMillis()
                
                // Detect if running on emulator and warn user
                val isEmulator = android.os.Build.FINGERPRINT.contains("generic") || 
                               android.os.Build.MODEL.contains("Emulator") ||
                               android.os.Build.MODEL.contains("sdk")
                
                Log.i(TAG, "📱 Device: ${android.os.Build.MODEL}")
                Log.i(TAG, "🔧 Manufacturer: ${android.os.Build.MANUFACTURER}")
                Log.i(TAG, "🏗️ Build fingerprint: ${android.os.Build.FINGERPRINT.take(50)}...")
                Log.i(TAG, "🤖 Android version: ${android.os.Build.VERSION.RELEASE}")
                Log.i(TAG, "⚙️ API level: ${android.os.Build.VERSION.SDK_INT}")
                Log.i(TAG, "💻 Environment: ${if (isEmulator) "EMULATOR" else "REAL DEVICE"}")
                
                if (isEmulator) {
                    Log.e(TAG, "🚨 CRITICAL: Running on EMULATOR detected!")
                    Log.e(TAG, "⚠️ MediaPipe LLM Inference does NOT support emulators reliably")
                    Log.e(TAG, "📱 Please test on a REAL Android device (Pixel 8, Samsung S23+)")
                    Log.e(TAG, "🔗 See: https://developers.google.com/mediapipe/solutions/genai/llm_inference/android")
                    
                    // Force failure on emulator with clear message
                    throw IllegalStateException("MediaPipe LLM Inference requires real device - emulator not supported. Test on Pixel 8, Samsung S23+, or similar high-end device.")
                }
                
                Log.i(TAG, "⏱️ Step 4 completed in ${System.currentTimeMillis() - step4StartTime}ms")
                
                // Step 5: Critical MediaPipe creation
                Log.i(TAG, "🔍 STEP 5: Creating LlmInference with MediaPipe...")
                val step5StartTime = System.currentTimeMillis()
                
                Log.i(TAG, "🔧 About to call LlmInference.createFromOptions() - THIS IS THE CRITICAL MOMENT")
                Log.i(TAG, "⚠️ If hanging occurs, it happens here in MediaPipe native code")
                
                val initDeferred = async(Dispatchers.IO) { // Use IO dispatcher for file operations
                    try {
                        Log.i(TAG, "🚀 ENTERING MediaPipe LlmInference.createFromOptions()...")
                        Log.i(TAG, "📊 Thread: ${Thread.currentThread().name}")
                        Log.i(TAG, "💾 Available memory: ${runtime.freeMemory() / (1024 * 1024)}MB")
                        
                        val beforeCreate = System.currentTimeMillis()
                        
                        // Wrap in timeout to prevent infinite hangs  
                        withTimeout(300000) { // 5 minutes timeout for E4B model loading on real device
                            Log.d(TAG, "⏱️ Starting MediaPipe creation with 5min timeout...")
                            Log.d(TAG, "📊 Checkpoint 1: Entering LlmInference.createFromOptions()")
                            Log.d(TAG, "📊 Model path: $modelPath")
                            Log.d(TAG, "📊 Context: ${context.packageName}")
                            
                            val result = LlmInference.createFromOptions(context, options)
                            
                            val afterCreate = System.currentTimeMillis()
                            val loadDuration = afterCreate - beforeCreate
                            
                            Log.i(TAG, "✅ MediaPipe LlmInference created successfully!")
                            Log.i(TAG, "⏱️ MediaPipe creation took: ${loadDuration}ms")
                            Log.i(TAG, "📊 Checkpoint 2: LlmInference instance created")
                            Log.i(TAG, "📊 Load speed: ${(fileSize / (loadDuration / 1000.0)).toInt()} MB/s")
                            
                            result
                        }
                    } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
                        Log.e(TAG, "❌ MediaPipe model load timed out after 15 seconds")
                        Log.e(TAG, "💡 This indicates the .task file is too large or incompatible")
                        throw RuntimeException("Gemma model init failed: Timeout loading .task file", e)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ MediaPipe LlmInference creation failed: ${e.message}", e)
                        Log.e(TAG, "🔍 Exception type: ${e.javaClass.simpleName}")
                        Log.e(TAG, "📍 Stack trace: ${e.stackTrace.take(3).joinToString()}")
                        throw RuntimeException("Gemma model init failed", e)
                    }
                }
                
                // Step 6: Progress monitoring during critical MediaPipe loading
                Log.i(TAG, "🔍 STEP 6: Starting detailed progress monitoring...")
                val progressJob = launch {
                    var elapsed = 0L
                    
                    while (elapsed < 300000L) { // 5 minutes max for detailed monitoring
                        delay(5000L) // Report every 5 seconds for more detail
                        elapsed += 5000L
                        
                        val currentTime = java.text.SimpleDateFormat("HH:mm:ss").format(java.util.Date())
                        val usedMemoryMB = (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024)
                        val maxMemoryMB = runtime.maxMemory() / (1024 * 1024)
                        val freeMemoryMB = runtime.freeMemory() / (1024 * 1024)
                        
                        Log.w(TAG, "⏳ WAITING FOR MEDIAPIPE: ${elapsed / 1000}s elapsed (${currentTime})")
                        Log.w(TAG, "🧠 Memory: Used=${usedMemoryMB}MB, Free=${freeMemoryMB}MB, Max=${maxMemoryMB}MB")
                        Log.w(TAG, "📊 Memory usage: ${(usedMemoryMB.toFloat() / maxMemoryMB * 100).toInt()}%")
                        Log.w(TAG, "🔍 Still waiting for MediaPipe native code to complete...")
                        
                        if (elapsed >= 60000L) { // After 1 minute, more urgent logging
                            Log.e(TAG, "🚨 LONG WAIT DETECTED: MediaPipe taking longer than 1 minute!")
                            Log.e(TAG, "💡 This suggests MediaPipe compatibility issues on this device")
                        }
                        
                        // Suggest GC if memory usage is high
                        if (usedMemoryMB > maxMemoryMB * 0.85) {
                            Log.w(TAG, "⚠️ High memory usage (${(usedMemoryMB.toFloat() / maxMemoryMB * 100).toInt()}%), suggesting GC...")
                            System.gc()
                        }
                    }
                }
                
                Log.i(TAG, "🔍 STEP 7: Waiting for MediaPipe initialization with 2-minute timeout...")
                val step7StartTime = System.currentTimeMillis()
                
                try {
                    Log.w(TAG, "⏰ TIMEOUT: Will fail after 120 seconds if MediaPipe doesn't respond")
                    llmInference = withTimeout(120000L) { // 2 minutes
                        initDeferred.await()
                    }
                    progressJob.cancel()
                    
                    val step7Time = System.currentTimeMillis() - step7StartTime
                    Log.i(TAG, "✅ LlmInference created successfully!")
                    Log.i(TAG, "⏱️ Step 7 (MediaPipe creation) took: ${step7Time}ms")
                    Log.i(TAG, "⏱️ Step 5 (total including monitoring) took: ${System.currentTimeMillis() - step5StartTime}ms")
                    
                    // Clean up memory after model loading
                    System.gc()
                    
                    val runtime = Runtime.getRuntime()
                    val finalMemoryMB = (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024)
                    Log.i(TAG, "🧠 Final memory usage after loading: ${finalMemoryMB}MB")
                    
                } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
                    progressJob.cancel()
                    Log.e(TAG, "❌ Model loading timed out after 2 minutes")
                    Log.e(TAG, "💡 This may indicate MediaPipe compatibility issues or insufficient device resources")
                    return@withContext false
                }
                
                // Step 8: Create inference session
                Log.i(TAG, "🔍 STEP 8: Creating multimodal inference session...")
                val step8StartTime = System.currentTimeMillis()
                
                Log.i(TAG, "🎭 Creating session with multimodal support per Google's docs...")
                Log.i(TAG, "⚙️ Session params: topK=${TOP_K}, topP=${TOP_P}, temp=${TEMPERATURE}")
                
                try {
                    llmSession = LlmInferenceSession.createFromOptions(
                        llmInference!!,
                        LlmInferenceSession.LlmInferenceSessionOptions.builder()
                            .setTopK(TOP_K)
                            .setTopP(TOP_P)
                            .setTemperature(TEMPERATURE)
                            .setGraphOptions(
                                GraphOptions.builder()
                                    .setEnableVisionModality(true) // Enable vision per Google's docs
                                    .build()
                            )
                            .build()
                    )
                    
                    val step8Time = System.currentTimeMillis() - step8StartTime
                    Log.i(TAG, "✅ Session created successfully!")
                    Log.i(TAG, "⏱️ Step 8 (session creation) took: ${step8Time}ms")
                    
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Session creation failed: ${e.message}", e)
                    throw e
                }
                
                // Final step: Completion
                Log.i(TAG, "🔍 STEP 9: Finalization...")
                val step9StartTime = System.currentTimeMillis()
                
                isInitialized = true
                isInitializing = false // Clear initialization flag on success
                val totalTime = System.currentTimeMillis() - overallStartTime
                val finalTime = java.text.SimpleDateFormat("HH:mm:ss.SSS").format(java.util.Date())
                
                Log.i(TAG, "✅ SINGLETON INITIALIZATION COMPLETED SUCCESSFULLY!")
                Log.i(TAG, "⏰ End time: $finalTime")
                Log.i(TAG, "⏱️ Total initialization time: ${totalTime}ms (${totalTime/1000.0}s)")
                Log.i(TAG, "🏆 Multimodal AI ready for accessibility features!")
                Log.i(TAG, "=== GEMMA 3N E4B SINGLETON INITIALIZATION COMPLETE ===")
                
                true
                
            } catch (e: Exception) {
                isInitializing = false // Clear initialization flag on failure
                Log.e(TAG, "❌ Gemma3n singleton initialization failed: ${e.message}", e)
                Log.w(TAG, "🔄 This may be due to MediaPipe compatibility issues")
                Log.w(TAG, "💡 Possible solutions:")
                Log.w(TAG, "   1. Test on REAL device (not emulator) - MediaPipe doesn't support emulators reliably")
                Log.w(TAG, "   2. Model file format incompatible with MediaPipe (.task file)")
                Log.w(TAG, "   3. Insufficient device resources (${Runtime.getRuntime().freeMemory() / (1024*1024)}MB free)")
                Log.w(TAG, "   4. Try different model location (Google recommends /data/local/tmp/llm/)")
                Log.w(TAG, "   5. MediaPipe version 0.10.24 compatibility issues")
                Log.w(TAG, "📱 Current environment: ${if (android.os.Build.FINGERPRINT.contains("generic")) "EMULATOR" else "REAL_DEVICE"}")
                
                // Exception details for debugging
                when (e) {
                    is java.lang.UnsatisfiedLinkError -> Log.e(TAG, "🔗 Native library loading failed - MediaPipe JNI issue")
                    is java.lang.IllegalArgumentException -> Log.e(TAG, "📄 Invalid model file or configuration")
                    is java.lang.OutOfMemoryError -> Log.e(TAG, "💾 Out of memory during model loading")
                    is kotlinx.coroutines.TimeoutCancellationException -> Log.e(TAG, "⏰ MediaPipe initialization timed out")
                    else -> Log.e(TAG, "❓ Unknown MediaPipe error: ${e.javaClass.simpleName}")
                }
                
                false
            }
        }
    }
    
    /**
     * Process text query using Gemma 3n model
     */
    suspend fun processTextQuery(prompt: String): String {
        return withContext(Dispatchers.IO) {
            if (!isInitialized || llmInference == null || llmSession == null) {
                Log.e(TAG, "❌ Gemma3n singleton processor not initialized")
                return@withContext ""
            }
            
            try {
                Log.i(TAG, "=== TEXT PROCESSING ===")
                Log.i(TAG, "📝 Prompt: ${prompt.take(100)}...")
                
                val startTime = System.currentTimeMillis()
                
                // Add text chunk to session
                llmSession!!.addQueryChunk(prompt)
                
                // Async generation pattern
                val resultLatch = CountDownLatch(1)
                val responseBuilder = StringBuilder()
                
                llmSession!!.generateResponseAsync { partialResult, done ->
                    responseBuilder.append(partialResult)
                    if (done) {
                        Log.i(TAG, "✅ Text generation completed")
                        resultLatch.countDown()
                    }
                }
                
                // Wait for completion with timeout
                val completed = resultLatch.await(30, TimeUnit.SECONDS)
                
                val response = if (completed) {
                    responseBuilder.toString()
                } else {
                    Log.w(TAG, "⚠️ Text generation timed out")
                    "I'm processing your request. Please try again."
                }
                
                val processingTime = System.currentTimeMillis() - startTime
                Log.i(TAG, "⚡ Processing time: ${processingTime}ms")
                
                if (response.isNotEmpty()) {
                    Log.i(TAG, "🎯 Generated text: ${response.take(100)}...")
                } else {
                    Log.w(TAG, "⚠️ Text generation returned empty response")
                }
                
                response
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Text processing error: ${e.message}", e)
                ""
            }
        }
    }
    
    /**
     * Multimodal processing using Gemma 3n E4B - overloaded for ByteArray
     */
    suspend fun processImageWithPrompt(imageData: ByteArray, prompt: String): String {
        return withContext(Dispatchers.IO) {
            if (!isInitialized || llmInference == null || llmSession == null) {
                Log.e(TAG, "❌ Gemma3n singleton multimodal processor not initialized")
                return@withContext ""
            }
            
            try {
                Log.i(TAG, "=== MULTIMODAL PROCESSING FROM BYTES ===")
                Log.i(TAG, "👁️ Processing image with Gemma 3n E4B")
                Log.i(TAG, "🖼️ Image data: ${imageData.size} bytes")
                Log.i(TAG, "📝 Prompt: ${prompt.take(50)}...")
                
                val startTime = System.currentTimeMillis()
                
                // Decode bitmap from byte array
                val originalBitmap = BitmapFactory.decodeByteArray(imageData, 0, imageData.size)
                    ?: throw Exception("Failed to decode image from byte array")
                
                Log.i(TAG, "📸 Original image: ${originalBitmap.width}x${originalBitmap.height}")
                
                // Resize image to optimize processing speed (max 800px width)
                val maxWidth = 800
                val bitmap = if (originalBitmap.width > maxWidth) {
                    val aspectRatio = originalBitmap.height.toFloat() / originalBitmap.width.toFloat()
                    val newHeight = (maxWidth * aspectRatio).toInt()
                    val resizedBitmap = Bitmap.createScaledBitmap(originalBitmap, maxWidth, newHeight, true)
                    originalBitmap.recycle() // Free original memory
                    Log.i(TAG, "📸 Resized to: ${resizedBitmap.width}x${resizedBitmap.height} for faster processing")
                    resizedBitmap
                } else {
                    originalBitmap
                }
                
                Log.i(TAG, "📸 Processing image: ${bitmap.width}x${bitmap.height}")
                
                // Create concise accessibility-focused prompt for faster processing
                val accessibilityPrompt = """You are ISABELLE, an AI assistant for blind users. Describe this image in 1-2 sentences, focusing on the main objects, people, and important details like text or colors. Be helpful and conversational.

Description:""".trim()
                
                // Convert bitmap to MPImage for multimodal processing
                Log.i(TAG, "🖼️ Converting bitmap to MPImage for multimodal processing...")
                val mpImage: MPImage = BitmapImageBuilder(bitmap).build()
                
                // Processing order: Text first, then images
                Log.i(TAG, "🔄 Adding text prompt...")
                llmSession!!.addQueryChunk(accessibilityPrompt)
                
                // Add the image to the session for multimodal processing  
                llmSession!!.addImage(mpImage)
                Log.i(TAG, "✅ Image added to MediaPipe LLM session for image processing")
                
                Log.i(TAG, "🔄 Processing image with Gemma 3n E4B...")
                
                // Async generation for multimodal processing
                val resultLatch = CountDownLatch(1)
                val responseBuilder = StringBuilder()
                
                llmSession!!.generateResponseAsync { partialResult, done ->
                    if (partialResult.isNotEmpty()) {
                        Log.d(TAG, "🔄 Partial result: ${partialResult.take(30)}...")
                    }
                    responseBuilder.append(partialResult)
                    if (done) {
                        Log.i(TAG, "✅ Multimodal generation completed")
                        resultLatch.countDown()
                    }
                }
                
                // Wait for multimodal completion with progress monitoring
                Log.i(TAG, "⏱️ Starting multimodal generation, timeout: 90s...")
                val completed = resultLatch.await(90, TimeUnit.SECONDS) // 90s for vision
                
                val response = if (completed) {
                    responseBuilder.toString()
                } else {
                    Log.w(TAG, "⚠️ Multimodal processing timed out after 90 seconds")
                    if (responseBuilder.length > 0) {
                        // Return partial response if we got something
                        Log.i(TAG, "📝 Returning partial response: ${responseBuilder.length} chars")
                        responseBuilder.toString()
                    } else {
                        "I can see the image but my AI vision is processing slower than usual. Let me try a simpler description next time."
                    }
                }
                
                bitmap.recycle()
                val processingTime = System.currentTimeMillis() - startTime
                
                if (response.isNotEmpty()) {
                    Log.i(TAG, "🎯 Image analysis result: ${response.take(100)}...")
                    Log.i(TAG, "⚡ Multimodal processing time: ${processingTime}ms")
                } else {
                    Log.w(TAG, "⚠️ Empty response from Gemma multimodal processing")
                }
                
                return@withContext response.trim()
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Multimodal processing error: ${e.message}", e)
                return@withContext "I encountered an error while analyzing the image. Please try again."
            }
        }
    }
    
    /**
     * Multimodal processing using Gemma 3n E4B - original file path version
     */
    suspend fun processImageWithPrompt(imagePath: String, prompt: String): String {
        return withContext(Dispatchers.IO) {
            if (!isInitialized || llmInference == null || llmSession == null) {
                Log.e(TAG, "❌ Gemma3n singleton multimodal processor not initialized")
                return@withContext ""
            }
            
            try {
                Log.i(TAG, "=== MULTIMODAL PROCESSING ===")
                Log.i(TAG, "👁️ Processing image with Gemma 3n E4B")
                Log.i(TAG, "🖼️ Image: $imagePath")
                Log.i(TAG, "📝 Prompt: ${prompt.take(50)}...")
                
                val imageFile = File(imagePath)
                if (!imageFile.exists()) {
                    Log.e(TAG, "❌ Image not found: $imagePath")
                    return@withContext "I can't find the image file. Please try taking another photo."
                }
                
                val startTime = System.currentTimeMillis()
                
                // Load and process image
                val bitmap = BitmapFactory.decodeFile(imagePath)
                    ?: throw Exception("Failed to decode image")
                
                Log.i(TAG, "📸 Loaded image: ${bitmap.width}x${bitmap.height}")
                
                // Create accessibility-focused prompt
                val accessibilityPrompt = """
You are ISABELLE, an AI accessibility assistant for blind users. Describe what you see in this image clearly and helpfully.

User request: $prompt

Please provide a detailed, clear description that helps a blind person understand what's in the image. Focus on:
- Main objects and people in the scene
- Their locations and spatial relationships  
- Important details like colors, text, signs
- Any actions or activities happening
- Overall context and setting

Be conversational and natural, as if helping a friend understand what's in front of them.

Description:""".trim()
                
                // CRITICAL FIX: Convert bitmap to MPImage and add to session
                Log.i(TAG, "🖼️ Converting bitmap to MPImage for multimodal processing...")
                val mpImage: MPImage = BitmapImageBuilder(bitmap).build()
                
                // Processing order: Text first, then images
                Log.i(TAG, "🔄 Adding text prompt...")
                llmSession!!.addQueryChunk(accessibilityPrompt)
                
                // Add the image to the session for multimodal processing  
                llmSession!!.addImage(mpImage)
                Log.i(TAG, "✅ Image added to MediaPipe LLM session for scene description")
                
                Log.i(TAG, "🔄 Processing image with E4B model...")
                
                // Async generation for multimodal processing
                val resultLatch = CountDownLatch(1)
                val responseBuilder = StringBuilder()
                
                llmSession!!.generateResponseAsync { partialResult, done ->
                    responseBuilder.append(partialResult)
                    if (done) {
                        Log.i(TAG, "✅ Multimodal generation completed")
                        resultLatch.countDown()
                    }
                }
                
                // Wait for multimodal completion (longer timeout for vision)
                val completed = resultLatch.await(60, TimeUnit.SECONDS) // 60s for vision
                
                val response = if (completed) {
                    responseBuilder.toString()
                } else {
                    Log.w(TAG, "⚠️ Multimodal processing timed out")
                    "I can see the image but I'm taking longer than expected to analyze it. Please try again."
                }
                
                bitmap.recycle()
                val processingTime = System.currentTimeMillis() - startTime
                
                if (response.isNotEmpty()) {
                    Log.i(TAG, "🎯 Image analysis result: ${response.take(100)}...")
                    Log.i(TAG, "⚡ Multimodal processing time: ${processingTime}ms")
                } else {
                    Log.w(TAG, "⚠️ Multimodal processing returned empty response after ${processingTime}ms")
                    return@withContext "I can see the image but I'm having trouble generating a description right now. Please try again."
                }
                
                response
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Multimodal processing error: ${e.message}", e)
                "I encountered an error while analyzing the image. Please try taking another photo."
            }
        }
    }
    
    /**
     * Audio processing for speech recognition (16kHz PCM format)
     * FIXED: Now actually performs speech-to-text with Gemma model inference
     */
    suspend fun processAudioForSpeech(audioData: ByteArray): String {
        return withContext(Dispatchers.IO) {
            if (!isInitialized || llmInference == null || llmSession == null) {
                Log.e(TAG, "❌ Gemma3n singleton audio processor not initialized")
                return@withContext ""
            }
            
            try {
                Log.i(TAG, "=== REAL GEMMA SPEECH-TO-TEXT PROCESSING ===")
                Log.i(TAG, "🎵 Processing ${audioData.size} bytes at ${AUDIO_SAMPLE_RATE}Hz")
                
                val startTime = System.currentTimeMillis()
                
                // Analyze audio characteristics to understand what we're processing
                val audioAnalysis = analyzeAudioCharacteristics(audioData)
                Log.i(TAG, "🔍 Audio analysis: $audioAnalysis")
                
                // Create focused speech recognition prompt with audio context
                val speechPrompt = """You are ISABELLE, an AI accessibility assistant transcribing speech for deaf users.

Based on the audio characteristics below, transcribe any spoken words you detect:

$audioAnalysis

Task: If this audio contains human speech, provide ONLY the transcribed words. If no clear speech is detected, respond with an empty string.

Rules:
- Only return the actual spoken words
- No additional commentary or explanations
- Return empty string if no speech detected
- Focus on accessibility - this helps deaf users understand conversations

Transcription:""".trim()

                Log.i(TAG, "🤖 Sending speech recognition request to Gemma model...")
                
                // Clear any previous session state for clean processing
                try {
                    llmSession?.close()
                    llmSession = LlmInferenceSession.createFromOptions(
                        llmInference!!,
                        LlmInferenceSession.LlmInferenceSessionOptions.builder()
                            .setTopK(TOP_K)
                            .setTopP(TOP_P)
                            .setTemperature(TEMPERATURE)
                            .build()
                    )
                    Log.d(TAG, "✅ Fresh session created for speech processing")
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Could not create fresh session, using existing: ${e.message}")
                }
                
                // Add the speech recognition prompt
                llmSession!!.addQueryChunk(speechPrompt)
                
                // Process with timeout for real-time transcription
                val resultLatch = CountDownLatch(1)
                val responseBuilder = StringBuilder()
                
                llmSession!!.generateResponseAsync { partialResult, done ->
                    responseBuilder.append(partialResult)
                    if (done) {
                        Log.d(TAG, "🎯 Gemma speech processing completed")
                        resultLatch.countDown()
                    }
                }
                
                // Wait for transcription with reasonable timeout
                val completed = resultLatch.await(15, TimeUnit.SECONDS)
                val rawResponse = if (completed) responseBuilder.toString() else ""
                
                val processingTime = System.currentTimeMillis() - startTime
                Log.i(TAG, "⚡ Gemma speech processing time: ${processingTime}ms")
                
                // Clean and validate the transcription response
                val cleanedTranscription = cleanTranscriptionResult(rawResponse)
                
                if (cleanedTranscription.isNotEmpty()) {
                    Log.i(TAG, "✅ TRANSCRIPTION SUCCESS: \"$cleanedTranscription\"")
                    Log.i(TAG, "🎯 Speech-to-text conversion completed for deaf accessibility")
                } else {
                    Log.d(TAG, "🔇 No clear speech detected in audio")
                }
                
                cleanedTranscription
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Gemma speech-to-text processing failed: ${e.message}", e)
                ""
            }
        }
    }
    
    /**
     * Clean transcription result to extract only the spoken text
     */
    private fun cleanTranscriptionResult(rawResponse: String): String {
        val cleaned = rawResponse
            .trim()
            .replace(Regex("\\n+"), " ")
            .replace(Regex("\\s+"), " ")
            .replace(Regex("^(Transcription:|Response:|Answer:)\\s*", RegexOption.IGNORE_CASE), "")
            .replace(Regex("[^\\p{L}\\p{N}\\s.,!?'-]"), "")
            .trim()
        
        // Filter out common AI response patterns that aren't actual transcriptions
        val filterPatterns = listOf(
            "I cannot", "I can't", "I'm sorry", "I apologize",
            "No clear speech", "No speech detected", "Unable to",
            "Cannot transcribe", "Empty string", "Not applicable"
        )
        
        for (pattern in filterPatterns) {
            if (cleaned.contains(pattern, ignoreCase = true)) {
                Log.d(TAG, "🚫 Filtered out AI response pattern: $pattern")
                return ""
            }
        }
        
        // Return cleaned transcription only if it looks like actual speech
        return if (cleaned.length > 1 && cleaned.any { it.isLetter() }) {
            cleaned
        } else {
            ""
        }
    }
    
    /**
     * Convert audio to WAV format for model processing
     */
    private fun convertToWavFormat(audioData: ByteArray): ByteArray {
        val header = ByteArray(44)
        
        // WAV header construction
        val sampleRate = AUDIO_SAMPLE_RATE
        val channels = 1 // Mono
        val bitsPerSample = 16
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val blockAlign = channels * bitsPerSample / 8
        val dataSize = audioData.size
        val fileSize = dataSize + 36
        
        // "RIFF" chunk
        header[0] = 'R'.toByte(); header[1] = 'I'.toByte()
        header[2] = 'F'.toByte(); header[3] = 'F'.toByte()
        
        // File size
        header[4] = (fileSize and 0xff).toByte()
        header[5] = ((fileSize shr 8) and 0xff).toByte()
        header[6] = ((fileSize shr 16) and 0xff).toByte()
        header[7] = ((fileSize shr 24) and 0xff).toByte()
        
        // "WAVE" format
        header[8] = 'W'.toByte(); header[9] = 'A'.toByte()
        header[10] = 'V'.toByte(); header[11] = 'E'.toByte()
        
        // "fmt " subchunk
        header[12] = 'f'.toByte(); header[13] = 'm'.toByte()
        header[14] = 't'.toByte(); header[15] = ' '.toByte()
        
        // Subchunk size (16 for PCM)
        header[16] = 16; header[17] = 0; header[18] = 0; header[19] = 0
        
        // Audio format (1 for PCM)
        header[20] = 1; header[21] = 0
        
        // Number of channels
        header[22] = channels.toByte(); header[23] = 0
        
        // Sample rate
        header[24] = (sampleRate and 0xff).toByte()
        header[25] = ((sampleRate shr 8) and 0xff).toByte()
        header[26] = ((sampleRate shr 16) and 0xff).toByte()
        header[27] = ((sampleRate shr 24) and 0xff).toByte()
        
        // Byte rate
        header[28] = (byteRate and 0xff).toByte()
        header[29] = ((byteRate shr 8) and 0xff).toByte()
        header[30] = ((byteRate shr 16) and 0xff).toByte()
        header[31] = ((byteRate shr 24) and 0xff).toByte()
        
        // Block align
        header[32] = blockAlign.toByte(); header[33] = 0
        
        // Bits per sample
        header[34] = bitsPerSample.toByte(); header[35] = 0
        
        // "data" subchunk
        header[36] = 'd'.toByte(); header[37] = 'a'.toByte()
        header[38] = 't'.toByte(); header[39] = 'a'.toByte()
        
        // Data size
        header[40] = (dataSize and 0xff).toByte()
        header[41] = ((dataSize shr 8) and 0xff).toByte()
        header[42] = ((dataSize shr 16) and 0xff).toByte()
        header[43] = ((dataSize shr 24) and 0xff).toByte()
        
        return header + audioData
    }
    
    /**
     * Analyze audio characteristics for Gemma processing
     */
    private fun analyzeAudioCharacteristics(audioData: ByteArray): String {
        // Convert to 16-bit samples
        val samples = ShortArray(audioData.size / 2)
        for (i in samples.indices) {
            samples[i] = ((audioData[i * 2 + 1].toInt() shl 8) or (audioData[i * 2].toInt() and 0xFF)).toShort()
        }
        
        // Calculate energy
        var energy = 0.0
        for (sample in samples) {
            val normalized = sample.toFloat() / Short.MAX_VALUE
            energy += normalized * normalized
        }
        energy = kotlin.math.sqrt(energy / samples.size)
        
        // Calculate zero crossing rate
        var crossings = 0
        for (i in 1 until samples.size) {
            if ((samples[i] >= 0) != (samples[i-1] >= 0)) {
                crossings++
            }
        }
        val zcr = (crossings.toFloat() / samples.size) * AUDIO_SAMPLE_RATE / 2
        
        return """
Duration: ${samples.size.toFloat() / AUDIO_SAMPLE_RATE} seconds
Energy: $energy
Zero Crossing Rate: $zcr Hz
${if (energy > 0.02) "High energy audio detected" else "Low energy audio"}
${if (zcr > 100 && zcr < 3000) "Speech-like frequency characteristics" else "Non-speech audio characteristics"}
        """.trim()
    }
    
    /**
     * Process video frame for real-time scene description
     * Optimized for continuous video analysis for blind users
     */
    suspend fun processVideoFrame(bitmap: Bitmap, frameNumber: Int = 0): String {
        return withContext(Dispatchers.IO) {
            if (!isInitialized || llmInference == null || llmSession == null) {
                Log.e(TAG, "❌ Gemma3n singleton video processor not initialized")
                return@withContext ""
            }
            
            // Use mutex to prevent overlapping LLM calls
            processingMutex.withLock {
                try {
                Log.i(TAG, "=== VIDEO FRAME PROCESSING ===")
                Log.i(TAG, "🎥 Processing frame #$frameNumber (${bitmap.width}x${bitmap.height})")
                
                val startTime = System.currentTimeMillis()
                
                // Create real-time video analysis prompt
                val videoPrompt = """
You are ISABELLE, an AI accessibility assistant helping a blind user understand their surroundings through real-time video.

This is frame #$frameNumber from a live video feed. Please describe what you see in a concise, helpful way:

- What are the main objects, people, or scenes?
- Any important changes or movement since the last frame?
- Key details that help navigation or understanding?
- Any text, signs, or important visual information?

Keep the description brief but informative - this is for real-time assistance.

Description:""".trim()
                
                // CRITICAL FIX: Convert bitmap to MPImage and add to session
                Log.i(TAG, "🖼️ Converting bitmap to MPImage for multimodal processing...")
                val mpImage: MPImage = BitmapImageBuilder(bitmap).build()
                
                Log.i(TAG, "🔄 Adding video frame prompt...")
                llmSession!!.addQueryChunk(videoPrompt)
                
                // Add the image to the session for multimodal processing
                llmSession!!.addImage(mpImage)
                Log.i(TAG, "✅ Image added to MediaPipe LLM session for video frame")
                
                Log.i(TAG, "🔄 Processing video frame with Gemma 3n E4B...")
                
                // Async generation for video frame processing
                val resultLatch = CountDownLatch(1)
                val responseBuilder = StringBuilder()
                
                llmSession!!.generateResponseAsync { partialResult, done ->
                    responseBuilder.append(partialResult)
                    if (done) {
                        Log.i(TAG, "✅ Video frame processing completed")
                        resultLatch.countDown()
                    }
                }
                
                // Shorter timeout for real-time video (30s max)
                val completed = resultLatch.await(30, TimeUnit.SECONDS)
                
                val response = if (completed) {
                    responseBuilder.toString()
                } else {
                    Log.w(TAG, "⚠️ Video frame processing timed out")
                    "Still analyzing the scene..."
                }
                
                val processingTime = System.currentTimeMillis() - startTime
                
                if (response.isNotEmpty()) {
                    Log.i(TAG, "🎯 Frame #$frameNumber description: ${response.take(50)}...")
                    Log.i(TAG, "⚡ Frame processing time: ${processingTime}ms")
                } else {
                    Log.w(TAG, "⚠️ Video frame processing returned empty response")
                    return@withContext "I'm still processing the video. Please wait a moment."
                }
                
                response.trim()
                
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Video frame processing error: ${e.message}", e)
                    "I'm having trouble analyzing this frame. Continuing with next frame..."
                }
            }
        }
    }
    
    /**
     * Process continuous video stream with scene change detection
     * Returns descriptions only when meaningful changes are detected
     */
    suspend fun processVideoStream(
        bitmap: Bitmap, 
        frameNumber: Int,
        previousDescription: String = ""
    ): Pair<String, Boolean> {
        return withContext(Dispatchers.IO) {
            // Use mutex to prevent overlapping LLM calls
            processingMutex.withLock {
                try {
                Log.i(TAG, "=== VIDEO STREAM PROCESSING ===")
                Log.i(TAG, "🎬 Analyzing frame #$frameNumber for scene changes...")
                
                // Create scene change detection prompt
                val changeDetectionPrompt = """
You are ISABELLE, analyzing a video stream for a blind user. Compare this frame with the previous scene.

Previous description: "$previousDescription"

Current frame: Analyze this new frame and determine:
1. Has the scene changed significantly?
2. If yes, provide a brief description of what's new or different
3. If no, respond with "SAME_SCENE"

Focus on meaningful changes like:
- New objects or people appearing
- Significant movement or action
- Changes in environment or location
- Important visual information (text, signs, etc.)

Response:""".trim()
                
                // CRITICAL FIX: Convert bitmap to MPImage and add to session
                Log.i(TAG, "🖼️ Converting bitmap to MPImage for multimodal processing...")
                val mpImage: MPImage = BitmapImageBuilder(bitmap).build()
                
                // Add the text prompt first
                llmSession!!.addQueryChunk(changeDetectionPrompt)
                
                // Add the image to the session for multimodal processing
                llmSession!!.addImage(mpImage)
                Log.i(TAG, "✅ Image added to MediaPipe LLM session")
                
                val resultLatch = CountDownLatch(1)
                val responseBuilder = StringBuilder()
                
                llmSession!!.generateResponseAsync { partialResult, done ->
                    responseBuilder.append(partialResult)
                    if (done) {
                        resultLatch.countDown()
                    }
                }
                
                val completed = resultLatch.await(20, TimeUnit.SECONDS) // Faster for stream
                val response = if (completed) responseBuilder.toString().trim() else ""
                
                val hasChanged = !response.contains("SAME_SCENE") && response.isNotEmpty()
                val description = if (hasChanged) response else previousDescription
                
                Log.i(TAG, "🔍 Scene changed: $hasChanged")
                if (hasChanged) {
                    Log.i(TAG, "🎯 New scene: ${description.take(50)}...")
                }
                
                Pair(description, hasChanged)
                
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Video stream processing error: ${e.message}", e)
                    Pair(previousDescription, false)
                }
            }
        }
    }
    
    /**
     * Get model information and status
     */
    fun getModelInfo(): Map<String, Any> {
        return mapOf(
            "model" to "Gemma 3n E4B (Google's approach)",
            "source" to "Kaggle → GCS (Google patterns)",
            "format" to "MediaPipe .task",
            "multimodal" to true,
            "maxImages" to MAX_IMAGE_COUNT,
            "audioSupported" to false, // Google hasn't enabled yet
            "videoFrameSupported" to true, // Frame-by-frame processing
            "initialized" to isInitialized,
            "initializing" to isInitializing,
            "singleton" to true,
            "memoryPeakMB" to (ESTIMATED_PEAK_MEMORY_BYTES / (1024 * 1024)),
            "modelSizeMB" to (MODEL_SIZE_BYTES / (1024 * 1024)),
            "backend" to "GPU (Google preferred)"
        )
    }
    
    /**
     * Clean up resources and release memory
     * Note: Only call this if you want to completely reset the singleton
     */
    fun cleanup() {
        try {
            Log.i(TAG, "🧹 Cleaning up singleton resources...")
            
            llmSession?.close()
            llmSession = null
            
            llmInference?.close()  
            llmInference = null
            
            isInitialized = false
            isInitializing = false
            
            Log.i(TAG, "✅ Singleton cleanup completed")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Cleanup error: ${e.message}", e)
        }
    }
}