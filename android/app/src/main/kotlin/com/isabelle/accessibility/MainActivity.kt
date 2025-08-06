package com.isabelle.accessibility

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.app.ActivityManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.AudioFormat
import kotlinx.coroutines.Job
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.withContext

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.isabelle.accessibility/main"
    private val CAMERA_CHANNEL = "com.isabelle.accessibility/camera"
    private val DOWNLOADER_CHANNEL = "com.isabelle.accessibility/native_downloader"
    private val PROGRESS_CHANNEL = "com.isabelle.accessibility/download_progress"
    private val REALTIME_VIDEO_CHANNEL = "com.isabelle.accessibility/realtime_video"
    private val SYSTEM_INFO_CHANNEL = "com.isabelle.accessibility/system_info"
    private val SOUND_DETECTION_CHANNEL = "sound_detection"
    
    private lateinit var methodChannel: MethodChannel
    private lateinit var cameraChannel: MethodChannel
    private lateinit var downloaderChannel: MethodChannel
    private lateinit var progressEventChannel: EventChannel
    private lateinit var realtimeVideoChannel: MethodChannel
    private lateinit var systemInfoChannel: MethodChannel
    private lateinit var soundDetectionChannel: MethodChannel
    private lateinit var fastDownloader: FastNativeDownloader
    private var realtimeVideoDescriber: RealTimeVideoDescriber? = null
    private var audioClassifier: MediaPipeAudioClassifier? = null
    private var emergencyCallManager: EmergencyCallManager? = null
    
    // Background audio monitoring for sound classification
    private var audioMonitorRecord: AudioRecord? = null
    private var audioMonitoringJob: Job? = null
    private var isAudioMonitoring = false
    
    companion object {
        private const val TAG = "IsabelleMain"
        private const val PERMISSIONS_REQUEST_CODE = 1001
        
        // Required permissions for vision assistant
        private val REQUIRED_PERMISSIONS = arrayOf(
            Manifest.permission.CAMERA,
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.CALL_PHONE,
            Manifest.permission.READ_CONTACTS
        )
        
        // Audio monitoring constants
        private const val AUDIO_SAMPLE_RATE = 16000
        private const val AUDIO_CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        private val AUDIO_BUFFER_SIZE = AudioRecord.getMinBufferSize(
            AUDIO_SAMPLE_RATE,
            AUDIO_CHANNEL_CONFIG,
            AUDIO_FORMAT
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        Log.d(TAG, "Configuring Flutter engine for ISABELLE Vision Assistant")
        
        // Setup method channels
        setupMethodChannels(flutterEngine)
        
        // Request permissions
        requestNecessaryPermissions()
    }
    
    private fun setupMethodChannels(flutterEngine: FlutterEngine) {
        // Main method channel
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermissions" -> {
                    result.success(checkAllPermissions())
                }
                "requestPermissions" -> {
                    requestNecessaryPermissions()
                    result.success(true)
                }
                "getDeviceInfo" -> {
                    result.success(getDeviceInfo())
                }
                else -> {
                    Log.w(TAG, "Unknown method: ${call.method}")
                    result.notImplemented()
                }
            }
        }
        
        // Camera method channel
        cameraChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAMERA_CHANNEL)
        cameraChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkCameraPermission" -> {
                    result.success(checkCameraPermission())
                }
                "requestCameraPermission" -> {
                    requestCameraPermission()
                    result.success(true)
                }
                else -> {
                    Log.w(TAG, "Unknown camera method: ${call.method}")
                    result.notImplemented()
                }
            }
        }
        
        // Fast Native Downloader setup
        fastDownloader = FastNativeDownloader(this)
        
        // Downloader method channel
        downloaderChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOADER_CHANNEL)
        downloaderChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    Log.d(TAG, "✅ Fast downloader initialized")
                    result.success(true)
                }
                "startDownload" -> {
                    val url = call.argument<String>("url")
                    val targetPath = call.argument<String>("targetPath")
                    
                    if (url != null && targetPath != null) {
                        Log.d(TAG, "🚀 Starting fast native download...")
                        Log.d(TAG, "📥 URL: $url")
                        Log.d(TAG, "📁 Target: $targetPath")
                        
                        fastDownloader.startDownload(url, targetPath)
                        result.success(true)
                    } else {
                        result.error("MISSING_PARAMS", "URL or target path missing", null)
                    }
                }
                "cancelDownload" -> {
                    fastDownloader.cancelDownload()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Progress event channel
        progressEventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS_CHANNEL)
        progressEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                if (events != null) {
                    fastDownloader.setEventSink(events)
                    Log.d(TAG, "📊 Progress event channel listening")
                }
            }
            
            override fun onCancel(arguments: Any?) {
                Log.d(TAG, "📊 Progress event channel cancelled")
            }
        })
        
        // CRITICAL FIX: Add the missing gemma_inference channel that Flutter expects
        val gemmaInferenceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gemma_inference")
        gemmaInferenceChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeGemma3n" -> {
                    val modelPath = call.argument<String>("modelPath")
                    if (modelPath != null) {
                        Log.d(TAG, "🚀 Initializing Gemma3n with model: $modelPath")
                        CoroutineScope(Dispatchers.IO).launch {
                            try {
                                // Use the actual Gemma3nProcessor
                                val success = Gemma3nProcessor.getInstance(this@MainActivity).initialize(modelPath)
                                withContext(Dispatchers.Main) {
                                    if (success) {
                                        Log.i(TAG, "✅ Native Gemma3n initialization successful - returning true to Flutter")
                                        result.success(true)
                                    } else {
                                        Log.e(TAG, "❌ Native Gemma3n initialization failed - returning false to Flutter")
                                        result.success(false)
                                    }
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "❌ Gemma3n init exception: ${e.message}")
                                withContext(Dispatchers.Main) {
                                    result.error("GEMMA_INIT_ERROR", e.message ?: "Unknown error", null)
                                }
                            }
                        }
                    } else {
                        result.error("MISSING_PATH", "Model path missing", null)
                    }
                }
                "generateWithVision" -> {
                    val prompt = call.argument<String>("prompt")
                    val imagePath = call.argument<String>("imagePath")
                    if (prompt != null && imagePath != null) {
                        CoroutineScope(Dispatchers.IO).launch {
                            try {
                                val response = Gemma3nProcessor.getInstance(this@MainActivity)
                                    .processImageWithPrompt(imagePath, prompt)
                                withContext(Dispatchers.Main) {
                                    result.success(response)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("GENERATION_ERROR", e.message, null)
                                }
                            }
                        }
                    } else {
                        result.error("MISSING_PARAMS", "Prompt or image path missing", null)
                    }
                }
                "generateWithImageData" -> {
                    val prompt = call.argument<String>("prompt")
                    val imageData = call.argument<ByteArray>("imageData")
                    if (prompt != null && imageData != null) {
                        Log.d(TAG, "🖼️ Processing image with Gemma 3n E4B multimodal")
                        CoroutineScope(Dispatchers.IO).launch {
                            try {
                                val response = Gemma3nProcessor.getInstance(this@MainActivity)
                                    .processImageWithPrompt(imageData, prompt)
                                withContext(Dispatchers.Main) {
                                    result.success(response)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "❌ Image processing error: ${e.message}")
                                withContext(Dispatchers.Main) {
                                    result.error("GENERATION_ERROR", e.message, null)
                                }
                            }
                        }
                    } else {
                        result.error("MISSING_PARAMS", "Prompt or image data missing", null)
                    }
                }
                "shutdown" -> {
                    Gemma3nProcessor.getInstance(this@MainActivity).cleanup()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        
        // RealTime Video Describer channel
        realtimeVideoChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REALTIME_VIDEO_CHANNEL)
        realtimeVideoChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startRealtimeDescriber" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            if (realtimeVideoDescriber == null) {
                                val gemmaProcessor = Gemma3nProcessor.getInstance(this@MainActivity)
                                realtimeVideoDescriber = RealTimeVideoDescriber(
                                    this@MainActivity, 
                                    this@MainActivity, 
                                    gemmaProcessor
                                )
                                // Set up error callback to report to Flutter
                                realtimeVideoDescriber?.onError = { error ->
                                    CoroutineScope(Dispatchers.Main).launch {
                                        realtimeVideoChannel.invokeMethod("onError", error)
                                    }
                                }
                                // Set up scene description callback
                                realtimeVideoDescriber?.onSceneDescription = { description, frameNum ->
                                    CoroutineScope(Dispatchers.Main).launch {
                                        realtimeVideoChannel.invokeMethod("onSceneDescription", mapOf(
                                            "description" to description,
                                            "frameNumber" to frameNum
                                        ))
                                    }
                                }
                            }
                            
                            val success = realtimeVideoDescriber?.startVideoDescription() ?: false
                            withContext(Dispatchers.Main) {
                                result.success(mapOf("success" to success))
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("START_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "stopRealtimeDescriber" -> {
                    try {
                        realtimeVideoDescriber?.stopVideoDescription()
                        result.success(mapOf("success" to true))
                    } catch (e: Exception) {
                        result.error("STOP_ERROR", e.message, null)
                    }
                }
                "getRealtimeStatus" -> {
                    try {
                        val status = realtimeVideoDescriber?.getStatus() ?: mapOf("isDescribing" to false)
                        result.success(status)
                    } catch (e: Exception) {
                        result.error("STATUS_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // System Info channel for device capabilities
        systemInfoChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_INFO_CHANNEL)
        systemInfoChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getAvailableRAM" -> {
                    try {
                        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val memoryInfo = ActivityManager.MemoryInfo()
                        activityManager.getMemoryInfo(memoryInfo)
                        
                        // Get total RAM in MB
                        val totalRAMMB = (memoryInfo.totalMem / (1024 * 1024)).toInt()
                        Log.d(TAG, "📊 Device RAM: ${totalRAMMB}MB total")
                        result.success(totalRAMMB)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error getting RAM info: ${e.message}")
                        result.error("RAM_ERROR", "Failed to get RAM info: ${e.message}", null)
                    }
                }
                "getDeviceCapabilities" -> {
                    try {
                        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val memoryInfo = ActivityManager.MemoryInfo()
                        activityManager.getMemoryInfo(memoryInfo)
                        
                        val totalRAMMB = (memoryInfo.totalMem / (1024 * 1024)).toInt()
                        val availableRAMMB = (memoryInfo.availMem / (1024 * 1024)).toInt()
                        val lowMemory = memoryInfo.lowMemory
                        
                        val capabilities = mapOf(
                            "totalRAM" to totalRAMMB,
                            "availableRAM" to availableRAMMB,
                            "lowMemory" to lowMemory,
                            "isLargeHeap" to activityManager.largeMemoryClass,
                            "memoryClass" to activityManager.memoryClass
                        )
                        
                        Log.d(TAG, "📊 Device capabilities: $capabilities")
                        result.success(capabilities)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error getting device capabilities: ${e.message}")
                        result.error("CAPABILITIES_ERROR", "Failed to get device capabilities: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // Sound Detection channel for deaf users
        soundDetectionChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SOUND_DETECTION_CHANNEL)
        soundDetectionChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startSoundDetection" -> {
                    try {
                        if (audioClassifier == null) {
                            audioClassifier = MediaPipeAudioClassifier(this@MainActivity)
                            audioClassifier!!.initialize()
                            
                            // Initialize emergency call manager
                            if (emergencyCallManager == null) {
                                emergencyCallManager = EmergencyCallManager(this@MainActivity)
                                
                                // Set up emergency call callbacks
                                emergencyCallManager!!.onEmergencyCallStarted = { phoneNumber, description ->
                                    CoroutineScope(Dispatchers.Main).launch {
                                        val callData = mapOf(
                                            "phoneNumber" to phoneNumber,
                                            "description" to description,
                                            "status" to "calling"
                                        )
                                        soundDetectionChannel.invokeMethod("onEmergencyCall", callData)
                                    }
                                }
                                
                                emergencyCallManager!!.onEmergencyCallFailed = { phoneNumber, error ->
                                    CoroutineScope(Dispatchers.Main).launch {
                                        val errorData = mapOf(
                                            "phoneNumber" to phoneNumber,
                                            "error" to error,
                                            "status" to "failed"
                                        )
                                        soundDetectionChannel.invokeMethod("onEmergencyCallError", errorData)
                                    }
                                }
                            }
                            
                            // Set up callbacks for sound detection
                            audioClassifier!!.onSoundDetected = { soundResult ->
                                CoroutineScope(Dispatchers.Main).launch {
                                    val soundData = mapOf(
                                        "category" to soundResult.category,
                                        "emoji" to soundResult.emoji,
                                        "description" to soundResult.description,
                                        "confidence" to soundResult.confidence,
                                        "level" to soundResult.level.name,
                                        "timestamp" to soundResult.timestamp
                                    )
                                    soundDetectionChannel.invokeMethod("onSoundDetected", soundData)
                                }
                            }
                            
                            // Set up callbacks for emergency sounds - NOW WITH AUTO-CALLING!
                            audioClassifier!!.onEmergencySound = { emergencyResult ->
                                CoroutineScope(Dispatchers.Main).launch {
                                    val emergencyData = mapOf(
                                        "category" to emergencyResult.category,
                                        "emoji" to emergencyResult.emoji,
                                        "description" to emergencyResult.description,
                                        "confidence" to emergencyResult.confidence,
                                        "level" to emergencyResult.level.name,
                                        "timestamp" to emergencyResult.timestamp
                                    )
                                    soundDetectionChannel.invokeMethod("onEmergencySound", emergencyData)
                                    
                                    // 🚨 TRIGGER EMERGENCY CALLING SYSTEM! 🚨
                                    Log.w(TAG, "🚨 EMERGENCY SOUND DETECTED - TRIGGERING AUTO-CALL SYSTEM!")
                                    emergencyCallManager?.triggerEmergencyResponse(
                                        emergencyResult.category, 
                                        emergencyResult.confidence
                                    )
                                }
                            }
                        }
                        
                        audioClassifier!!.startClassification()
                        
                        // Start background audio monitoring
                        startBackgroundAudioMonitoring()
                        
                        Log.d(TAG, "✅ Sound detection started for deaf users")
                        result.success(mapOf("success" to true))
                        
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error starting sound detection: ${e.message}")
                        result.error("SOUND_DETECTION_ERROR", "Failed to start sound detection: ${e.message}", null)
                    }
                }
                
                "stopSoundDetection" -> {
                    try {
                        audioClassifier?.stopClassification()
                        stopBackgroundAudioMonitoring()
                        Log.d(TAG, "🛑 Sound detection stopped")
                        result.success(mapOf("success" to true))
                    } catch (e: Exception) {
                        result.error("STOP_ERROR", "Failed to stop sound detection: ${e.message}", null)
                    }
                }
                
                "getSoundDetectionStatus" -> {
                    try {
                        val isActive = audioClassifier != null
                        result.success(mapOf(
                            "isActive" to isActive,
                            "classifier" to if (isActive) "MediaPipe Audio Classifier" else "None"
                        ))
                    } catch (e: Exception) {
                        result.error("STATUS_ERROR", e.message, null)
                    }
                }
                
                // Development mode methods - not exposed in production UI
                "testEmergencyDetection" -> {
                    try {
                        val soundType = call.argument<String>("soundType") ?: "fire_alarm"
                        Log.i(TAG, "🧪 DEVELOPMENT MODE - Verifying emergency detection for: $soundType")
                        
                        if (emergencyCallManager == null) {
                            emergencyCallManager = EmergencyCallManager(this@MainActivity)
                        }
                        
                        emergencyCallManager!!.testEmergencyDetection(soundType)
                        result.success(mapOf("success" to true, "soundType" to soundType))
                    } catch (e: Exception) {
                        result.error("TEST_ERROR", e.message, null)
                    }
                }
                
                // Development mode simulation - not exposed in production UI  
                "simulateEmergencySound" -> {
                    try {
                        val soundType = call.argument<String>("soundType") ?: "fire_alarm"
                        val confidence = call.argument<Double>("confidence")?.toFloat() ?: 0.9f
                        
                        Log.w(TAG, "🔥 DEVELOPMENT MODE - SIMULATING EMERGENCY: $soundType (confidence: $confidence)")
                        
                        if (emergencyCallManager == null) {
                            emergencyCallManager = EmergencyCallManager(this@MainActivity)
                        }
                        
                        // Trigger emergency response simulation
                        emergencyCallManager!!.triggerEmergencyResponse(soundType, confidence)
                        
                        result.success(mapOf(
                            "success" to true, 
                            "soundType" to soundType,
                            "confidence" to confidence
                        ))
                    } catch (e: Exception) {
                        result.error("SIMULATION_ERROR", e.message, null)
                    }
                }
                
                else -> result.notImplemented()
            }
        }
    }
    
    private fun requestNecessaryPermissions() {
        val missingPermissions = REQUIRED_PERMISSIONS.filter { permission ->
            ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED
        }
        
        if (missingPermissions.isNotEmpty()) {
            Log.d(TAG, "Requesting permissions: ${missingPermissions.joinToString()}")
            ActivityCompat.requestPermissions(
                this, 
                missingPermissions.toTypedArray(), 
                PERMISSIONS_REQUEST_CODE
            )
        } else {
            Log.d(TAG, "All required permissions already granted")
        }
    }
    
    private fun checkAllPermissions(): Boolean {
        return REQUIRED_PERMISSIONS.all { permission ->
            ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
        }
    }
    
    private fun checkCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    }
    
    private fun requestCameraPermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), PERMISSIONS_REQUEST_CODE)
        }
    }
    
    private fun getDeviceInfo(): Map<String, Any> {
        return mapOf(
            "androidVersion" to Build.VERSION.RELEASE,
            "sdkVersion" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "hasCamera" to packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA),
            "hasMicrophone" to packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)
        )
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        when (requestCode) {
            PERMISSIONS_REQUEST_CODE -> {
                val granted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                Log.d(TAG, "Permissions result: ${if (granted) "All granted" else "Some denied"}")
                
                // Notify Flutter about permission status
                methodChannel.invokeMethod("onPermissionsResult", mapOf(
                    "allGranted" to granted,
                    "cameraGranted" to (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED),
                    "audioGranted" to (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)
                ))
            }
        }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "ISABELLE Vision Assistant MainActivity created")
    }
    
    override fun onResume() {
        super.onResume()
        Log.d(TAG, "MainActivity resumed")
    }
    
    override fun onPause() {
        super.onPause()
        Log.d(TAG, "MainActivity paused")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        // Cleanup real-time video describer
        realtimeVideoDescriber?.cleanup()
        // Cleanup audio classifier and monitoring
        stopBackgroundAudioMonitoring()
        audioClassifier?.close()
        // Cleanup emergency call manager
        emergencyCallManager?.cleanup()
        Log.d(TAG, "MainActivity destroyed")
    }
    
    private fun startBackgroundAudioMonitoring() {
        if (isAudioMonitoring) return
        
        try {
            // Initialize AudioRecord for continuous monitoring
            audioMonitorRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                AUDIO_SAMPLE_RATE,
                AUDIO_CHANNEL_CONFIG,
                AUDIO_FORMAT,
                kotlin.math.max(AUDIO_BUFFER_SIZE, AUDIO_SAMPLE_RATE * 2) // 1 second buffer
            )
            
            if (audioMonitorRecord!!.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "❌ Failed to initialize AudioRecord for sound monitoring")
                return
            }
            
            audioMonitorRecord!!.startRecording()
            isAudioMonitoring = true
            
            // Start background monitoring loop
            audioMonitoringJob = GlobalScope.launch(Dispatchers.IO) {
                val buffer = ByteArray(1024)
                
                while (isAudioMonitoring && audioMonitorRecord?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    try {
                        val bytesRead = audioMonitorRecord!!.read(buffer, 0, buffer.size)
                        
                        if (bytesRead > 0) {
                            // Feed audio data to classifier
                            audioClassifier?.classifyAudioData(buffer.copyOf(bytesRead))
                        } else if (bytesRead < 0) {
                            Log.w(TAG, "AudioRecord read error: $bytesRead")
                            break
                        }
                        
                        // Small delay to prevent excessive CPU usage
                        Thread.sleep(50) // 50ms = 20 times per second
                        
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in audio monitoring loop: ${e.message}")
                        break
                    }
                }
                
                Log.d(TAG, "Background audio monitoring loop ended")
            }
            
            Log.d(TAG, "✅ Background audio monitoring started")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start background audio monitoring: ${e.message}")
            isAudioMonitoring = false
        }
    }
    
    private fun stopBackgroundAudioMonitoring() {
        if (!isAudioMonitoring) return
        
        isAudioMonitoring = false
        
        try {
            audioMonitoringJob?.cancel()
            audioMonitoringJob = null
            
            audioMonitorRecord?.stop()
            audioMonitorRecord?.release()
            audioMonitorRecord = null
            
            Log.d(TAG, "✅ Background audio monitoring stopped")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error stopping audio monitoring: ${e.message}")
        }
    }
}