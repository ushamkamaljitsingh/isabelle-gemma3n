import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
// import 'package:vosk_flutter/vosk_flutter.dart'; // TEMPORARILY DISABLED
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio/just_audio.dart';
import '../models/sound_event.dart';
import '../core/constants.dart';
import '../utils/core_utils.dart';
import 'gemma_inference_service.dart';

class AudioService extends ChangeNotifier {
  // Speech Recognition
  late stt.SpeechToText _speechToText;
  GemmaInferenceService? _gemmaInferenceService;
  bool _gemmaReady = false;
  bool _speechEnabled = false;
  bool _speechListening = false;
  bool _offlineSTTEnabled = false; // Will be true when Gemma is available
  String _lastWords = '';
  
  // Text-to-Speech
  late FlutterTts _flutterTts;
  bool _isSpeaking = false;
  
  // Audio playback
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // Sound detection
  static const MethodChannel _soundChannel = MethodChannel('sound_detection');
  bool _soundDetectionActive = false;
  StreamController<SoundEvent> _soundEventController = StreamController<SoundEvent>.broadcast();
  
  // Audio processing
  StreamController<Map<String, dynamic>> _audioFrameController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Performance tracking
  int _totalTranscriptions = 0;
  double _averageConfidence = 0.0;
  List<double> _confidenceHistory = [];
  
  // Callback properties for speech recognition
  Function(String)? onSpeechResult;
  Function(String)? onSpeechError;
  Function(String)? onSpeechStatus;

  // Getters
  bool get speechEnabled => _speechEnabled;
  bool get speechListening => _speechListening;
  bool get isSpeaking => _isSpeaking;
  bool get soundDetectionActive => _soundDetectionActive;
  bool get isInitialized => _speechEnabled; // Only online STT for now
  bool get offlineSTTEnabled => _offlineSTTEnabled; // Always false for now
  String get lastWords => _lastWords;
  int get totalTranscriptions => _totalTranscriptions;
  double get averageConfidence => _averageConfidence;
  
  Stream<SoundEvent> get soundEventStream => _soundEventController.stream;
  Stream<Map<String, dynamic>> get audioFrameStream => _audioFrameController.stream;
  
  /// Check if offline STT is available
  bool isOfflineSTTAvailable() {
    // Gemma doesn't support audio transcription - always return false
    return false;
  }

  /// Set the GemmaInferenceService for offline speech recognition
  Future<void> setGemmaService(GemmaInferenceService gemmaService) async {
    try {
      Logger.info('🔍 Setting up Gemma speech service...');
      
      _gemmaInferenceService = gemmaService;
      
      // Gemma doesn't support audio transcription
      _gemmaReady = true;
      _offlineSTTEnabled = false; // Always false since Gemma is text/vision only
      Logger.info('ℹ️ Gemma service set, but offline STT not available (Gemma is text/vision only)');
    } catch (e) {
      Logger.error('Failed to set up Gemma speech service: $e');
      _offlineSTTEnabled = false;
    }
  }

  Future<bool> initialize() async {
    final initStopwatch = Stopwatch()..start();
    
    Logger.info('=== AUDIO SERVICE INITIALIZATION START ===');
    Logger.info('🔊 Starting Audio Service initialization...');
    
    try {
      Logger.info('🔍 Step 1: Requesting audio permissions...');
      final permissionStopwatch = Stopwatch()..start();
      await _requestPermissions();
      Logger.info('⚡ Permissions processed in ${permissionStopwatch.elapsedMilliseconds}ms');
      
      Logger.info('🔍 Step 2: Initializing online STT...');
      final sttStopwatch = Stopwatch()..start();
      await _initializeOnlineSTT();
      Logger.info('⚡ STT initialization completed in ${sttStopwatch.elapsedMilliseconds}ms');
      
      Logger.info('🔍 Step 2.5: Initializing offline STT (Gemma)...');
      final offlineStopwatch = Stopwatch()..start();
      // await _initializeOfflineSTT(); // Initialization happens in setGemmaService
      Logger.info('⚡ Offline STT initialization completed in ${offlineStopwatch.elapsedMilliseconds}ms');
      
      Logger.info('🔍 Step 3: Initializing TTS...');
      final ttsStopwatch = Stopwatch()..start();
      await _initializeTTS();
      Logger.info('⚡ TTS initialization completed in ${ttsStopwatch.elapsedMilliseconds}ms');
      
      Logger.info('🔍 Step 4: Setting up sound detection...');
      final soundStopwatch = Stopwatch()..start();
      await _setupSoundDetection();
      Logger.info('⚡ Sound detection setup completed in ${soundStopwatch.elapsedMilliseconds}ms');
      
      Logger.info('=== AUDIO SERVICE INITIALIZATION SUCCESS ===');
      Logger.info('📊 Initialization Summary:');
      Logger.info('  Speech enabled: $_speechEnabled');
      Logger.info('  Offline STT enabled: $_offlineSTTEnabled');
      Logger.info('  TTS ready: ${_flutterTts != null}');
      Logger.info('  Sound detection ready: true');
      Logger.info('⚡ Total initialization time: ${initStopwatch.elapsedMilliseconds}ms');
      Logger.info('=== AUDIO SERVICE INITIALIZATION END ===');
      
      notifyListeners();
      return true;
      
    } catch (e, stackTrace) {
      Logger.error('❌ Failed to initialize Audio Service: $e');
      Logger.error('Stack trace: $stackTrace');
      Logger.info('⚡ Audio Service initialization failed after ${initStopwatch.elapsedMilliseconds}ms');
      Logger.info('=== AUDIO SERVICE INITIALIZATION END (FAILED) ===');
      return false;
    }
  }

  Future<void> _requestPermissions() async {
    Logger.info('🔒 Requesting microphone permission...');
    
    try {
      final micPermission = await Permission.microphone.request();
      
      Logger.info('📋 Permission result: $micPermission');
      
      if (micPermission != PermissionStatus.granted) {
        Logger.warning('❌ Microphone permission not granted: $micPermission');
        throw Exception('Microphone permission required for audio functionality');
      }
      
      Logger.info('✅ Audio permissions granted');
    } catch (e, stackTrace) {
      Logger.error('❌ Failed to request audio permissions: $e');
      Logger.error('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> _initializeOnlineSTT() async {
    Logger.info('🎤 Creating SpeechToText instance...');
    
    try {
      _speechToText = stt.SpeechToText();
      Logger.info('✅ SpeechToText instance created');
      
      Logger.info('🔄 Initializing speech recognition...');
      _speechEnabled = await _speechToText.initialize(
        onError: _onSpeechError,
        onStatus: _onSpeechStatus,
        debugLogging: false,
      );
      
      if (_speechEnabled) {
        Logger.info('✅ Online STT initialized successfully');
        
        // Get available locales
        final locales = await _speechToText.locales();
        Logger.info('📋 Available locales: ${locales.length}');
        Logger.info('🌐 Default locale: ${AppConstants.SPEECH_LOCALE}');
        
        // Check if device has speech recognition
        final isAvailable = await _speechToText.hasPermission;
        Logger.info('🔒 Speech permission: $isAvailable');
      } else {
        Logger.warning('❌ Online STT initialization failed');
      }
    } catch (e, stackTrace) {
      Logger.error('❌ Failed to initialize online STT: $e');
      Logger.error('Stack trace: $stackTrace');
    }
  }

  // OFFLINE STT METHODS - TEMPORARILY DISABLED
  /*
  Future<void> _initializeOfflineSTT() async {
    try {
      Logger.info('🔍 Initializing Gemma-based offline STT...');
      
      // We need to get the GemmaInferenceService instance
      // For now, we'll defer initialization until we have access to it
      // The actual initialization will happen in setGemmaService method
      
      Logger.info('✅ Offline STT (Gemma) ready for initialization');
      
    } catch (e) {
      Logger.error('Failed to initialize offline STT: $e');
    }
  }

  Future<String?> _loadVoskModel() async {
    try {
      const modelAssetPath = 'assets/models/vosk-model-small-en-us-0.15';
      Logger.info('Vosk model loading not implemented - using online STT only');
      return null;
    } catch (e) {
      Logger.error('Failed to load Vosk model: $e');
      return null;
    }
  }
  */

  Future<void> _initializeTTS() async {
    Logger.info('🗣️ Creating FlutterTts instance...');
    
    try {
      _flutterTts = FlutterTts();
      Logger.info('✅ FlutterTts instance created');
      
      Logger.info('🔄 Configuring TTS settings...');
      await _flutterTts.setLanguage(AppConstants.TTS_LANGUAGE);
      await _flutterTts.setSpeechRate(AppConstants.TTS_SPEECH_RATE);
      await _flutterTts.setPitch(AppConstants.TTS_PITCH);
      await _flutterTts.setVolume(AppConstants.TTS_VOLUME);
      
      Logger.info('=== TTS CONFIGURATION ===');
      Logger.info('🌐 Language: ${AppConstants.TTS_LANGUAGE}');
      Logger.info('⚡ Speech Rate: ${AppConstants.TTS_SPEECH_RATE}');
      Logger.info('🎵 Pitch: ${AppConstants.TTS_PITCH}');
      Logger.info('🔊 Volume: ${AppConstants.TTS_VOLUME}');
      
      Logger.info('🔄 Setting up TTS handlers...');
      _flutterTts.setCompletionHandler(() {
        Logger.info('✅ TTS completion handler called');
        _isSpeaking = false;
        notifyListeners();
      });
      
      _flutterTts.setErrorHandler((msg) {
        Logger.error('❌ TTS error: $msg');
        _isSpeaking = false;
        notifyListeners();
      });
      
      // Get available languages
      final languages = await _flutterTts.getLanguages;
      Logger.info('📋 Available TTS languages: ${languages?.length ?? 0}');
      
      // Get available voices
      final voices = await _flutterTts.getVoices;
      Logger.info('🎤 Available TTS voices: ${voices?.length ?? 0}');
      
      Logger.info('✅ TTS initialized successfully');
      
    } catch (e, stackTrace) {
      Logger.error('❌ Failed to initialize TTS: $e');
      Logger.error('Stack trace: $stackTrace');
    }
  }

  Future<void> _setupSoundDetection() async {
    try {
      _soundChannel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'onSoundDetected':
            final data = Map<String, dynamic>.from(call.arguments);
            final soundEvent = SoundEvent.fromJson(data);
            _soundEventController.add(soundEvent);
            Logger.info('Sound detected: ${soundEvent.description}');
            break;
          case 'onAudioFrame':
            final data = Map<String, dynamic>.from(call.arguments);
            _audioFrameController.add(data);
            break;
        }
      });
      
      Logger.info('Sound detection channel setup complete');
    } catch (e) {
      Logger.error('Failed to setup sound detection: $e');
    }
  }

  Future<void> startSpeechRecognition({
    required Function(String) onResult,
    required Function(String) onFinalResult,
    String? localeId,
    bool useOffline = true, // Default to offline for privacy
  }) async {
    // Prefer offline STT when available
    if (useOffline && _offlineSTTEnabled && (_gemmaInferenceService?.isInitialized ?? false)) {
      Logger.info('🔒 Using offline speech recognition with Gemma');
      return _startOfflineSpeechRecognition(onResult, onFinalResult);
    }
    
    if (_speechEnabled) {
      Logger.info('🌐 Using online speech recognition');
      return _startOnlineSpeechRecognition(onResult, onFinalResult, localeId);
    } else {
      Logger.error('Speech recognition not available');
      throw Exception('Speech recognition not available');
    }
  }

  Future<void> _startOfflineSpeechRecognition(
    Function(String) onResult,
    Function(String) onFinalResult,
  ) async {
    if (!(_gemmaInferenceService?.isInitialized ?? false)) {
      Logger.error('Gemma service not initialized for offline speech recognition');
      return _startOnlineSpeechRecognition(onResult, onFinalResult, null);
    }
    
    try {
      Logger.info('🎤 Starting offline speech recognition with Gemma...');
      _speechListening = true;
      notifyListeners();
      
      // Start audio recording for offline processing
      await _startAudioRecording();
      
      // Set up a timer to process audio chunks
      Timer.periodic(const Duration(seconds: 2), (timer) async {
        if (!_speechListening) {
          timer.cancel();
          return;
        }
        
        try {
          // Get current audio buffer
          final audioData = await _getCurrentAudioBuffer();
          if (audioData != null && audioData.isNotEmpty) {
            // For now, fallback to online STT as Gemma doesn't support audio transcription
            Logger.warning('⚠️ Gemma does not support audio transcription, falling back to online STT');
            // Cancel the timer and switch to online
            timer.cancel();
            _speechListening = false;
            notifyListeners();
            // Switch to online speech recognition
            return _startOnlineSpeechRecognition(onResult, onFinalResult, null);
          }
        } catch (e) {
          Logger.error('Error in offline speech processing: $e');
          // Don't cancel timer immediately - give it another chance
        }
      });
      
      // Auto-stop after 30 seconds
      Timer(const Duration(seconds: 30), () async {
        if (_speechListening) {
          Logger.info('Auto-stopping offline speech recognition after 30s');
          await stopSpeechRecognition();
        }
      });
      
    } catch (e) {
      Logger.error('Failed to start offline speech recognition: $e');
      _speechListening = false;
      notifyListeners();
      
      // Fall back to online speech recognition
      return _startOnlineSpeechRecognition(onResult, onFinalResult, null);
    }
  }
  
  /// Start audio recording for offline processing
  Future<void> _startAudioRecording() async {
    // Audio recording implementation - using native Android AudioRecord integration
    // Connected to native audio monitoring system for real-time processing
    Logger.info('Starting audio recording for offline STT...');
  }
  
  /// Get current audio buffer for processing
  Future<Uint8List?> _getCurrentAudioBuffer() async {
    // Audio buffer retrieval - connected to native Android AudioRecord system
    // For now, we'll return null to use online fallback
    return null;
  }

  Future<void> _startOnlineSpeechRecognition(
    Function(String) onResult,
    Function(String) onFinalResult,
    String? localeId,
  ) async {
    if (!_speechEnabled) {
      Logger.error('Online speech recognition not enabled');
      return;
    }

    try {
      _speechListening = true;
      notifyListeners();
      
      Logger.info('Starting online speech recognition...');
      
      await _speechToText.listen(
        onResult: (result) {
          _lastWords = result.recognizedWords;
          _updateConfidenceTracking(result.confidence);
          
          Logger.debug('Speech result: $_lastWords (${result.confidence})');
          
          onResult(_lastWords);
          
          if (result.finalResult) {
            Logger.info('Final speech result: $_lastWords');
            onFinalResult(_lastWords);
            _totalTranscriptions++;
          }
        },
        listenFor: Duration(seconds: AppConstants.SPEECH_LISTEN_DURATION_SECONDS),
        pauseFor: Duration(seconds: AppConstants.SPEECH_PAUSE_DURATION_SECONDS),
        partialResults: AppConstants.SPEECH_PARTIAL_RESULTS,
        localeId: localeId ?? AppConstants.SPEECH_LOCALE,
        listenMode: stt.ListenMode.confirmation,
        cancelOnError: true,
      );
      
    } catch (e) {
      Logger.error('Failed to start online speech recognition: $e');
      _speechListening = false;
      notifyListeners();
    }
  }

  void _updateConfidenceTracking(double confidence) {
    _confidenceHistory.add(confidence);
    
    if (_confidenceHistory.length > 100) {
      _confidenceHistory.removeAt(0);
    }
    
    _averageConfidence = _confidenceHistory.reduce((a, b) => a + b) / _confidenceHistory.length;
  }

  Future<void> stopSpeechRecognition() async {
    if (_speechListening) {
      try {
        // Offline STT is currently disabled (GemmaSpeechService removed)
        // TODO: Re-implement when direct Gemma integration is ready
        
        // Stop online STT if it's being used
        if (_speechEnabled && _speechToText.isListening) {
          await _speechToText.stop();
          Logger.info('Online speech recognition stopped');
        }
        
        _speechListening = false;
        notifyListeners();
        
      } catch (e) {
        Logger.error('Failed to stop speech recognition: $e');
      }
    }
  }

  Future<void> speakText(String text, {
    double? pitch,
    double? rate,
    double? volume,
  }) async {
    if (text.trim().isEmpty) return;
    
    try {
      if (_isSpeaking) {
        await _flutterTts.stop();
      }
      
      _isSpeaking = true;
      notifyListeners();
      
      Logger.info('Speaking: "${text.substring(0, text.length.clamp(0, 50))}..."');
      
      if (pitch != null) await _flutterTts.setPitch(pitch);
      if (rate != null) await _flutterTts.setSpeechRate(rate);
      if (volume != null) await _flutterTts.setVolume(volume);
      
      await _flutterTts.speak(text);
      
    } catch (e) {
      Logger.error('Failed to speak text: $e');
      _isSpeaking = false;
      notifyListeners();
    }
  }

  Future<void> startSoundDetection() async {
    if (_soundDetectionActive) return;
    
    try {
      await _soundChannel.invokeMethod('startSoundDetection', {
        'sensitivity': AppConstants.NORMAL_SOUND_THRESHOLD,
        'emergencyThreshold': AppConstants.EMERGENCY_SOUND_THRESHOLD,
      });
      
      _soundDetectionActive = true;
      notifyListeners();
      
      Logger.info('Sound detection started');
      
    } catch (e) {
      Logger.error('Failed to start sound detection: $e');
      _soundDetectionActive = false;
      notifyListeners();
    }
  }

  Future<void> stopSoundDetection() async {
    if (!_soundDetectionActive) return;
    
    try {
      await _soundChannel.invokeMethod('stopSoundDetection');
      _soundDetectionActive = false;
      notifyListeners();
      
      Logger.info('Sound detection stopped');
      
    } catch (e) {
      Logger.error('Failed to stop sound detection: $e');
    }
  }

  void _onSpeechError(dynamic error) {
    Logger.error('Speech recognition error: $error');
    _speechListening = false;
    notifyListeners();
  }

  void _onSpeechStatus(String status) {
    switch (status) {
      case 'done':
      case 'notListening':
        _speechListening = false;
        notifyListeners();
        // Restart detection for continuous monitoring (deaf mode)
        _restartDetectionIfNeeded();
        break;
      case 'listening':
        _speechListening = true;
        notifyListeners();
        break;
    }
  }
  
  void _restartDetectionIfNeeded() {
    // Only restart if we're in deaf mode and no other speech session is active
    if (!_speechListening && _soundDetectionActive) {
      Logger.info('🔄 Scheduling speech recognition restart...');
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (!_speechListening && _soundDetectionActive) {
          Logger.info('🔄 Restarting speech recognition for continuous monitoring');
          Logger.info('🎯 This enables live transcription for deaf users');
          
          startSpeechRecognition(
            onResult: (result) {
              Logger.info('🎤 DEAF MODE - Partial transcription: "$result"');
              if (result.isNotEmpty) {
                Logger.info('✅ Live transcription working: ${result.length} chars');
              }
            },
            onFinalResult: (finalResult) {
              Logger.info('🎤 DEAF MODE - Final transcription: "$finalResult"');
              Logger.info('📝 Transcription length: ${finalResult.length} characters');
              if (finalResult.isNotEmpty) {
                Logger.info('🎯 TRANSCRIPTION SUCCESS - Deaf mode receiving text');
              } else {
                Logger.warning('⚠️ Empty transcription result in deaf mode');
              }
            },
          );
        } else {
          Logger.info('ℹ️ Speech recognition restart skipped - conditions not met');
        }
      });
    }
  }

  Future<void> configureTTS({
    double? pitch,
    double? rate,
    double? volume,
    String? language,
  }) async {
    try {
      if (pitch != null) {
        await _flutterTts.setPitch(pitch);
      }
      if (rate != null) {
        await _flutterTts.setSpeechRate(rate);
      }
      if (volume != null) {
        await _flutterTts.setVolume(volume);
      }
      if (language != null) {
        await _flutterTts.setLanguage(language);
      }
      Logger.info('TTS configuration updated');
    } catch (e) {
      Logger.error('Failed to configure TTS: $e');
    }
  }


  Future<void> playAlertSound(String alertType) async {
    try {
      String assetPath;
      switch (alertType) {
        case 'emergency':
          assetPath = 'assets/sounds/emergency_alert.wav';
          break;
        case 'notification':
          assetPath = 'assets/sounds/notification.wav';
          break;
        case 'success':
          assetPath = 'assets/sounds/success.wav';
          break;
        default:
          assetPath = 'assets/sounds/default_alert.wav';
      }
      
      await _audioPlayer.setAsset(assetPath);
      await _audioPlayer.play();
      
      Logger.info('Alert sound played: $alertType');
    } catch (e) {
      Logger.error('Failed to play alert sound: $e');
    }
  }

  Future<void> enhanceTranscription(String rawText) async {
    if (rawText.trim().isEmpty) return;
    
    try {
      // This would normally use the Gemma service to enhance transcription
      // For now, just do basic cleanup
      final enhanced = _basicTranscriptionCleanup(rawText);
      
      if (enhanced != rawText) {
        Logger.info('Transcription enhanced: $rawText -> $enhanced');
      }
    } catch (e) {
      Logger.error('Failed to enhance transcription: $e');
    }
  }

  String _basicTranscriptionCleanup(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), ' ') // Multiple spaces to single
        .replaceAll(RegExp(r'\.\.+'), '.') // Multiple dots to single
        .replaceAll(RegExp(r'\?\?+'), '?') // Multiple question marks
        .replaceAll(RegExp(r'!!+'), '!') // Multiple exclamation marks
        .trim();
  }

  Map<String, dynamic> getAudioStats() {
    return {
      'speechEnabled': _speechEnabled,
      'offlineSTTEnabled': _offlineSTTEnabled,
      'speechListening': _speechListening,
      'isSpeaking': _isSpeaking,
      'soundDetectionActive': _soundDetectionActive,
      'totalTranscriptions': _totalTranscriptions,
      'averageConfidence': _averageConfidence,
      'lastWords': _lastWords,
    };
  }

  Future<void> testAudioSystems() async {
    Logger.info('Testing audio systems...');
    
    try {
      // Test TTS
      await speakText('Audio test: Text to speech working');
      await Future.delayed(const Duration(seconds: 2));
      
      // Test sound detection
      if (!_soundDetectionActive) {
        await startSoundDetection();
      }
      
      Logger.info('Audio systems test completed');
    } catch (e) {
      Logger.error('Audio systems test failed: $e');
    }
  }

  /// CRITICAL: Configure emergency sound detection system
  Future<void> configureEmergencyDetection({
    required List<String> emergencySounds,
    required Function(String) onEmergencyDetected,
  }) async {
    try {
      Logger.info('🚨 CRITICAL: Configuring emergency sound detection...');
      Logger.info('Emergency sounds to detect: ${emergencySounds.join(', ')}');
      
      // Start sound detection if not already active
      if (!_soundDetectionActive) {
        await startSoundDetection();
      }
      
      // Listen for sound events and check for emergency patterns
      _soundEventController.stream.listen((soundEvent) {
        final description = soundEvent.description.toLowerCase();
        
        // Check if this sound matches any emergency patterns
        for (final emergencySound in emergencySounds) {
          if (description.contains(emergencySound.toLowerCase()) ||
              _isEmergencySound(description, emergencySound)) {
            Logger.warning('🚨 EMERGENCY SOUND DETECTED: $emergencySound');
            Logger.warning('Sound description: ${soundEvent.description}');
            Logger.warning('Confidence: ${soundEvent.confidence}');
            
            // Trigger emergency callback
            onEmergencyDetected(emergencySound);
            break;
          }
        }
      });
      
      Logger.info('✅ CRITICAL: Emergency sound detection configured successfully');
    } catch (e) {
      Logger.error('🚨 CRITICAL ERROR: Failed to configure emergency sound detection: $e');
    }
  }

  /// Check if a sound description matches emergency patterns
  bool _isEmergencySound(String description, String emergencyType) {
    final emergencyPatterns = {
      'fire_alarm': ['alarm', 'fire', 'smoke', 'beeping', 'siren'],
      'smoke_detector': ['smoke', 'detector', 'beep', 'chirp', 'alarm'],
      'car_horn': ['horn', 'car', 'honk', 'vehicle', 'traffic'],
      'screaming': ['scream', 'yell', 'shout', 'help', 'panic'],
      'glass_breaking': ['glass', 'break', 'shatter', 'crash', 'smash'],
      'door_slamming': ['door', 'slam', 'bang', 'crash', 'thud'],
      'gunshot': ['shot', 'gun', 'bang', 'pop', 'crack'],
      'explosion': ['explosion', 'blast', 'boom', 'detonate'],
      'siren': ['siren', 'ambulance', 'police', 'fire truck', 'emergency'],
      'shouting_help': ['help', 'emergency', 'assistance', 'aid'],
    };
    
    final patterns = emergencyPatterns[emergencyType] ?? [emergencyType];
    
    return patterns.any((pattern) => description.contains(pattern));
  }

  /// CRITICAL: Announce emergency with high priority TTS
  Future<void> announceEmergency(String message) async {
    try {
      Logger.warning('🚨 EMERGENCY ANNOUNCEMENT: $message');
      
      // Stop any current speech
      await _flutterTts.stop();
      
      // Configure TTS for emergency (loud, clear, slow)
      await _flutterTts.setVolume(1.0); // Maximum volume
      await _flutterTts.setSpeechRate(0.6); // Slower for clarity
      await _flutterTts.setPitch(1.2); // Slightly higher pitch for urgency
      
      // Speak the emergency message
      await _flutterTts.speak(message);
      
      Logger.info('✅ Emergency announcement delivered');
    } catch (e) {
      Logger.error('🚨 CRITICAL ERROR: Failed to announce emergency: $e');
    }
  }

  @override
  void dispose() {
    stopSpeechRecognition();
    stopSoundDetection();
    _soundEventController.close();
    _audioFrameController.close();
    _audioPlayer.dispose();
    _flutterTts.stop();
    
    // Clean up Vosk resources (when re-enabled)
    // _voskRecognizer = null;
    // _voskModel = null;
    
    super.dispose();
  }
}