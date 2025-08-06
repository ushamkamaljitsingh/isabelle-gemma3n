import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import '../services/gemma_inference_service.dart';
import '../utils/core_utils.dart';

class ObjectDescriber {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  GemmaInferenceService? _gemmaService;
  
  bool get isInitialized => _isInitialized;
  CameraController? get cameraController => _cameraController;
  
  void setGemmaService(GemmaInferenceService service) {
    _gemmaService = service;
  }
  
  Future<void> initialize() async {
    try {
      Logger.info('Initializing Object Describer...');
      
      // Get available cameras
      _cameras = await availableCameras();
      
      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('No cameras available');
      }
      
      // Use back camera (index 0) for scene description
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
      
      // Initialize camera controller with explicit image capture configuration
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium, // Balance between quality and speed
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg, // Explicit JPEG format for photos
      );
      
      await _cameraController!.initialize();
      
      // Ensure camera is ready for both preview and photo capture
      if (_cameraController!.value.isInitialized) {
        // Wait for camera to be fully ready
        await Future.delayed(const Duration(milliseconds: 1000));
        
        Logger.info('Camera initialized and ready for photo capture');
        
        _isInitialized = true;
        Logger.info('Camera ready for both preview and photo capture');
      } else {
        throw Exception('Camera failed to initialize properly');
      }
      
      Logger.info('Object Describer initialized successfully');
      
    } catch (e) {
      Logger.error('Failed to initialize Object Describer: $e');
      throw Exception('Camera initialization failed: ${e.toString()}');
    }
  }
  
  /// Main method for describing current scene using AI vision
  Future<String> describeCurrentScene() async {
    if (!_isInitialized || _cameraController == null) {
      throw Exception('Object Describer not initialized');
    }
    
    try {
      Logger.info('🎯 Starting AI vision analysis...');
      
      // Step 1: Capture photo with error handling
      Logger.info('📸 Capturing photo...');
      
      // Ensure camera is ready for photo capture
      if (!_cameraController!.value.isInitialized) {
        throw Exception('Camera not initialized for photo capture');
      }
      
      final XFile image = await _cameraController!.takePicture();
      final Uint8List imageBytes = await image.readAsBytes();
      
      Logger.info('✅ Photo captured successfully');
      Logger.info('  - Image size: ${imageBytes.length} bytes');
      Logger.info('  - Checking Gemma availability...');
      
      // Step 2: Process with Gemma 3n service
      if (_gemmaService?.isInitialized != true) {
        await File(image.path).delete();
        throw Exception('AI vision system not ready. Please wait for model to load.');
      }
      
      try {
        Logger.info('🤖 Processing with Gemma 3n AI...');
        
        // Use Gemma service for AI processing
        final description = await _gemmaService!.processImageWithPrompt(
          imageBytes,
          'You are Isabelle, an AI assistant for blind users. Analyze this image and describe what you see clearly and helpfully. Focus on: objects and people in the scene, their locations and relationships, colors and shapes, any text or signs visible, and overall scene context. Be concise but descriptive.'
        );
        
        // Clean up temporary file
        await File(image.path).delete();
        
        if (description.trim().isEmpty) {
          throw Exception('AI returned empty description');
        }
        
        Logger.info('✅ AI vision analysis completed successfully');
        Logger.info('  - Description length: ${description.length} characters');
        
        return description;
        
      } catch (aiError) {
        Logger.error('❌ AI processing failed: $aiError');
        await File(image.path).delete();
        throw Exception('AI vision analysis failed: ${aiError.toString()}');
      }
      
    } catch (e) {
      Logger.error('❌ Scene description failed: $e');
      
      // Provide specific error messages for different failure types
      if (e.toString().contains('Camera')) {
        throw Exception('Camera error: Unable to take photo. Please check camera permissions and try again.');
      } else if (e.toString().contains('AI') || e.toString().contains('Gemma')) {
        throw Exception('AI vision error: ${e.toString()}');
      } else {
        throw Exception('Vision system error: ${e.toString()}');
      }
    }
  }
  
  /// Dispose resources
  void dispose() {
    try {
      _cameraController?.dispose();
      Logger.info('Object Describer disposed');
    } catch (e) {
      Logger.error('Error disposing Object Describer: $e');
    }
  }
}