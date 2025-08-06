package com.isabelle.accessibility

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.widget.Toast
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*

/**
 * Multi-sensory alert system for deaf/hard-of-hearing users
 * Combines haptic feedback, visual alerts, and screen flash indicators
 */
class MultiSensoryAlertSystem(private val context: Context) {
    companion object {
        private const val TAG = "MultiSensoryAlertSystem"
        
        // Vibration patterns for different sound types
        private val VIBRATION_PATTERNS = mapOf(
            "fire_alarm" to longArrayOf(0, 1000, 500, 1000, 500, 1000), // Urgent repeated
            "doorbell" to longArrayOf(0, 200, 100, 200, 100, 200), // Ding-dong pattern
            "phone_ringing" to longArrayOf(0, 300, 200, 300, 200, 300, 200, 300), // Ring pattern
            "baby_crying" to longArrayOf(0, 150, 50, 150, 50, 150, 50, 150), // Rapid pattern
            "emergency" to longArrayOf(0, 500, 100, 500, 100, 500, 100, 500), // SOS pattern
            "knock" to longArrayOf(0, 100, 50, 100, 50, 100), // Knock pattern
            "glass_breaking" to longArrayOf(0, 1500), // Single long vibration
            "speech" to longArrayOf(0, 200, 100, 200), // Gentle notification
            "general" to longArrayOf(0, 300, 200, 300) // Default pattern
        )
        
        // Color coding for different alert types
        private val ALERT_COLORS = mapOf(
            "emergency" to Color.RED,
            "fire_alarm" to Color.RED,
            "smoke_alarm" to Color.RED,
            "siren" to Color.RED,
            "glass_breaking" to Color.YELLOW,
            "baby_crying" to Color.MAGENTA,
            "doorbell" to Color.BLUE,
            "phone_ringing" to Color.GREEN,
            "knock" to Color.CYAN,
            "speech" to Color.WHITE,
            "general" to Color.GRAY
        )
    }
    
    private val vibrator: Vibrator by lazy {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }
    
    private var alertScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var currentFlashJob: Job? = null
    
    /**
     * Trigger comprehensive alert for deaf users
     */
    fun triggerAlert(soundDetection: MediaPipeAudioClassifier.SoundDetectionResult) {
        Log.i(TAG, "Triggering multi-sensory alert for: ${soundDetection.description}")
        
        // Trigger all alert types simultaneously
        triggerHapticFeedback(soundDetection.category, soundDetection.level)
        triggerVisualAlert(soundDetection)
        triggerScreenFlash(soundDetection.category, soundDetection.level)
        showToastAlert(soundDetection)
    }
    
    /**
     * Haptic feedback patterns for different sounds
     */
    private fun triggerHapticFeedback(category: String, level: MediaPipeAudioClassifier.AlertLevel) {
        if (!vibrator.hasVibrator()) {
            Log.w(TAG, "Device does not have vibrator")
            return
        }
        
        val pattern = VIBRATION_PATTERNS[category] ?: VIBRATION_PATTERNS["general"]!!
        
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val effect = when (level) {
                    MediaPipeAudioClassifier.AlertLevel.EMERGENCY -> {
                        VibrationEffect.createWaveform(pattern, 0) // Repeat
                    }
                    MediaPipeAudioClassifier.AlertLevel.HIGH -> {
                        VibrationEffect.createWaveform(pattern, -1) // No repeat
                    }
                    MediaPipeAudioClassifier.AlertLevel.MEDIUM -> {
                        VibrationEffect.createWaveform(pattern, -1)
                    }
                    MediaPipeAudioClassifier.AlertLevel.LOW -> {
                        VibrationEffect.createOneShot(300, VibrationEffect.DEFAULT_AMPLITUDE)
                    }
                }
                vibrator.vibrate(effect)
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, if (level == MediaPipeAudioClassifier.AlertLevel.EMERGENCY) 0 else -1)
            }
            
            Log.d(TAG, "Haptic feedback triggered for $category")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to trigger haptic feedback", e)
        }
    }
    
    /**
     * Visual alert with text and emoji
     */
    private fun triggerVisualAlert(soundDetection: MediaPipeAudioClassifier.SoundDetectionResult) {
        alertScope.launch {
            try {
                val alertMessage = "${soundDetection.emoji} ${soundDetection.description}"
                
                // Show different types of visual alerts based on urgency
                when (soundDetection.level) {
                    MediaPipeAudioClassifier.AlertLevel.EMERGENCY -> {
                        showEmergencyDialog(alertMessage)
                    }
                    MediaPipeAudioClassifier.AlertLevel.HIGH -> {
                        showHighPriorityToast(alertMessage)
                    }
                    MediaPipeAudioClassifier.AlertLevel.MEDIUM -> {
                        showMediumPriorityToast(alertMessage)
                    }
                    MediaPipeAudioClassifier.AlertLevel.LOW -> {
                        showLowPriorityToast(alertMessage)
                    }
                }
                
                Log.d(TAG, "Visual alert triggered: $alertMessage")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to trigger visual alert", e)
            }
        }
    }
    
    /**
     * Flash entire screen with color coding
     */
    private fun triggerScreenFlash(category: String, level: MediaPipeAudioClassifier.AlertLevel) {
        if (context !is Activity) {
            Log.w(TAG, "Context is not an Activity, cannot flash screen")
            return
        }
        
        val color = ALERT_COLORS[category] ?: ALERT_COLORS["general"]!!
        val duration = when (level) {
            MediaPipeAudioClassifier.AlertLevel.EMERGENCY -> 2000L // 2 seconds
            MediaPipeAudioClassifier.AlertLevel.HIGH -> 1500L
            MediaPipeAudioClassifier.AlertLevel.MEDIUM -> 1000L
            MediaPipeAudioClassifier.AlertLevel.LOW -> 500L
        }
        
        currentFlashJob?.cancel()
        currentFlashJob = alertScope.launch {
            try {
                flashScreen(context, color, duration)
                Log.d(TAG, "Screen flash triggered for $category")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to trigger screen flash", e)
            }
        }
    }
    
    /**
     * Show toast notification
     */
    private fun showToastAlert(soundDetection: MediaPipeAudioClassifier.SoundDetectionResult) {
        val message = "${soundDetection.emoji} ${soundDetection.description}"
        val duration = when (soundDetection.level) {
            MediaPipeAudioClassifier.AlertLevel.EMERGENCY,
            MediaPipeAudioClassifier.AlertLevel.HIGH -> Toast.LENGTH_LONG
            else -> Toast.LENGTH_SHORT
        }
        
        Toast.makeText(context, message, duration).show()
    }
    
    private fun showEmergencyDialog(message: String) {
        // For emergency alerts, use system alert window
        Toast.makeText(context, "🚨 EMERGENCY: $message", Toast.LENGTH_LONG).show()
    }
    
    private fun showHighPriorityToast(message: String) {
        Toast.makeText(context, "⚠️ $message", Toast.LENGTH_LONG).show()
    }
    
    private fun showMediumPriorityToast(message: String) {
        Toast.makeText(context, "ℹ️ $message", Toast.LENGTH_SHORT).show()
    }
    
    private fun showLowPriorityToast(message: String) {
        Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
    }
    
    /**
     * Flash the entire screen with a specific color
     */
    private suspend fun flashScreen(activity: Activity, color: Int, durationMs: Long) {
        withContext(Dispatchers.Main) {
            val window = activity.window
            val decorView = window.decorView
            
            // Save original color
            val originalColor = decorView.solidColor
            
            // Create flash overlay
            val flashOverlay = View(activity).apply {
                setBackgroundColor(color)
                alpha = 0.8f
            }
            
            // Add overlay to activity
            val contentView = activity.findViewById<View>(android.R.id.content)
            if (contentView is android.view.ViewGroup) {
                contentView.addView(flashOverlay, android.view.ViewGroup.LayoutParams(
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT
                ))
            }
            
            // Flash effect
            delay(durationMs)
            
            // Remove overlay
            if (contentView is android.view.ViewGroup) {
                contentView.removeView(flashOverlay)
            }
        }
    }
    
    /**
     * Test all alert types for deaf users
     */
    fun testAllAlerts() {
        Log.i(TAG, "Testing all alert types for deaf users")
        
        val testSound = MediaPipeAudioClassifier.SoundDetectionResult(
            category = "test",
            emoji = "🔊",
            description = "TEST ALERT",
            confidence = 1.0f,
            level = MediaPipeAudioClassifier.AlertLevel.MEDIUM
        )
        
        triggerAlert(testSound)
    }
    
    /**
     * Stop all ongoing alerts
     */
    fun stopAllAlerts() {
        Log.i(TAG, "Stopping all alerts")
        
        // Stop vibration
        vibrator.cancel()
        
        // Cancel flash effects
        currentFlashJob?.cancel()
        
        // Cancel all pending alerts
        alertScope.cancel()
        alertScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    }
    
    /**
     * Configure alert sensitivity for deaf users
     */
    fun configureAlertSensitivity(
        enableHaptic: Boolean = true,
        enableVisual: Boolean = true,
        enableScreenFlash: Boolean = true,
        vibrationIntensity: Float = 1.0f
    ) {
        Log.i(TAG, "Configuring alert sensitivity: haptic=$enableHaptic, visual=$enableVisual, flash=$enableScreenFlash")
        
        // Store configuration for future use
        // This would typically be saved to SharedPreferences
    }
    
    fun close() {
        Log.i(TAG, "Closing multi-sensory alert system")
        stopAllAlerts()
        alertScope.cancel()
    }
}