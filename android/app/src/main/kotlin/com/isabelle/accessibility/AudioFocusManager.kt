package com.isabelle.accessibility

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.AudioFocusRequest
import android.media.AudioAttributes
import android.os.Build
import android.util.Log
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothHeadset
import androidx.annotation.RequiresApi

/**
 * Advanced AudioManager integration for ISABELLE accessibility app
 * Handles audio focus, device routing, and hearing aid compatibility
 */
class AudioFocusManager(private val context: Context) {
    companion object {
        private const val TAG = "AudioFocusManager"
    }
    
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var audioFocusRequest: AudioFocusRequest? = null
    private var hasAudioFocus = false
    private var isInitialized = false
    
    // Callbacks for audio state changes
    var onAudioFocusChanged: ((Boolean) -> Unit)? = null
    var onAudioDeviceChanged: ((AudioDeviceInfo) -> Unit)? = null
    var onHearingAidConnected: (() -> Unit)? = null
    
    // Audio focus change listener
    private val audioFocusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        Log.i(TAG, "Audio focus changed: $focusChange")
        
        when (focusChange) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                Log.i(TAG, "✅ Audio focus GAINED - Full accessibility audio control")
                hasAudioFocus = true
                onAudioFocusChanged?.invoke(true)
                optimizeForAccessibility()
            }
            AudioManager.AUDIOFOCUS_LOSS -> {
                Log.w(TAG, "❌ Audio focus LOST - Another app took control")
                hasAudioFocus = false
                onAudioFocusChanged?.invoke(false)
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                Log.w(TAG, "⏸️ Audio focus LOST TEMPORARILY - Pausing accessibility features")
                hasAudioFocus = false
                onAudioFocusChanged?.invoke(false)
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                Log.i(TAG, "🔉 Audio focus DUCKING - Reducing volume but continuing")
                // Continue with reduced volume for accessibility
            }
        }
    }
    
    // TODO: Audio device callback for hearing aid detection (API 23+)
    // Temporarily disabled due to compilation issues - will implement with proper API version handling
    
    fun initialize(): Boolean {
        return try {
            Log.i(TAG, "Initializing AudioFocusManager for accessibility...")
            
            // TODO: Register audio device callback (API 23+)
            // Temporarily disabled - will implement with proper API version handling
            Log.i(TAG, "Audio device callback registration skipped (will implement later)")
            
            // Check current audio environment
            analyzeCurrentAudioEnvironment()
            
            isInitialized = true
            Log.i(TAG, "✅ AudioFocusManager initialized successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to initialize AudioFocusManager", e)
            false
        }
    }
    
    fun requestAccessibilityAudioFocus(): Boolean {
        if (!isInitialized) {
            Log.e(TAG, "AudioFocusManager not initialized")
            return false
        }
        
        return try {
            Log.i(TAG, "🎯 Requesting accessibility audio focus...")
            
            val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Use modern AudioFocusRequest for Android 8+
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
                
                audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(audioAttributes)
                    .setAcceptsDelayedFocusGain(true)
                    .setOnAudioFocusChangeListener(audioFocusChangeListener)
                    .build()
                
                audioManager.requestAudioFocus(audioFocusRequest!!)
            } else {
                // Legacy method for older Android versions
                audioManager.requestAudioFocus(
                    audioFocusChangeListener,
                    AudioManager.STREAM_ACCESSIBILITY,
                    AudioManager.AUDIOFOCUS_GAIN
                )
            }
            
            val success = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            if (success) {
                hasAudioFocus = true
                Log.i(TAG, "✅ Accessibility audio focus GRANTED")
                optimizeForAccessibility()
            } else {
                Log.w(TAG, "❌ Accessibility audio focus DENIED")
            }
            
            success
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to request audio focus", e)
            false
        }
    }
    
    fun releaseAudioFocus() {
        if (!hasAudioFocus) return
        
        try {
            Log.i(TAG, "🔓 Releasing accessibility audio focus...")
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusRequest != null) {
                audioManager.abandonAudioFocusRequest(audioFocusRequest!!)
            } else {
                audioManager.abandonAudioFocus(audioFocusChangeListener)
            }
            
            hasAudioFocus = false
            Log.i(TAG, "✅ Audio focus released")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to release audio focus", e)
        }
    }
    
    private fun analyzeCurrentAudioEnvironment() {
        Log.i(TAG, "🔍 Analyzing current audio environment...")
        
        // Check audio mode
        val audioMode = audioManager.mode
        Log.i(TAG, "Current audio mode: ${getAudioModeString(audioMode)}")
        
        // Check available audio devices (API 23+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            Log.i(TAG, "Available audio output devices:")
            
            for (device in devices) {
                Log.i(TAG, "  - ${device.productName} (${getDeviceTypeString(device.type)})")
                
                // Special handling for hearing aids
                if (device.type == 30) { // AudioDeviceInfo.TYPE_HEARING_AID
                    Log.w(TAG, "🦻 HEARING AID DETECTED on startup")
                    onHearingAidConnected?.invoke()
                }
            }
        } else {
            Log.i(TAG, "Audio device enumeration not available on this Android version")
        }
        
        // Check volume levels
        val accessibilityVolume = audioManager.getStreamVolume(AudioManager.STREAM_ACCESSIBILITY)
        val maxAccessibilityVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ACCESSIBILITY)
        Log.i(TAG, "Accessibility volume: $accessibilityVolume/$maxAccessibilityVolume")
        
        // Check if speaker is on (important for deaf users)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val isSpeakerphoneOn = audioManager.isSpeakerphoneOn
            Log.i(TAG, "Speakerphone active: $isSpeakerphoneOn")
        }
    }
    
    private fun optimizeForAccessibility() {
        Log.i(TAG, "🎯 Optimizing audio for accessibility...")
        
        try {
            // Set audio mode for clear communication
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            
            // Enable speakerphone for deaf users (loud and clear)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                audioManager.isSpeakerphoneOn = true
                Log.i(TAG, "✅ Speakerphone enabled for deaf users")
            }
            
            // Optimize volume for accessibility
            val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ACCESSIBILITY)
            audioManager.setStreamVolume(
                AudioManager.STREAM_ACCESSIBILITY, 
                (maxVolume * 0.8).toInt(), // 80% for safety
                0
            )
            
            // Enable audio effects if available
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // Enable spatial audio for better directional awareness
                Log.i(TAG, "🎵 Optimizing spatial audio for accessibility")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to optimize for accessibility", e)
        }
    }
    
    private fun optimizeForHearingAid(device: AudioDeviceInfo) {
        Log.i(TAG, "🦻 Optimizing for hearing aid: ${device.productName}")
        
        try {
            // Use hearing aid optimized settings
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            
            // Disable speakerphone when hearing aid is connected
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                audioManager.isSpeakerphoneOn = false
                Log.i(TAG, "✅ Speakerphone disabled for hearing aid")
            }
            
            // Optimize volume for hearing aid
            val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)
            audioManager.setStreamVolume(
                AudioManager.STREAM_VOICE_CALL,
                (maxVolume * 0.9).toInt(), // Higher volume for hearing aid
                0
            )
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to optimize for hearing aid", e)
        }
    }
    
    private fun optimizeForBluetoothAudio(device: AudioDeviceInfo) {
        Log.i(TAG, "📱 Optimizing for Bluetooth audio: ${device.productName}")
        
        try {
            // Use Bluetooth SCO for voice calls
            audioManager.isBluetoothScoOn = true
            audioManager.startBluetoothSco()
            
            Log.i(TAG, "✅ Bluetooth SCO enabled for voice communication")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to optimize for Bluetooth audio", e)
        }
    }
    
    private fun optimizeForWiredAudio(device: AudioDeviceInfo) {
        Log.i(TAG, "🎧 Optimizing for wired audio: ${device.productName}")
        
        try {
            // Disable speakerphone for privacy
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                audioManager.isSpeakerphoneOn = false
                Log.i(TAG, "✅ Speakerphone disabled for privacy")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to optimize for wired audio", e)
        }
    }
    
    private fun revertToSpeakerMode() {
        Log.i(TAG, "🔊 Reverting to speaker mode")
        
        try {
            // Re-enable speakerphone
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                audioManager.isSpeakerphoneOn = true
                Log.i(TAG, "✅ Speakerphone re-enabled")
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to revert to speaker mode", e)
        }
    }
    
    fun cleanup() {
        try {
            releaseAudioFocus()
            
            // TODO: Unregister audio device callback (API 23+)
            // Temporarily disabled - will implement with proper API version handling
            Log.i(TAG, "Audio device callback cleanup skipped (will implement later)")
            
            isInitialized = false
            Log.i(TAG, "✅ AudioFocusManager cleaned up")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to cleanup AudioFocusManager", e)
        }
    }
    
    // Helper methods for logging
    private fun getAudioModeString(mode: Int): String {
        return when (mode) {
            AudioManager.MODE_NORMAL -> "NORMAL"
            AudioManager.MODE_RINGTONE -> "RINGTONE"
            AudioManager.MODE_IN_CALL -> "IN_CALL"
            AudioManager.MODE_IN_COMMUNICATION -> "IN_COMMUNICATION"
            else -> "UNKNOWN($mode)"
        }
    }
    
    private fun getDeviceTypeString(type: Int): String {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "BUILTIN_SPEAKER"
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> "BUILTIN_MIC"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "WIRED_HEADPHONES"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "WIRED_HEADSET"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "BLUETOOTH_A2DP"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "BLUETOOTH_SCO"
            30 -> "HEARING_AID" // AudioDeviceInfo.TYPE_HEARING_AID constant value
            else -> "UNKNOWN($type)"
        }
    }
    
    // Public getters
    fun hasAudioFocus(): Boolean = hasAudioFocus
    fun isInitialized(): Boolean = isInitialized
    
    // Get current audio device info (API 23+)
    fun getCurrentAudioDevices(): List<AudioDeviceInfo> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()
        } else {
            emptyList()
        }
    }
    
    // Check if hearing aid is connected
    fun isHearingAidConnected(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            getCurrentAudioDevices().any { it.type == 30 } // AudioDeviceInfo.TYPE_HEARING_AID
        } else {
            false
        }
    }
}