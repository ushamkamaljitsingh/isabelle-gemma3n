package com.isabelle.accessibility

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import kotlinx.coroutines.*
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Gemma 3n Speech Recognition for ISABELLE
 * 
 * This service implements offline speech-to-text using Gemma 3n model inference
 * instead of Android's online SpeechRecognizer. Critical for accessibility.
 */
class Gemma3nSpeechService(
    private val context: Context,
    private val gemma3nProcessor: Gemma3nProcessor
) {
    companion object {
        private const val TAG = "Gemma3nSpeechService"
        
        // Audio configuration optimized for speech
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        
        // CRITICAL FIX: Calculate proper buffer size
        private val MIN_BUFFER = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT
        )
        private val BUFFER_SIZE = kotlin.math.max(MIN_BUFFER, SAMPLE_RATE * 2) // At least 1 second of audio
        
        // Speech detection parameters
        private const val VOICE_ACTIVITY_THRESHOLD = 0.02f
        private const val SILENCE_TIMEOUT_MS = 1500L
        private const val MIN_SPEECH_LENGTH_MS = 500L
        private const val MAX_RECORDING_TIME_MS = 30000L // 30 seconds max (Google's recommendation)
        
        // Audio analysis
        private const val FRAME_SIZE_MS = 30 // 30ms frames
        private val FRAME_SIZE_SAMPLES = kotlin.math.max(
            (SAMPLE_RATE * FRAME_SIZE_MS) / 1000,
            MIN_BUFFER / 2 // Ensure frame size is reasonable
        )
        
        /**
         * Convert ShortArray (16-bit PCM) to ByteArray for Google's processor
         * Google expects 16-bit PCM in little-endian format
         */
        private fun shortArrayToByteArray(shortArray: ShortArray): ByteArray {
            val byteArray = ByteArray(shortArray.size * 2)
            for (i in shortArray.indices) {
                val sample = shortArray[i]
                byteArray[i * 2] = (sample.toInt() and 0xFF).toByte()           // Low byte
                byteArray[i * 2 + 1] = ((sample.toInt() shr 8) and 0xFF).toByte()  // High byte
            }
            return byteArray
        }
    }

    private var audioRecord: AudioRecord? = null
    @Volatile private var isRecording = false
    @Volatile private var starting = false // CRITICAL FIX: Prevent double initialization
    private var recordingJob: Job? = null
    private var audioBuffer = mutableListOf<Short>()
    
    // Callbacks
    var onSpeechDetected: (() -> Unit)? = null
    var onSpeechEnded: (() -> Unit)? = null
    var onTranscriptionResult: ((String, Float) -> Unit)? = null
    var onError: ((String) -> Unit)? = null

    /**
     * Initialize audio recording capabilities
     */
    fun initialize(): Boolean {
        return try {
            Log.i(TAG, "=== INITIALIZING REAL GEMMA SPEECH RECOGNITION ===")
            
            Log.i(TAG, "📊 Audio configuration:")
            Log.i(TAG, "  Sample rate: ${SAMPLE_RATE}Hz")
            Log.i(TAG, "  Min buffer size: $MIN_BUFFER bytes")
            Log.i(TAG, "  Actual buffer size: $BUFFER_SIZE bytes")
            Log.i(TAG, "  Frame size: $FRAME_SIZE_SAMPLES samples")
            Log.i(TAG, "  Format: 16-bit PCM mono")
            
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION, // Better for speech
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                BUFFER_SIZE
            )
            
            val recordingState = audioRecord?.state == AudioRecord.STATE_INITIALIZED
            Log.i(TAG, if (recordingState) "✅ Audio recording initialized" else "❌ Audio recording failed to initialize")
            
            recordingState
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to initialize audio recording: ${e.message}", e)
            false
        }
    }

    /**
     * Start listening for speech and processing with Gemma
     */
    fun startListening(): Boolean {
        // CRITICAL FIX: Atomic guard to prevent double initialization
        if (isRecording || starting) {
            Log.w(TAG, "⚠️ Already listening or starting (isRecording=$isRecording, starting=$starting)")
            return isRecording
        }
        
        starting = true
        
        return try {
            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "❌ AudioRecord not initialized")
                onError?.invoke("AudioRecord not initialized")
                return false
            }
            
            Log.i(TAG, "🎤 Starting REAL Gemma speech recognition...")
            
            audioBuffer.clear()
            
            audioRecord?.startRecording()
            
            // Verify recording started
            if (audioRecord?.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                Log.e(TAG, "❌ Failed to start AudioRecord - state: ${audioRecord?.recordingState}")
                throw IllegalStateException("AudioRecord failed to start recording")
            }
            
            isRecording = true
            
            recordingJob = GlobalScope.launch(Dispatchers.IO) {
                processAudioStream()
            }
            
            Log.i(TAG, "✅ Listening for speech with REAL Gemma processing")
            true
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start listening: ${e.message}", e)
            onError?.invoke("Failed to start listening: ${e.message}")
            isRecording = false
            false
        } finally {
            starting = false
        }
    }

    /**
     * Stop listening and process any remaining audio
     */
    fun stopListening() {
        if (!isRecording) {
            Log.w(TAG, "⚠️ Not currently listening")
            return
        }
        
        try {
            Log.i(TAG, "🛑 Stopping Gemma speech recognition...")
            
            isRecording = false
            recordingJob?.cancel()
            audioRecord?.stop()
            
            // Process final audio if we have enough
            if (audioBuffer.isNotEmpty()) {
                GlobalScope.launch(Dispatchers.IO) {
                    processAudioWithGemma(audioBuffer.toShortArray(), true)
                }
            }
            
            audioBuffer.clear()
            Log.i(TAG, "✅ Speech recognition stopped")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error stopping speech recognition: ${e.message}", e)
        }
    }

    /**
     * Process audio stream in real-time
     */
    private suspend fun processAudioStream() {
        val buffer = ShortArray(FRAME_SIZE_SAMPLES)
        var lastVoiceTime = 0L
        var speechStartTime = 0L
        var isSpeaking = false
        val recordingStartTime = System.currentTimeMillis()
        var loopCount = 0
        
        Log.i(TAG, "🎵 Starting audio stream processing...")
        Log.i(TAG, "🔧 Buffer size: ${buffer.size} samples, FRAME_SIZE_SAMPLES: $FRAME_SIZE_SAMPLES")
        
        try {
            while (isRecording) {
                val currentTime = System.currentTimeMillis()
                loopCount++
                
                // CRITICAL FIX: Add periodic logging to debug loop behavior
                if (loopCount % 100 == 0) {
                    Log.v(TAG, "🔄 Loop tick #$loopCount - isRecording=$isRecording")
                }
                
                // Check max recording time
                if (currentTime - recordingStartTime > MAX_RECORDING_TIME_MS) {
                    Log.i(TAG, "⏰ Max recording time reached, processing speech...")
                    break
                }
                
                // CRITICAL FIX: Robust read with error handling
                val readBytes = audioRecord?.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING) ?: -1
                
                // CRITICAL FIX: Handle read errors properly
                if (readBytes <= 0) {
                    Log.w(TAG, "🚨 read() returned $readBytes (${if (readBytes == 0) "no data" else "error"})")
                    when (readBytes) {
                        AudioRecord.ERROR_INVALID_OPERATION -> {
                            Log.e(TAG, "❌ ERROR_INVALID_OPERATION - AudioRecord not initialized")
                            break
                        }
                        AudioRecord.ERROR_BAD_VALUE -> {
                            Log.e(TAG, "❌ ERROR_BAD_VALUE - Invalid parameters")
                            break
                        }
                        AudioRecord.ERROR_DEAD_OBJECT -> {
                            Log.e(TAG, "❌ ERROR_DEAD_OBJECT - AudioRecord object is dead")
                            break
                        }
                        AudioRecord.ERROR -> {
                            Log.e(TAG, "❌ Generic ERROR from AudioRecord")
                            break
                        }
                        0 -> {
                            Log.d(TAG, "🔄 No audio data available, continuing...")
                            delay(50) // Wait a bit and try again
                            continue
                        }
                        else -> {
                            Log.w(TAG, "⚠️ Unexpected read result: $readBytes, continuing...")
                            delay(10)
                            continue
                        }
                    }
                }
                
                // Log successful reads periodically
                if (loopCount % 50 == 0) {
                    Log.d(TAG, "✅ Read $readBytes samples successfully")
                }
                
                // Analyze for voice activity
                val hasVoiceActivity = detectVoiceActivity(buffer, readBytes)
                
                if (hasVoiceActivity) {
                    if (!isSpeaking) {
                        // Speech start detected
                        isSpeaking = true
                        speechStartTime = currentTime
                        onSpeechDetected?.invoke()
                        Log.i(TAG, "🗣️ Speech detected, starting buffer...")
                    }
                    
                    // Add to speech buffer
                    audioBuffer.addAll(buffer.take(readBytes))
                    lastVoiceTime = currentTime
                    
                } else if (isSpeaking) {
                    // Check if silence is long enough to end speech
                    val silenceDuration = currentTime - lastVoiceTime
                    val speechDuration = currentTime - speechStartTime
                    
                    if (silenceDuration > SILENCE_TIMEOUT_MS && speechDuration > MIN_SPEECH_LENGTH_MS) {
                        // End of speech detected
                        Log.i(TAG, "🔇 Speech ended after ${speechDuration}ms, processing with Gemma...")
                        
                        isSpeaking = false
                        onSpeechEnded?.invoke()
                        
                        // Process the collected audio
                        if (audioBuffer.isNotEmpty()) {
                            processAudioWithGemma(audioBuffer.toShortArray(), false)
                            audioBuffer.clear()
                        }
                    }
                }
                
                // Small delay to prevent tight loop
                delay(10)
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in audio stream processing: ${e.message}", e)
            onError?.invoke("Audio processing error: ${e.message}")
        }
        
        // CRITICAL FIX: Process any remaining audio after timeout or loop exit
        Log.i(TAG, "🎵 Audio stream processing ended after $loopCount loops")
        if (audioBuffer.isNotEmpty()) {
            Log.i(TAG, "📊 Processing ${audioBuffer.size} buffered audio samples after timeout...")
            processAudioWithGemma(audioBuffer.toShortArray(), true)
            audioBuffer.clear()
        } else {
            Log.w(TAG, "⚠️ No audio buffer to process - loop count: $loopCount")
        }
    }

    /**
     * Detect voice activity in audio frame
     */
    private fun detectVoiceActivity(audioData: ShortArray, length: Int): Boolean {
        if (length == 0) return false
        
        // Calculate RMS energy
        var sum = 0.0
        for (i in 0 until length) {
            val sample = audioData[i].toFloat() / Short.MAX_VALUE
            sum += sample * sample
        }
        
        val rms = sqrt(sum / length).toFloat()
        
        // DEBUG: Log audio energy levels
        Log.d(TAG, "🔊 Audio energy: ${String.format("%.4f", rms)} (threshold: $VOICE_ACTIVITY_THRESHOLD)")
        
        // TEMPORARY: Lower threshold for testing
        val hasVoice = rms > (VOICE_ACTIVITY_THRESHOLD * 0.5f) // More sensitive
        if (hasVoice) {
            Log.i(TAG, "🗣️ Voice activity detected! Energy: ${String.format("%.4f", rms)}")
        }
        
        return hasVoice
    }

    /**
     * Process audio buffer with REAL Gemma inference
     */
    private suspend fun processAudioWithGemma(audioData: ShortArray, isFinal: Boolean) {
        try {
            Log.i(TAG, "=== PROCESSING AUDIO WITH REAL GEMMA ===")
            Log.i(TAG, "🎵 Audio samples: ${audioData.size}")
            Log.i(TAG, "⏱️ Duration: ${(audioData.size.toFloat() / SAMPLE_RATE).toStringAsFixed(2)}s")
            Log.i(TAG, "🎯 Final: $isFinal")
            
            // Convert audio to features for Gemma
            val audioFeatures = extractAudioFeatures(audioData)
            
            // Create speech recognition prompt
            val speechPrompt = createSpeechRecognitionPrompt(audioFeatures)
            Log.i(TAG, "📝 Created speech recognition prompt (${speechPrompt.length} chars)")
            
            // Convert ShortArray to ByteArray for Google's processor
            val audioBytes = shortArrayToByteArray(audioData)
            
            // Process with Google's OFFICIAL audio processing
            Log.i(TAG, "🤖 Sending to Google's OFFICIAL Gemma for speech recognition...")
            val startTime = System.currentTimeMillis()
            
            val transcription = runBlocking {
                gemma3nProcessor.processAudioForSpeech(audioBytes)
            }
            
            val processingTime = System.currentTimeMillis() - startTime
            Log.i(TAG, "⚡ Gemma speech processing completed in ${processingTime}ms")
            
            // Clean and validate transcription
            val cleanedTranscription = cleanTranscriptionResult(transcription)
            val confidence = calculateConfidence(cleanedTranscription, audioFeatures)
            
            // DEBUG: Always log the raw response
            Log.i(TAG, "🤖 RAW Gemma response: \"$transcription\"")
            Log.i(TAG, "🧹 CLEANED response: \"$cleanedTranscription\"")
            Log.i(TAG, "🎯 Calculated confidence: ${(confidence * 100).toInt()}%")
            
            if (cleanedTranscription.isNotEmpty()) {
                Log.i(TAG, "✅ REAL TRANSCRIPTION: \"$cleanedTranscription\"")
                Log.i(TAG, "📞 CALLING onTranscriptionResult callback...")
                
                onTranscriptionResult?.invoke(cleanedTranscription, confidence)
                Log.i(TAG, "✅ Callback invoked successfully")
            } else {
                Log.i(TAG, "❌ No clear speech recognized - skipping empty result")
                // Don't send empty/test results to UI
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ REAL Gemma speech processing failed: ${e.message}", e)
            onError?.invoke("Speech processing failed: ${e.message}")
        }
    }

    /**
     * Extract audio features for Gemma analysis
     */
    private fun extractAudioFeatures(audioData: ShortArray): AudioFeatures {
        // Calculate basic audio features
        val energy = calculateEnergy(audioData)
        val zeroCrossingRate = calculateZeroCrossingRate(audioData)
        val spectralCentroid = estimateSpectralCentroid(audioData)
        val duration = audioData.size.toFloat() / SAMPLE_RATE
        
        return AudioFeatures(
            energy = energy,
            zeroCrossingRate = zeroCrossingRate,
            spectralCentroid = spectralCentroid,
            duration = duration,
            sampleCount = audioData.size
        )
    }

    /**
     * Create speech recognition prompt for Gemma
     */
    private fun createSpeechRecognitionPrompt(features: AudioFeatures): String {
        return """
You are ISABELLE, an AI accessibility assistant. Analyze this audio and transcribe the spoken words.

Audio Analysis:
- Duration: ${features.duration.toStringAsFixed(2)} seconds
- Energy Level: ${features.energy.toStringAsFixed(3)}
- Zero Crossing Rate: ${features.zeroCrossingRate.toStringAsFixed(0)} Hz
- Spectral Centroid: ${features.spectralCentroid.toStringAsFixed(0)} Hz

Speech Characteristics:
${if (features.energy > 0.05) "High energy speech (clear)" else "Low energy speech (quiet)"}
${if (features.zeroCrossingRate > 100 && features.zeroCrossingRate < 3000) "Human speech frequency range" else "Non-speech audio"}
${if (features.spectralCentroid < 1000) "Low pitch (male voice)" else if (features.spectralCentroid < 2000) "Medium pitch" else "High pitch (female voice)"}

Common words and phrases to recognize:
- "Isabelle" (wake word)
- "What's in front of me?"
- "Read this"
- "Help me"
- "Emergency"
- "Call someone"
- "Yes" / "No"
- Numbers (one, two, three, etc.)
- Navigation (up, down, left, right)

Based on the audio characteristics above, what words did the person speak?
Only return the transcribed text, nothing else:""".trimIndent()
    }

    /**
     * Clean transcription result from Gemma
     */
    private fun cleanTranscriptionResult(rawTranscription: String): String {
        return rawTranscription
            .trim()
            .replace(Regex("\\n+"), " ")
            .replace(Regex("\\s+"), " ")
            .replace(Regex("[^a-zA-Z0-9\\s.,!?'-]"), "")
            .lowercase()
            .capitalize()
    }

    /**
     * Calculate confidence score for transcription
     */
    private fun calculateConfidence(transcription: String, features: AudioFeatures): Float {
        if (transcription.isEmpty()) return 0.0f
        
        var confidence = 0.0f
        
        // Energy-based confidence
        confidence += when {
            features.energy > 0.1f -> 0.3f
            features.energy > 0.05f -> 0.2f
            else -> 0.1f
        }
        
        // Duration-based confidence
        confidence += when {
            features.duration > 2.0f -> 0.3f
            features.duration > 1.0f -> 0.2f
            else -> 0.1f
        }
        
        // Speech frequency-based confidence
        if (features.zeroCrossingRate > 100 && features.zeroCrossingRate < 3000) {
            confidence += 0.2f
        }
        
        // Length-based confidence
        confidence += (transcription.length.toFloat() / 50).coerceAtMost(0.2f)
        
        return confidence.coerceAtMost(1.0f)
    }

    // Audio analysis helper functions
    private fun calculateEnergy(audioData: ShortArray): Float {
        var sum = 0.0
        for (sample in audioData) {
            val normalized = sample.toFloat() / Short.MAX_VALUE
            sum += normalized * normalized
        }
        return sqrt(sum / audioData.size).toFloat()
    }

    private fun calculateZeroCrossingRate(audioData: ShortArray): Float {
        var crossings = 0
        for (i in 1 until audioData.size) {
            if ((audioData[i] >= 0) != (audioData[i-1] >= 0)) {
                crossings++
            }
        }
        return (crossings.toFloat() / audioData.size) * SAMPLE_RATE / 2
    }

    private fun estimateSpectralCentroid(audioData: ShortArray): Float {
        var weightedSum = 0.0
        var magnitudeSum = 0.0
        
        for (i in audioData.indices) {
            val magnitude = abs(audioData[i].toFloat())
            weightedSum += i * magnitude
            magnitudeSum += magnitude
        }
        
        return if (magnitudeSum > 0) {
            (weightedSum / magnitudeSum).toFloat()
        } else {
            0f
        }
    }

    /**
     * Clean up resources
     */
    fun cleanup() {
        stopListening()
        audioRecord?.release()
        audioRecord = null
        Log.i(TAG, "🧹 Gemma speech recognition cleaned up")
    }

    data class AudioFeatures(
        val energy: Float,
        val zeroCrossingRate: Float,
        val spectralCentroid: Float,
        val duration: Float,
        val sampleCount: Int
    )

    private fun Float.toStringAsFixed(decimals: Int): String = "%.${decimals}f".format(this)
}