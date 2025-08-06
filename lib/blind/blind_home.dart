import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../utils/core_utils.dart';
import 'object_describer.dart';
import '../services/audio_service.dart';
import '../services/gemma_inference_service.dart';
import '../services/realtime_video_service.dart';
import '../widgets/eye_camera_preview.dart';
import 'package:provider/provider.dart';

class BlindHome extends StatefulWidget {
  const BlindHome({Key? key}) : super(key: key);

  @override
  State<BlindHome> createState() => _BlindHomeState();
}

class _BlindHomeState extends State<BlindHome> with TickerProviderStateMixin, WidgetsBindingObserver {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final ObjectDescriber _objectDescriber = ObjectDescriber();
  
  // Offline speech service
  AudioService? _audioService;
  
  // Real-time video description service
  final RealtimeVideoService _realtimeVideoService = RealtimeVideoService();
  
  // Animation controllers
  late AnimationController _starsController;
  late Animation<double> _starsAnimation;
  
  bool _isListening = false;
  bool _speechEnabled = false;
  bool _offlineSpeechEnabled = false;
  String _currentCommand = '';
  String _lastResponse = 'Say "What is in front?" or tap the button to see';
  bool _isProcessing = false;
  
  // Processing state with detailed progress
  bool _showCameraPreview = false;
  String _processingText = 'Ready';
  String _processingStage = 'idle'; // idle, listening, capturing, analyzing, speaking
  double _processingProgress = 0.0;
  
  bool _gemmaReady = false;
  bool _realtimeDescriptionActive = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
    _setupAnimations();
  }
  
  void _setupAnimations() {
    _starsController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );
    
    _starsAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _starsController,
      curve: Curves.linear,
    ));
    
    _starsController.repeat();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speechToText.stop();
    _flutterTts.stop();
    _objectDescriber.dispose();
    _starsController.dispose();
    // Stop real-time description if active
    if (_realtimeDescriptionActive) {
      _realtimeVideoService.stopRealtimeDescriber();
    }
    super.dispose();
  }
  
  Future<void> _initializeServices() async {
    try {
      Logger.info('🎯 BlindHome: Starting services initialization...');
      
      // Initialize TTS
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      Logger.info('✅ TTS initialized');
      
      // Initialize speech recognition
      await _initializeSpeech();
      
      // Initialize audio service for offline speech
      if (mounted) {
        _audioService = Provider.of<AudioService>(context, listen: false);
      }
      
      // Initialize object describer with error handling
      try {
        await _objectDescriber.initialize();
        Logger.info('✅ Object Describer initialized');
      } catch (e) {
        Logger.error('⚠️ Object Describer initialization failed: $e');
        // Continue without camera - other features still work
      }
      
      // Check if Gemma service is ready - retry a few times if needed
      final gemmaService = Provider.of<GemmaInferenceService>(context, listen: false);
      var gemmaReady = gemmaService.isInitialized;
      
      // If not ready, wait and check again (the service might still be connecting)
      if (!gemmaReady) {
        Logger.info('🔄 Gemma not ready on first check, waiting and retrying...');
        await Future.delayed(const Duration(milliseconds: 1000));
        gemmaReady = gemmaService.isInitialized;
        
        if (!gemmaReady) {
          Logger.info('🔄 Gemma still not ready, trying one more time...');
          await Future.delayed(const Duration(milliseconds: 2000));
          gemmaReady = gemmaService.isInitialized;
        }
      }
      
      Logger.info('🔍 BlindHome initialization - Final Gemma state:');
      Logger.info('  - gemmaService: $gemmaService');
      Logger.info('  - gemmaService.isInitialized: $gemmaReady');
      Logger.info('  - Setting _gemmaReady to: $gemmaReady');
      
      setState(() {
        _gemmaReady = gemmaReady;
        _processingText = gemmaReady ? 'Ready' : 'AI Loading...';
      });
      
      // Setup real-time video service callbacks
      _realtimeVideoService.onSceneDescription = (description, frameNumber) {
        if (mounted) {
          Logger.info('📺 Real-time scene: $description');
          // Speak the real-time description
          _speak(description);
          setState(() {
            _lastResponse = 'Real-time: $description';
          });
        }
      };
      
      _realtimeVideoService.onError = (error) {
        if (mounted) {
          Logger.error('❌ Real-time video error: $error');
          _speak('Real-time video error: $error');
        }
      };
      
      // Welcome message
      if (gemmaReady) {
        await _speak('ISABELLE is ready! Say "What is in front?" or tap the button to see what I can see.');
      } else {
        await _speak('ISABELLE is starting. The AI vision system is still loading, please wait.');
      }
      
    } catch (e) {
      Logger.error('Failed to initialize services: $e');
      await _speak('Some features may not be available. Please restart the app.');
    }
  }
  
  Future<void> _initializeSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onError: (error) {
          Logger.error('Speech recognition error: $error');
          if (error.errorMsg != 'error_no_match') {
            setState(() => _currentCommand = 'Error: ${error.errorMsg}');
          }
          // Auto-restart listening for recoverable errors
          if (mounted && !_isProcessing && error.errorMsg == 'error_no_match') {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) _startListening();
            });
          }
        },
        onStatus: (status) {
          Logger.info('Speech recognition status: $status');
          if (status == 'notListening' && mounted) {
            setState(() => _isListening = false);
            // Auto-restart if we're not processing and should be listening
            if (!_isProcessing) {
              Future.delayed(const Duration(milliseconds: 1000), () {
                if (mounted) _startListening();
              });
            }
          }
        },
      );
      
      if (_speechEnabled) {
        _startListening();
      }
    } catch (e) {
      Logger.error('Failed to initialize speech: $e');
      _speechEnabled = false;
    }
  }
  
  Future<void> _startListening() async {
    if (!_speechEnabled || _isListening || _isProcessing) return;
    
    try {
      setState(() => _isListening = true);
      
      await _speechToText.listen(
        onResult: (result) {
          setState(() {
            _currentCommand = result.recognizedWords;
          });
          
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            _processVoiceCommand(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 60), // Increased listening duration
        pauseFor: const Duration(seconds: 5), // Longer pause to handle pauses in speech
        partialResults: true,
        onSoundLevelChange: (level) {
          // Log sound levels to debug microphone issues
          if (level > 0.1) {
            Logger.info('🎤 Sound level: $level');
          }
        },
        cancelOnError: false, // Don't cancel on minor errors
        listenMode: ListenMode.confirmation,
        localeId: 'en_US', // Explicit locale
      );
    } catch (e) {
      Logger.error('Error starting speech recognition: $e');
      setState(() => _isListening = false);
      
      // Auto-restart listening after error
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_isProcessing) {
          _startListening();
        }
      });
    }
  }
  
  Future<void> _stopListening() async {
    await _speechToText.stop();
    setState(() => _isListening = false);
  }
  
  Future<void> _speak(String text) async {
    try {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      Logger.error('TTS error: $e');
    }
  }
  
  Future<void> _processVoiceCommand(String command) async {
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
      _currentCommand = command;
    });
    
    await _stopListening();
    
    try {
      final lowerCommand = command.toLowerCase();
      
      // Check for real-time description commands
      if (lowerCommand.contains('start') && 
          (lowerCommand.contains('continuous') || 
           lowerCommand.contains('real') || 
           lowerCommand.contains('live'))) {
        if (!_realtimeDescriptionActive) {
          await _toggleRealtimeDescription();
        } else {
          await _speak('Continuous description is already active.');
        }
      } else if (lowerCommand.contains('stop') && 
                 (lowerCommand.contains('continuous') || 
                  lowerCommand.contains('real') || 
                  lowerCommand.contains('live'))) {
        if (_realtimeDescriptionActive) {
          await _toggleRealtimeDescription();
        } else {
          await _speak('Continuous description is not active.');
        }
      } else if (lowerCommand.contains('continuous') || 
                 lowerCommand.contains('real time') ||
                 lowerCommand.contains('live')) {
        // Toggle real-time description
        await _toggleRealtimeDescription();
      } else if (lowerCommand.contains('what') || 
          lowerCommand.contains('see') || 
          lowerCommand.contains('look') ||
          lowerCommand.contains('describe') ||
          lowerCommand.contains('front') ||
          lowerCommand.contains('around') ||
          lowerCommand.contains('show')) {
        await _describeScene();
      } else {
        await _speak('Say "What is in front?" for a single description, or "Start continuous" for live descriptions.');
      }
      
    } catch (e) {
      await _speak('Sorry, I had trouble processing that. Please try again.');
      Logger.error('Voice command processing error: $e');
    }
    
    setState(() {
      _isProcessing = false;
    });
    
    // Restart listening
    _startListening();
  }
  
  Future<void> _describeScene() async {
    try {
      // Check if Gemma service is initialized first
      final gemmaService = Provider.of<GemmaInferenceService>(context, listen: false);
      Logger.info('🔍 Debug Gemma service state:');
      Logger.info('  - gemmaService: $gemmaService');
      Logger.info('  - gemmaService.isInitialized: ${gemmaService.isInitialized}');
      
      if (!gemmaService.isInitialized) {
        Logger.error('❌ Gemma service not initialized');
        await _speak('The AI vision system is still loading. Please wait a moment and try again.');
        setState(() {
          _processingStage = 'idle';
          _processingText = 'AI Loading...';
          _lastResponse = 'AI vision system is still loading. Please wait...';
        });
        return;
      }
      
      // Set Gemma service for object describer
      _objectDescriber.setGemmaService(gemmaService);
      
      // Stage 1: Initial setup
      setState(() {
        _processingStage = 'capturing';
        _processingProgress = 0.1;
        _lastResponse = 'Starting vision analysis...';
        _showCameraPreview = true;
        _processingText = '📸 Opening camera...';
      });
      
      await _speak('Let me look and tell you what I see.');
      
      // Stage 2: Camera capture
      setState(() {
        _processingProgress = 0.3;
        _processingText = '📸 Taking photo...';
      });
      
      Logger.info('Starting AI vision analysis...');
      
      // Stage 3: AI processing
      setState(() {
        _processingProgress = 0.5;
        _processingText = '🤖 AI analyzing image...';
      });
      
      final description = await _objectDescriber.describeCurrentScene();
      
      // Stage 4: Analysis complete
      setState(() {
        _processingProgress = 0.9;
        _processingText = '✨ Analysis complete!';
      });
      
      // Small delay to show completion
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Stage 5: Speaking response
      setState(() {
        _processingStage = 'speaking';
        _processingProgress = 1.0;
        _lastResponse = description;
        _showCameraPreview = false;
        _processingText = '🔊 Speaking result...';
      });
      
      await _speak(description);
      
      // Reset to idle state
      setState(() {
        _processingStage = 'idle';
        _processingProgress = 0.0;
        _processingText = 'Ready';
      });
      
      Logger.info('Vision analysis completed successfully');
      
    } catch (e) {
      Logger.error('Vision analysis error: $e');
      
      // Determine error type for specific user feedback
      String errorMessage;
      String speakMessage;
      
      if (e.toString().contains('Camera')) {
        errorMessage = 'Camera Error: Unable to take photo';
        speakMessage = 'I\'m having trouble with my camera. Please check that the camera isn\'t blocked and try again.';
      } else if (e.toString().contains('AI') || e.toString().contains('not ready')) {
        errorMessage = 'AI Vision System Loading...';
        speakMessage = 'My AI vision system is still loading. Please wait a moment and try again.';
      } else {
        errorMessage = 'Vision Error: Please try again';
        speakMessage = 'I had trouble analyzing what I see. Please try again.';
      }
      
      setState(() {
        _processingStage = 'idle';
        _processingProgress = 0.0;
        _lastResponse = errorMessage;
        _showCameraPreview = false;
        _processingText = 'Ready';
      });
      
      await _speak(speakMessage);
    }
  }
  
  Future<void> _toggleRealtimeDescription() async {
    try {
      // Check if Gemma service is ready first
      final gemmaService = Provider.of<GemmaInferenceService>(context, listen: false);
      if (!gemmaService.isInitialized) {
        await _speak('The AI vision system is still loading. Please wait and try again.');
        return;
      }
      
      if (_realtimeDescriptionActive) {
        // Stop real-time description
        setState(() {
          _realtimeDescriptionActive = false;
          _processingText = 'Stopping real-time...';
        });
        
        await _speak('Stopping continuous description.');
        final success = await _realtimeVideoService.stopRealtimeDescriber();
        
        setState(() {
          _realtimeDescriptionActive = false;
          _processingText = success ? 'Ready' : 'Error stopping';
          _lastResponse = success ? 'Continuous description stopped.' : 'Error stopping real-time description.';
        });
        
      } else {
        // Start real-time description
        setState(() {
          _realtimeDescriptionActive = true;
          _processingText = 'Starting real-time...';
        });
        
        await _speak('Starting continuous description of your surroundings.');
        final success = await _realtimeVideoService.startRealtimeDescriber();
        
        setState(() {
          _realtimeDescriptionActive = success;
          _processingText = success ? 'Real-time Active' : 'Error starting';
          _lastResponse = success ? 'Continuous description active. I\'ll describe what I see.' : 'Error starting real-time description.';
        });
        
        if (!success) {
          await _speak('Failed to start continuous description. Please try again.');
        }
      }
      
    } catch (e) {
      Logger.error('Error toggling real-time description: $e');
      await _speak('Error with continuous description. Please try again.');
      setState(() {
        _realtimeDescriptionActive = false;
        _processingText = 'Ready';
      });
    }
  }
  
  /// Get appropriate icon for current processing stage
  IconData _getProcessingIcon() {
    switch (_processingStage) {
      case 'capturing':
        return Icons.camera_alt;
      case 'analyzing':
        return Icons.psychology;
      case 'speaking':
        return Icons.volume_up;
      default:
        return Icons.visibility;
    }
  }
  
  /// Build premium glass morphism button
  Widget _buildPremiumButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    bool isActive = false,
    bool isPrimary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: onTap == null ? [
              Colors.grey.withOpacity(0.1),
              Colors.grey.withOpacity(0.05),
            ] : [
              color.withOpacity(isPrimary ? 0.3 : 0.15),
              color.withOpacity(isPrimary ? 0.15 : 0.05),
            ],
          ),
          border: Border.all(
            color: onTap == null 
                ? Colors.grey.withOpacity(0.3) 
                : color.withOpacity(isPrimary ? 0.8 : 0.4),
            width: isPrimary ? 2 : 1,
          ),
          boxShadow: onTap == null ? [] : [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: isPrimary ? 20 : 10,
              spreadRadius: isPrimary ? 2 : 0,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: onTap == null 
                  ? Colors.grey.withOpacity(0.5)
                  : color,
              size: isPrimary ? 28 : 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: isPrimary ? 13 : 11,
                fontWeight: FontWeight.w600,
                color: onTap == null 
                    ? Colors.grey.withOpacity(0.5)
                    : Colors.white.withOpacity(0.9),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 2.0,
            colors: [
              const Color(0xFF0A0A0A), // Deep black center
              const Color(0xFF1A0F2E), // Purple-black
              const Color(0xFF0D1B2A), // Navy-black edges
            ],
          ),
        ),
        child: Stack(
          children: [
            // Enhanced animated starry background
            AnimatedBuilder(
              animation: _starsAnimation,
              builder: (context, child) {
                return CustomPaint(
                  painter: EnhancedStarryBackgroundPainter(_starsAnimation.value),
                  size: Size.infinite,
                );
              },
            ),
            
            // Floating particles for premium feel
            AnimatedBuilder(
              animation: _starsAnimation,
              builder: (context, child) {
                return CustomPaint(
                  painter: FloatingParticlesPainter(_starsAnimation.value),
                  size: Size.infinite,
                );
              },
            ),
            
            SafeArea(
              child: Column(
                children: [
                  // Premium header with glass morphism effect
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(0.1),
                          Colors.white.withOpacity(0.05),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Premium ISABELLE logo
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              Color(0xFF00FFFF), // Cyan
                              Color(0xFF0080FF), // Blue
                              Color(0xFF8A2BE2), // Purple
                            ],
                          ).createShader(bounds),
                          child: const Text(
                            'ISABELLE',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF00FFFF).withOpacity(0.2),
                                const Color(0xFF8A2BE2).withOpacity(0.2),
                              ],
                            ),
                            border: Border.all(
                              color: const Color(0xFF00FFFF).withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: const Text(
                            'AI Vision Assistant • Powered by Gemma 3n',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF00CCAA),
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Premium Eye - Full screen immersive experience
                  Expanded(
                    flex: isLandscape ? 6 : 8,
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: isLandscape ? 2.0 : 1.2,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(40),
                              boxShadow: [
                                // Multiple layered shadows for depth
                                BoxShadow(
                                  color: const Color(0xFF00FFFF).withOpacity(0.3),
                                  blurRadius: 60,
                                  spreadRadius: 5,
                                ),
                                BoxShadow(
                                  color: const Color(0xFF8A2BE2).withOpacity(0.2),
                                  blurRadius: 40,
                                  spreadRadius: 10,
                                ),
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.5),
                                  blurRadius: 30,
                                  offset: const Offset(0, 15),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(40),
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: Alignment.center,
                                    radius: 1.0,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.1),
                                      Colors.black.withOpacity(0.3),
                                    ],
                                  ),
                                ),
                                child: EyeCameraPreview(
                                  cameraController: _objectDescriber.cameraController,
                                  isVisible: true,
                                  isProcessing: _isProcessing,
                                  processingText: _processingText,
                                  eyeSize: screenSize.width * 0.85,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // Premium status and controls section
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(
                      children: [
                        // Premium voice status card with glass morphism
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withOpacity(0.15),
                                Colors.white.withOpacity(0.05),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Premium status indicator with animated glow
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 500),
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _isListening 
                                          ? const Color(0xFF00FF41)
                                          : _isProcessing 
                                              ? const Color(0xFFFF6B35)
                                              : const Color(0xFF00D2FF),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (_isListening 
                                              ? const Color(0xFF00FF41)
                                              : _isProcessing 
                                                  ? const Color(0xFFFF6B35)
                                                  : const Color(0xFF00D2FF)).withOpacity(0.6),
                                          blurRadius: 12,
                                          spreadRadius: 3,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ShaderMask(
                                    shaderCallback: (bounds) => LinearGradient(
                                      colors: [
                                        _isListening ? const Color(0xFF00FF41) : const Color(0xFF00D2FF),
                                        _isProcessing ? const Color(0xFFFF6B35) : const Color(0xFF8A2BE2),
                                      ],
                                    ).createShader(bounds),
                                    child: Text(
                                      _isListening 
                                          ? 'Listening to your voice...'
                                          : _isProcessing 
                                              ? 'Analyzing with AI...'
                                              : _realtimeDescriptionActive
                                                  ? 'Live Vision Active'
                                                  : 'Ready to help you see',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Response text with beautiful typography
                              Container(
                                constraints: const BoxConstraints(minHeight: 60),
                                child: Text(
                                  _isListening && _currentCommand.isNotEmpty
                                      ? '"$_currentCommand"'
                                      : _lastResponse,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.white.withOpacity(0.9),
                                    height: 1.4,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Premium control buttons with haptic feedback
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Premium Emergency button
                            _buildPremiumButton(
                              icon: Icons.emergency,
                              label: 'Emergency',
                              color: const Color(0xFFFF3B71),
                              onTap: () => _speak('Emergency feature coming soon'),
                            ),
                            
                            // Premium Live mode button
                            _buildPremiumButton(
                              icon: _realtimeDescriptionActive ? Icons.stop_circle : Icons.play_circle,
                              label: _realtimeDescriptionActive ? 'Stop Live' : 'Live Mode',
                              color: _realtimeDescriptionActive ? const Color(0xFFFF6B35) : const Color(0xFF00FF41),
                              onTap: _isProcessing ? null : _toggleRealtimeDescription,
                              isActive: _realtimeDescriptionActive,
                            ),
                            
                            // Premium Describe button
                            _buildPremiumButton(
                              icon: Icons.remove_red_eye_rounded,
                              label: 'Describe',
                              color: const Color(0xFF00D2FF),
                              onTap: _isProcessing ? null : _describeScene,
                              isPrimary: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Enhanced starry background painter for premium look
class EnhancedStarryBackgroundPainter extends CustomPainter {
  final double animationValue;

  EnhancedStarryBackgroundPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42); // Fixed seed for consistent stars
    
    // Create multiple layers of stars with different colors and sizes
    final starLayers = [
      {'count': 60, 'color': const Color(0xFF00FFFF), 'size': 1.5, 'opacity': 0.6},
      {'count': 40, 'color': const Color(0xFF8A2BE2), 'size': 1.0, 'opacity': 0.4},
      {'count': 80, 'color': const Color(0xFF00D2FF), 'size': 0.8, 'opacity': 0.8},
    ];
    
    for (final layer in starLayers) {
      final paint = Paint();
      final count = layer['count'] as int;
      final color = layer['color'] as Color;
      final starSize = layer['size'] as double;
      final baseOpacity = layer['opacity'] as double;
      
      for (int i = 0; i < count; i++) {
        final x = random.nextDouble() * size.width;
        final y = random.nextDouble() * size.height;
        final twinkle = (math.sin(animationValue * 2 * math.pi + i * 0.5) + 1) / 2;
        final pulseSpeed = (math.sin(animationValue * math.pi + i * 0.3) + 1) / 2;
        
        paint.color = color.withOpacity(baseOpacity * (0.3 + twinkle * 0.7));
        
        // Create starburst effect
        final radius = starSize + (twinkle * pulseSpeed * 0.5);
        canvas.drawCircle(Offset(x, y), radius, paint);
        
        // Add subtle glow
        paint.color = color.withOpacity(baseOpacity * 0.2);
        canvas.drawCircle(Offset(x, y), radius * 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Floating particles painter for ambient effect
class FloatingParticlesPainter extends CustomPainter {
  final double animationValue;

  FloatingParticlesPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final random = math.Random(123); // Different seed for particles
    
    // Create floating light particles
    for (int i = 0; i < 25; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      
      // Floating motion
      final floatX = baseX + math.sin(animationValue * 2 * math.pi + i * 0.4) * 20;
      final floatY = baseY + math.cos(animationValue * 1.5 * math.pi + i * 0.6) * 15;
      
      final opacity = (math.sin(animationValue * 3 * math.pi + i * 0.8) + 1) / 4;
      
      // Gradient particles
      final gradient = RadialGradient(
        colors: [
          const Color(0xFF00FFFF).withOpacity(opacity * 0.6),
          Colors.transparent,
        ],
      );
      
      final rect = Rect.fromCircle(center: Offset(floatX, floatY), radius: 8);
      paint.shader = gradient.createShader(rect);
      
      canvas.drawCircle(Offset(floatX, floatY), 8, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}