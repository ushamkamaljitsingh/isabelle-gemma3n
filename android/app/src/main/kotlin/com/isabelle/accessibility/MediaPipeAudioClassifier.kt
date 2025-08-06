package com.isabelle.accessibility

import android.content.Context
import android.util.Log
// MediaPipe imports removed - using amplitude-based detection as fallback
import kotlinx.coroutines.*
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * MediaPipe-based audio classifier for environmental sound detection
 * Designed specifically for deaf/hard-of-hearing users
 */
class MediaPipeAudioClassifier(private val context: Context) {
    companion object {
        private const val TAG = "MediaPipeAudioClassifier"
        private const val SAMPLE_RATE = 16000
        private const val CLASSIFICATION_INTERVAL_MS = 500 // Faster response time
        
        // Sound categories with emoji indicators for deaf users
        private val SOUND_ALERTS = mapOf(
            "fire_alarm" to AlertInfo("🚨", "FIRE ALARM", AlertLevel.EMERGENCY),
            "smoke_alarm" to AlertInfo("🚨", "SMOKE ALARM", AlertLevel.EMERGENCY),
            "siren" to AlertInfo("🚓", "EMERGENCY SIREN", AlertLevel.EMERGENCY),
            "doorbell" to AlertInfo("🔔", "DOORBELL", AlertLevel.MEDIUM),
            "knocking" to AlertInfo("👊", "DOOR KNOCK", AlertLevel.MEDIUM),
            "baby_crying" to AlertInfo("👶", "BABY CRYING", AlertLevel.HIGH),
            "dog_barking" to AlertInfo("🐕", "DOG BARKING", AlertLevel.LOW),
            "phone_ringing" to AlertInfo("📱", "PHONE RINGING", AlertLevel.MEDIUM),
            "alarm_clock" to AlertInfo("⏰", "ALARM CLOCK", AlertLevel.MEDIUM),
            "glass_breaking" to AlertInfo("💥", "GLASS BREAKING", AlertLevel.HIGH),
            "car_horn" to AlertInfo("🚗", "CAR HORN", AlertLevel.MEDIUM),
            "speech" to AlertInfo("💬", "SOMEONE SPEAKING", AlertLevel.MEDIUM)
        )
    }
    
    // Using amplitude-based detection instead of MediaPipe AudioEmbedder
    private var isClassifying = false
    private var classificationScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    // Callbacks
    var onSoundDetected: ((SoundDetectionResult) -> Unit)? = null
    var onEmergencySound: ((SoundDetectionResult) -> Unit)? = null
    
    data class AlertInfo(
        val emoji: String,
        val description: String,
        val level: AlertLevel
    )
    
    enum class AlertLevel {
        EMERGENCY,  // Immediate attention required
        HIGH,       // Important but not emergency
        MEDIUM,     // Notable sound
        LOW         // Informational
    }
    
    data class SoundDetectionResult(
        val category: String,
        val emoji: String,
        val description: String,
        val confidence: Float,
        val level: AlertLevel,
        val timestamp: Long = System.currentTimeMillis()
    )
    
    fun initialize() {
        try {
            Log.i(TAG, "Initializing amplitude-based audio classifier for deaf users...")
            
            // Using amplitude-based pattern detection as primary method
            // This works offline and is highly efficient for accessibility
            
            Log.i(TAG, "Audio classifier initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize audio classifier", e)
        }
    }
    
    fun startClassification() {
        if (isClassifying) return
        
        isClassifying = true
        Log.i(TAG, "Starting real-time sound classification for deaf users")
    }
    
    fun classifyAudioData(audioData: ByteArray) {
        if (!isClassifying) return
        
        classificationScope.launch {
            try {
                // Perform amplitude-based pattern detection
                val detectionResult = analyzeAudioPatterns(audioData)
                
                if (detectionResult != null && detectionResult.confidence > 0.6f) {
                    Log.i(TAG, "Sound detected: ${detectionResult.emoji} ${detectionResult.description} (${detectionResult.confidence})")
                    
                    withContext(Dispatchers.Main) {
                        onSoundDetected?.invoke(detectionResult)
                        
                        if (detectionResult.level == AlertLevel.EMERGENCY) {
                            onEmergencySound?.invoke(detectionResult)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error classifying audio", e)
            }
        }
    }
    
    /**
     * Amplitude-based pattern detection for common environmental sounds
     * This works offline and is highly efficient
     */
    private fun analyzeAudioPatterns(audioData: ByteArray): SoundDetectionResult? {
        val amplitudes = extractAmplitudes(audioData)
        val frequencies = estimateFrequencies(audioData)
        
        // Pattern matching for different sounds
        return when {
            isFireAlarmPattern(amplitudes, frequencies) -> createResult("fire_alarm", 0.85f)
            isDoorbellPattern(amplitudes, frequencies) -> createResult("doorbell", 0.8f)
            isBabyCryingPattern(amplitudes, frequencies) -> createResult("baby_crying", 0.75f)
            isDogBarkingPattern(amplitudes, frequencies) -> createResult("dog_barking", 0.7f)
            isKnockingPattern(amplitudes, frequencies) -> createResult("knocking", 0.75f)
            isPhoneRingingPattern(amplitudes, frequencies) -> createResult("phone_ringing", 0.8f)
            isGlassBreakingPattern(amplitudes, frequencies) -> createResult("glass_breaking", 0.85f)
            isSpeechPattern(amplitudes, frequencies) -> createResult("speech", 0.7f)
            else -> null
        }
    }
    
    private fun createResult(category: String, confidence: Float): SoundDetectionResult {
        val alertInfo = SOUND_ALERTS[category] ?: AlertInfo("🔊", "Unknown Sound", AlertLevel.LOW)
        return SoundDetectionResult(
            category = category,
            emoji = alertInfo.emoji,
            description = alertInfo.description,
            confidence = confidence,
            level = alertInfo.level
        )
    }
    
    private fun extractAmplitudes(audioData: ByteArray): FloatArray {
        val buffer = ByteBuffer.wrap(audioData).order(ByteOrder.LITTLE_ENDIAN)
        val samples = audioData.size / 2
        val amplitudes = FloatArray(samples)
        
        for (i in 0 until samples) {
            val sample = buffer.short
            amplitudes[i] = sample.toFloat() / Short.MAX_VALUE
        }
        
        return amplitudes
    }
    
    private fun estimateFrequencies(audioData: ByteArray): FloatArray {
        // Simple zero-crossing rate for frequency estimation
        val amplitudes = extractAmplitudes(audioData)
        val frequencies = mutableListOf<Float>()
        
        var crossings = 0
        for (i in 1 until amplitudes.size) {
            if ((amplitudes[i-1] < 0 && amplitudes[i] >= 0) || 
                (amplitudes[i-1] >= 0 && amplitudes[i] < 0)) {
                crossings++
            }
        }
        
        val estimatedFreq = (crossings * SAMPLE_RATE) / (2.0f * amplitudes.size)
        frequencies.add(estimatedFreq)
        
        return frequencies.toFloatArray()
    }
    
    // Pattern detection functions
    private fun isFireAlarmPattern(amplitudes: FloatArray, frequencies: FloatArray): Boolean {
        // Fire alarms: High amplitude, includes both mid-range (1000-1500Hz) and high-range (3000-4500Hz)
        val avgAmplitude = amplitudes.average()
        val primaryFreq = frequencies.firstOrNull() ?: 0f
        
        return avgAmplitude > 0.6 && 
               ((primaryFreq in 1000f..1500f) || (primaryFreq in 3000f..4500f)) && 
               hasPeriodicPattern(amplitudes, 1.0f) // 1 second intervals
    }
    
    private fun isDoorbellPattern(amplitudes: FloatArray, frequencies: FloatArray): Boolean {
        // Doorbells: Medium amplitude, characteristic "ding-dong" pattern
        val avgAmplitude = amplitudes.average()
        return avgAmplitude in 0.4..0.7 && hasDingDongPattern(amplitudes)
    }
    
    private fun isBabyCryingPattern(amplitudes: FloatArray, frequencies: FloatArray): Boolean {
        // Baby crying: Variable amplitude, 300-600Hz fundamental
        val primaryFreq = frequencies.firstOrNull() ?: 0f
        val amplitudeVariance = calculateVariance(amplitudes)
        
        return primaryFreq in 300f..600f && amplitudeVariance > 0.3
    }
    
    private fun isDogBarkingPattern(amplitudes: FloatArray, frequencies: FloatArray): Boolean {
        // Dog barking: Sharp amplitude spikes, 200-500Hz
        val primaryFreq = frequencies.firstOrNull() ?: 0f
        val maxAmplitude = amplitudes.maxOrNull() ?: 0f
        
        return primaryFreq in 200f..500f && maxAmplitude > 0.8 && hasSharpSpikes(amplitudes)
    }
    
    private fun isKnockingPattern(amplitudes: FloatArray, frequencies: FloatArray): Boolean {
        // Knocking: Very short duration high amplitude impacts
        return hasImpactPattern(amplitudes, minAmplitude = 0.6f, maxDuration = 100)
    }
    
    private fun isPhoneRingingPattern(amplitudes: FloatArray, frequencies: FloatArray): Boolean {
        // Phone ringing: Consistent amplitude, 1-2kHz, periodic
        val avgAmplitude = amplitudes.average()
        val primaryFreq = frequencies.firstOrNull() ?: 0f
        
        return avgAmplitude in 0.5..0.8 && 
               primaryFreq in 1000f..2000f && 
               hasPeriodicPattern(amplitudes, 2.0f) // 2 second intervals
    }
    
    private fun isGlassBreakingPattern(amplitudes: FloatArray, frequencies: FloatArray): Boolean {
        // Glass breaking: Very high frequencies (>5kHz), sharp amplitude spike
        val primaryFreq = frequencies.firstOrNull() ?: 0f
        val maxAmplitude = amplitudes.maxOrNull() ?: 0f
        
        return primaryFreq > 5000f && maxAmplitude > 0.9
    }
    
    private fun isSpeechPattern(amplitudes: FloatArray, frequencies: FloatArray): Boolean {
        // Human speech: 100-400Hz fundamental, moderate amplitude variations
        val primaryFreq = frequencies.firstOrNull() ?: 0f
        val avgAmplitude = amplitudes.average()
        
        return primaryFreq in 100f..400f && avgAmplitude in 0.2..0.6
    }
    
    // Helper functions
    private fun hasPeriodicPattern(amplitudes: FloatArray, periodSeconds: Float): Boolean {
        val samplesPerPeriod = (SAMPLE_RATE * periodSeconds).toInt()
        if (amplitudes.size < samplesPerPeriod * 2) return false
        
        // Check for repeating pattern
        var matches = 0
        for (i in samplesPerPeriod until amplitudes.size) {
            if (kotlin.math.abs(amplitudes[i] - amplitudes[i - samplesPerPeriod]) < 0.1f) {
                matches++
            }
        }
        
        return matches.toFloat() / samplesPerPeriod > 0.7f
    }
    
    private fun hasDingDongPattern(amplitudes: FloatArray): Boolean {
        // Look for two distinct tones
        val peaks = findPeaks(amplitudes)
        return peaks.size >= 2 && peaks[1] - peaks[0] in 50..200 // 50-200ms apart
    }
    
    private fun hasSharpSpikes(amplitudes: FloatArray): Boolean {
        val peaks = findPeaks(amplitudes, threshold = 0.8f)
        return peaks.size >= 2
    }
    
    private fun hasImpactPattern(amplitudes: FloatArray, minAmplitude: Float, maxDuration: Int): Boolean {
        val peaks = findPeaks(amplitudes, threshold = minAmplitude)
        return peaks.isNotEmpty() && peaks.all { peakDuration(amplitudes, it) < maxDuration }
    }
    
    private fun findPeaks(amplitudes: FloatArray, threshold: Float = 0.5f): List<Int> {
        val peaks = mutableListOf<Int>()
        for (i in 1 until amplitudes.size - 1) {
            if (amplitudes[i] > threshold && 
                amplitudes[i] > amplitudes[i-1] && 
                amplitudes[i] > amplitudes[i+1]) {
                peaks.add(i)
            }
        }
        return peaks
    }
    
    private fun peakDuration(amplitudes: FloatArray, peakIndex: Int): Int {
        var duration = 1
        val threshold = amplitudes[peakIndex] * 0.5f
        
        // Check before peak
        var i = peakIndex - 1
        while (i >= 0 && amplitudes[i] > threshold) {
            duration++
            i--
        }
        
        // Check after peak
        i = peakIndex + 1
        while (i < amplitudes.size && amplitudes[i] > threshold) {
            duration++
            i++
        }
        
        return duration
    }
    
    private fun calculateVariance(values: FloatArray): Float {
        val mean = values.average().toFloat()
        return values.map { (it - mean) * (it - mean) }.average().toFloat()
    }
    
    fun stopClassification() {
        isClassifying = false
        classificationScope.cancel()
        classificationScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
        Log.i(TAG, "Stopped sound classification")
    }
    
    fun close() {
        stopClassification()
        Log.i(TAG, "Audio classifier closed")
    }
}