package com.isabelle.accessibility

import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * Throttles vibration calls to prevent spam and improve battery life
 */
object VibrationThrottler {
    private const val TAG = "VibrationThrottler" 
    private const val MIN_VIBRATION_INTERVAL_MS = 2000L // Minimum 2 seconds between vibrations
    
    private var lastVibrationTime = 0L
    
    /**
     * Perform throttled vibration
     */
    fun vibrateThrottled(context: Context, pattern: LongArray? = null, duration: Long = 300L) {
        val currentTime = SystemClock.elapsedRealtime()
        
        // Check if enough time has passed since last vibration
        if (currentTime - lastVibrationTime < MIN_VIBRATION_INTERVAL_MS) {
            Log.d(TAG, "⏱️ Vibration throttled - too soon since last vibration")
            return
        }
        
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            
            if (!vibrator.hasVibrator()) {
                Log.w(TAG, "⚠️ Device does not have vibrator")
                return
            }
            
            when {
                pattern != null -> {
                    // Use pattern vibration
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val effect = VibrationEffect.createWaveform(pattern, -1)
                        vibrator.vibrate(effect)
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator.vibrate(pattern, -1)
                    }
                }
                else -> {
                    // Simple vibration
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val effect = VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE)
                        vibrator.vibrate(effect)
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator.vibrate(duration)
                    }
                }
            }
            
            lastVibrationTime = currentTime
            Log.d(TAG, "📳 Vibration executed (throttled)")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to vibrate", e)
        }
    }
    
    /**
     * Emergency vibration (bypasses throttling for critical alerts)
     */
    fun vibrateEmergency(context: Context, pattern: LongArray) {
        Log.w(TAG, "🚨 Emergency vibration - bypassing throttle")
        
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            
            if (vibrator.hasVibrator()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val effect = VibrationEffect.createWaveform(pattern, -1)
                    vibrator.vibrate(effect)
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(pattern, -1)
                }
                lastVibrationTime = SystemClock.elapsedRealtime()
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed emergency vibration", e)
        }
    }
}