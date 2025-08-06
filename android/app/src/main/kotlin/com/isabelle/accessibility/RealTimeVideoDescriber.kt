package com.isabelle.accessibility

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.util.Log
import android.util.Size
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.*
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.*
import java.util.concurrent.Executors

/**
 * Real-time Video Description Service for ISABELLE
 * 
 * Provides continuous scene description using Gemma 3n E4B model for blind users.
 * Captures frames from camera and processes them through Gemma for accessibility.
 */
class RealTimeVideoDescriber(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val gemma3nProcessor: Gemma3nProcessor
) {
    companion object {
        private const val TAG = "RealTimeVideoDescriber"
        
        // Video processing configuration
        private const val FRAME_ANALYSIS_INTERVAL_MS = 3000L // Analyze every 3 seconds
        private const val SCENE_CHANGE_ANALYSIS_INTERVAL_MS = 1500L // Check changes every 1.5s
        private const val MIN_PROCESSING_INTERVAL_MS = 500L // Min gap between processing
        
        // Camera configuration
        private const val TARGET_RESOLUTION_WIDTH = 640
        private const val TARGET_RESOLUTION_HEIGHT = 480
        private const val IMAGE_CAPTURE_RESOLUTION_WIDTH = 224
        private const val IMAGE_CAPTURE_RESOLUTION_HEIGHT = 224
    }

    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var camera: Camera? = null
    
    private var isDescribing = false
    private var frameNumber = 0
    private var lastProcessingTime = 0L
    private var lastDescription = ""
    
    private val processingScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private val analysisExecutor = Executors.newSingleThreadExecutor()
    
    // Text-to-speech for accessibility
    private var textToSpeech: TextToSpeech? = null
    private var ttsInitialized = false
    
    // Callbacks for video description events
    var onSceneDescription: ((String, Int) -> Unit)? = null
    var onSceneChange: ((String, Boolean) -> Unit)? = null
    var onError: ((String) -> Unit)? = null

    init {
        initializeTTS()
    }
    
    /**
     * Initialize Text-to-Speech for accessibility output
     */
    private fun initializeTTS() {
        textToSpeech = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                textToSpeech?.language = Locale.US
                textToSpeech?.setSpeechRate(1.0f)
                ttsInitialized = true
                Log.i(TAG, "✅ TTS initialized for video descriptions")
            } else {
                Log.e(TAG, "❌ TTS initialization failed")
            }
        }
    }

    /**
     * Start real-time video description for blind users
     */
    suspend fun startVideoDescription(): Boolean {
        return withContext(Dispatchers.Main) {
            try {
                if (isDescribing) {
                    Log.w(TAG, "⚠️ Video description already running")
                    return@withContext true
                }
                
                Log.i(TAG, "=== STARTING REAL-TIME VIDEO DESCRIPTION ===")
                Log.i(TAG, "🎥 Initializing camera for accessibility...")
                
                val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
                cameraProvider = cameraProviderFuture.get()
                
                setupCameraAndAnalysis()
                
                isDescribing = true
                frameNumber = 0
                lastDescription = ""
                
                Log.i(TAG, "✅ Real-time video description started")
                Log.i(TAG, "🎯 Ready to help blind users understand their surroundings")
                
                // Initial announcement
                speakDescription("Video description started. I'll describe what I see in your surroundings.")
                
                true
                
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to start video description: ${e.message}", e)
                onError?.invoke("Failed to start video description: ${e.message}")
                false
            }
        }
    }

    /**
     * Setup camera and image analysis for real-time processing
     */
    private fun setupCameraAndAnalysis() {
        try {
            // Unbind any existing use cases
            cameraProvider?.unbindAll()
            
            // Configure image analysis
            imageAnalysis = ImageAnalysis.Builder()
                .setTargetResolution(Size(TARGET_RESOLUTION_WIDTH, TARGET_RESOLUTION_HEIGHT))
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
            
            // Set up frame analyzer
            imageAnalysis?.setAnalyzer(analysisExecutor) { imageProxy ->
                processVideoFrame(imageProxy)
            }
            
            // Select back camera
            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
            
            // Bind to lifecycle
            camera = cameraProvider?.bindToLifecycle(
                lifecycleOwner,
                cameraSelector,
                imageAnalysis
            )
            
            Log.i(TAG, "📷 Camera configured for real-time analysis")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Camera setup failed: ${e.message}", e)
            onError?.invoke("Camera setup failed: ${e.message}")
        }
    }

    /**
     * Process individual video frame through Gemma 3n
     */
    private fun processVideoFrame(imageProxy: ImageProxy) {
        val currentTime = System.currentTimeMillis()
        
        // Rate limiting to prevent overwhelming the processor
        if (currentTime - lastProcessingTime < MIN_PROCESSING_INTERVAL_MS) {
            imageProxy.close()
            return
        }
        
        try {
            frameNumber++
            
            // Convert ImageProxy to Bitmap
            val bitmap = imageProxyToBitmap(imageProxy) ?: run {
                Log.w(TAG, "⚠️ Failed to convert frame to bitmap")
                imageProxy.close()
                return
            }
            
            // Resize for efficient processing
            val resizedBitmap = Bitmap.createScaledBitmap(
                bitmap, 
                IMAGE_CAPTURE_RESOLUTION_WIDTH, 
                IMAGE_CAPTURE_RESOLUTION_HEIGHT, 
                true
            )
            
            bitmap.recycle()
            
            // Decide whether to do full analysis or scene change detection
            val shouldAnalyzeScene = (currentTime - lastProcessingTime) > FRAME_ANALYSIS_INTERVAL_MS
            
            if (shouldAnalyzeScene) {
                // Full scene analysis
                processingScope.launch {
                    processFullSceneAnalysis(resizedBitmap, frameNumber)
                }
            } else if (lastDescription.isNotEmpty() && 
                       (currentTime - lastProcessingTime) > SCENE_CHANGE_ANALYSIS_INTERVAL_MS) {
                // Scene change detection
                processingScope.launch {
                    processSceneChangeDetection(resizedBitmap, frameNumber)
                }
            }
            
            lastProcessingTime = currentTime
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Frame processing error: ${e.message}", e)
        } finally {
            imageProxy.close()
        }
    }

    /**
     * Process full scene analysis using Gemma 3n
     */
    private suspend fun processFullSceneAnalysis(bitmap: Bitmap, frameNum: Int) {
        try {
            Log.i(TAG, "🎬 Performing full scene analysis for frame #$frameNum")
            
            val description = gemma3nProcessor.processVideoFrame(bitmap, frameNum)
            
            if (description.isNotEmpty() && description != lastDescription) {
                Log.i(TAG, "🎯 New scene description: ${description.take(50)}...")
                
                lastDescription = description
                
                // Notify callbacks
                onSceneDescription?.invoke(description, frameNum)
                
                // Speak description for accessibility
                speakDescription(description)
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Full scene analysis error: ${e.message}", e)
        } finally {
            bitmap.recycle()
        }
    }

    /**
     * Process scene change detection using Gemma 3n
     */
    private suspend fun processSceneChangeDetection(bitmap: Bitmap, frameNum: Int) {
        try {
            Log.i(TAG, "🔍 Checking scene changes for frame #$frameNum")
            
            val (newDescription, hasChanged) = gemma3nProcessor.processVideoStream(
                bitmap, frameNum, lastDescription
            )
            
            if (hasChanged && newDescription != lastDescription) {
                Log.i(TAG, "🎯 Scene changed: ${newDescription.take(50)}...")
                
                lastDescription = newDescription
                
                // Notify callbacks
                onSceneChange?.invoke(newDescription, hasChanged)
                
                // Speak only significant changes
                if (newDescription.length > 10) { // Filter out very short responses
                    speakDescription("Scene changed: $newDescription")
                }
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Scene change detection error: ${e.message}", e)
        } finally {
            bitmap.recycle()
        }
    }

    /**
     * Convert ImageProxy to Bitmap for processing
     * Fixed to handle different image formats properly
     */
    private fun imageProxyToBitmap(imageProxy: ImageProxy): Bitmap? {
        return try {
            val image = imageProxy.image ?: return null
            
            when (image.format) {
                ImageFormat.JPEG -> {
                    // JPEG format - direct conversion
                    val buffer: ByteBuffer = imageProxy.planes[0].buffer
                    val bytes = ByteArray(buffer.remaining())
                    buffer.get(bytes)
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                }
                
                ImageFormat.YUV_420_888 -> {
                    // YUV format - convert to NV21 then to bitmap
                    convertYuv420ToBitmap(image)
                }
                
                else -> {
                    Log.w(TAG, "⚠️ Unsupported image format: ${image.format}")
                    null
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to convert ImageProxy to Bitmap: ${e.message}")
            null
        }
    }
    
    /**
     * Convert YUV_420_888 format to Bitmap
     * Proper handling to avoid 'unimplemented' decoder errors
     */
    private fun convertYuv420ToBitmap(image: android.media.Image): Bitmap? {
        return try {
            val planes = image.planes
            val yPlane: android.media.Image.Plane = planes[0]
            val uPlane: android.media.Image.Plane = planes[1]  
            val vPlane: android.media.Image.Plane = planes[2]
            
            val yBuffer = yPlane.buffer
            val uBuffer = uPlane.buffer
            val vBuffer = vPlane.buffer
            
            val ySize = yBuffer.remaining()
            val uSize = uBuffer.remaining() 
            val vSize = vBuffer.remaining()
            
            // Create NV21 byte array
            val nv21 = ByteArray(ySize + uSize + vSize)
            
            // Copy Y plane
            yBuffer.get(nv21, 0, ySize)
            
            // Interleave U and V for NV21 format
            val uvPixelStride = uPlane.pixelStride
            if (uvPixelStride == 1) {
                // Packed UV
                uBuffer.get(nv21, ySize, uSize)
                vBuffer.get(nv21, ySize + uSize, vSize)
            } else {
                // Interleaved UV
                val uvBuffer = ByteArray(2 * uSize)
                uBuffer.get(uvBuffer, 0, uSize)
                vBuffer.get(uvBuffer, 1, vSize)
                
                var uvIndex = 0
                for (i in 0 until uSize) {
                    nv21[ySize + uvIndex] = uvBuffer[i * 2 + 1] // V
                    nv21[ySize + uvIndex + 1] = uvBuffer[i * 2] // U
                    uvIndex += 2
                }
            }
            
            // Convert to Bitmap using YuvImage
            val yuvImage = YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
            val out = ByteArrayOutputStream()
            yuvImage.compressToJpeg(Rect(0, 0, image.width, image.height), 85, out)
            val imageBytes = out.toByteArray()
            
            BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ YUV to Bitmap conversion failed: ${e.message}")
            null
        }
    }

    /**
     * Speak description using TTS for accessibility
     */
    private fun speakDescription(description: String) {
        if (ttsInitialized && textToSpeech != null) {
            Handler(Looper.getMainLooper()).post {
                textToSpeech?.speak(
                    description,
                    TextToSpeech.QUEUE_FLUSH,
                    null,
                    "video_desc_${System.currentTimeMillis()}"
                )
            }
            Log.i(TAG, "🔊 Speaking: ${description.take(30)}...")
        } else {
            Log.w(TAG, "⚠️ TTS not available for description")
        }
    }

    /**
     * Stop real-time video description
     */
    fun stopVideoDescription() {
        try {
            Log.i(TAG, "🛑 Stopping real-time video description...")
            
            isDescribing = false
            
            // Unbind camera
            cameraProvider?.unbindAll()
            camera = null
            imageAnalysis = null
            
            // Cancel processing
            processingScope.cancel()
            
            // Final announcement
            speakDescription("Video description stopped.")
            
            Log.i(TAG, "✅ Video description stopped")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error stopping video description: ${e.message}", e)
        }
    }

    /**
     * Get current video description status
     */
    fun getStatus(): Map<String, Any> {
        return mapOf(
            "isDescribing" to isDescribing,
            "frameNumber" to frameNumber,
            "lastDescription" to lastDescription,
            "ttsReady" to ttsInitialized,
            "cameraActive" to (camera != null)
        )
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        try {
            Log.i(TAG, "🧹 Cleaning up video describer...")
            
            stopVideoDescription()
            
            textToSpeech?.stop()
            textToSpeech?.shutdown()
            textToSpeech = null
            
            analysisExecutor.shutdown()
            
            Log.i(TAG, "✅ Video describer cleanup completed")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Cleanup error: ${e.message}", e)
        }
    }
}