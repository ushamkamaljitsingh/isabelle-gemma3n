import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/gemma_output.dart';
import '../utils/core_utils.dart';
import '../core/constants.dart';
import 'package:path_provider/path_provider.dart';

class GemmaInitializationException implements Exception {
  final String message;
  const GemmaInitializationException(this.message);
  
  @override
  String toString() => 'GemmaInitializationException: $message';
}

class GemmaInferenceService extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('gemma_inference');
  
  bool _isInitialized = false;
  bool _isProcessing = false;
  String _currentModelPath = '';
  
  // Performance tracking
  int _totalInferences = 0;
  double _averageLatency = 0.0;
  List<double> _latencyHistory = [];
  int _tokensPerSecond = 0;
  
  // Model state
  Map<String, dynamic> _modelInfo = {};
  Map<String, dynamic> _deviceCapabilities = {};
  
  // Error tracking
  String? _lastError;
  int _errorCount = 0;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isProcessing => _isProcessing;
  int get totalInferences => _totalInferences;
  double get averageLatency => _averageLatency;
  int get tokensPerSecond => _tokensPerSecond;
  String get currentModelPath => _currentModelPath;
  Map<String, dynamic> get modelInfo => Map.unmodifiable(_modelInfo);
  Map<String, dynamic> get deviceCapabilities => Map.unmodifiable(_deviceCapabilities);
  String? get lastError => _lastError;
  int get errorCount => _errorCount;

  Future<bool> initialize() async {
    final initStopwatch = Stopwatch()..start();
    
    Logger.info('=== GEMMA INITIALIZATION START ===');
    Logger.info('🧠 Starting Gemma 3n E4B Multimodal initialization...');
    
    if (_isInitialized) {
      Logger.info('✅ Gemma service already initialized');
      Logger.info('⚡ Initialization completed in ${initStopwatch.elapsedMilliseconds}ms (already initialized)');
      return true;
    }
    
    try {
      Logger.info('🔍 Step 1: Assessing device capabilities...');
      final capabilitiesStopwatch = Stopwatch()..start();
      
      // Get device capabilities first
      _deviceCapabilities = await _assessDeviceCapabilities();
      Logger.info('⚡ Device capabilities assessed in ${capabilitiesStopwatch.elapsedMilliseconds}ms');
      Logger.info('=== DEVICE CAPABILITIES ===');
      Logger.info('📱 Total RAM: ${_deviceCapabilities["totalRAM"]}MB');
      Logger.info('💾 Available RAM: ${_deviceCapabilities["availableRAM"]}MB');
      Logger.info('🎮 Has GPU: ${_deviceCapabilities["hasGPU"]}');
      Logger.info('🔋 Battery Level: ${_deviceCapabilities["batteryLevel"]}');
      Logger.info('📱 Device Model: ${_deviceCapabilities["deviceModel"]}');
      Logger.info('⚙️ CPU ABI: ${_deviceCapabilities["cpuAbi"]}');
      Logger.info('✅ Meets Min RAM: ${_deviceCapabilities["meetsMinimumRAM"]}');
      Logger.info('✅ Meets Rec RAM: ${_deviceCapabilities["meetsRecommendedRAM"]}');
      
      // Check device compatibility
      Logger.info('🔍 Step 2: Checking device compatibility...');
      if (!_isDeviceCompatible()) {
        Logger.error('❌ Device not compatible with Gemma 3n requirements');
        throw Exception('Device not compatible with Gemma 3n requirements');
      }
      Logger.info('✅ Device compatibility check passed');
      
      // Check if we can skip initialization (fast path)
      Logger.info('🔍 Step 3: Checking initialization cache...');
      final canSkipInit = await _canSkipInitialization();
      if (canSkipInit) {
        Logger.info('🚀 FAST PATH: Skipping full initialization - using cached state');
        
        // Quick initialization - just verify model is accessible
        // Get model path
        final appSupportDir = await getApplicationSupportDirectory();
        _currentModelPath = '${appSupportDir.path}/isabelle_models/${AppConstants.modelFileName}';
        
        try {
          // Quick connectivity test to native code
          final testResult = await _channel.invokeMethod('testConnection');
          if (testResult == true) {
            _isInitialized = true;
            Logger.info('⚡ ULTRA-FAST initialization completed in ${initStopwatch.elapsedMilliseconds}ms (cached)');
            await _saveCacheState();
            return true;
          } else {
            Logger.warning('⚠️ Cache test failed, falling back to full initialization');
          }
        } catch (e) {
          Logger.warning('⚠️ Cache validation failed: $e, falling back to full initialization');
        }
      }
      
      // Ensure model is ready for use
      Logger.info('🔍 Step 4: Ensuring model is ready for full initialization...');
      final modelPathStopwatch = Stopwatch()..start();
      // Get model path
      final appSupportDir = await getApplicationSupportDirectory();
      _currentModelPath = '${appSupportDir.path}/isabelle_models/${AppConstants.modelFileName}';
      Logger.info('⚡ Model ready in ${modelPathStopwatch.elapsedMilliseconds}ms');
      Logger.info('📍 Model path: $_currentModelPath');
      
      // Verify model exists and is valid
      Logger.info('🔍 Step 4: Verifying model file...');
      final modelFile = File(_currentModelPath);
      
      if (!await modelFile.exists()) {
        Logger.error('❌ Model file not found at: $_currentModelPath');
        throw Exception('Model file not found at: $_currentModelPath');
      }
      
      final fileSizeBytes = await modelFile.length();
      final fileSizeMB = fileSizeBytes / (1024 * 1024);
      final fileSizeGB = fileSizeBytes / (1024 * 1024 * 1024);
      
      Logger.info('✅ Model file found');
      Logger.info('📏 Model file size: ${fileSizeMB.toStringAsFixed(1)}MB (${fileSizeGB.toStringAsFixed(2)}GB)');
      
      // Accept download if it's at least 2.8GB (consistent with downloader service)
      if (fileSizeMB < 2800) {
        Logger.error('❌ Model file too small: ${fileSizeMB}MB (minimum 2800MB required)');
        throw Exception('Model file appears to be incomplete: ${fileSizeMB}MB (minimum 2800MB required)');
      }
      
      Logger.info('✅ Model file size validation passed');
      
      // Get optimized settings for this device
      Logger.info('🔍 Step 5: Calculating optimized settings...');
      final settings = _getOptimizedSettings();
      Logger.info('=== OPTIMIZED SETTINGS ===');
      Logger.info('🎯 Max Tokens: ${settings['maxTokens']}');
      Logger.info('🌡️ Temperature: ${settings['temperature']}');
      Logger.info('🔝 Top K: ${settings['topK']}');
      Logger.info('👁️ Enable Vision: ${settings['enableVision']}');
      Logger.info('🎮 Enable GPU: ${settings['enableGPU']}');
      Logger.info('🎲 Random Seed: ${settings['randomSeed']}');
      
      // Initialize MediaPipe LLM
      Logger.info('🔄 Step 6: Initializing Gemma 3n E4B with MediaPipe...');
      final channelStopwatch = Stopwatch()..start();
      
      final initParams = {
        'modelPath': _currentModelPath,
        'maxTokens': settings['maxTokens'],
        'temperature': settings['temperature'],
        'topK': settings['topK'],
        'topP': settings['topP'], // Add topP for better generation
        'enableVision': settings['enableVision'],
        'randomSeed': settings['randomSeed'],
        'enablePLE': true,
        'enableKVCacheSharing': true,
        'enableMatFormer': true,
        'enableGPU': settings['enableGPU'],
        'effectiveParameterSize': 'E4B',
        'quantization': 'INT4',
        'preferredBackend': settings['enableGPU'] ? 'GPU' : 'CPU', // Match Google's approach
        'maxNumImages': 3, // E4B supports multiple images
        'enableVisionModality': settings['enableVision'], // Google's parameter name
      };
      
      Logger.info('🔄 Calling Android initializeGemma3n with params:');
      Logger.info('  ModelPath: $_currentModelPath');
      Logger.info('  MaxTokens: ${initParams['maxTokens']}');
      Logger.info('  Temperature: ${initParams['temperature']}');
      Logger.info('  TopK: ${initParams['topK']}');
      Logger.info('  EnableVision: ${initParams['enableVision']}');
      Logger.info('  EnablePLE: ${initParams['enablePLE']}');
      Logger.info('  EnableKVCache: ${initParams['enableKVCacheSharing']}');
      Logger.info('  EnableGPU: ${initParams['enableGPU']}');
      
      // Add timeout to prevent hanging
      dynamic result;
      try {
        Logger.info('⏱️ Starting Android initialization with 5 minute timeout...');
        result = await _channel.invokeMethod('initializeGemma3n', initParams)
            .timeout(
              const Duration(minutes: 5),
              onTimeout: () {
                throw TimeoutException('Gemma initialization timed out after 5 minutes', const Duration(minutes: 5));
              }
            );
        
        Logger.info('⚡ Android initialization call completed in ${channelStopwatch.elapsedMilliseconds}ms');
        Logger.info('📋 Android initialization response: $result');
        
      } catch (e) {
        Logger.error('❌ Android initialization failed: $e');
        Logger.error('⏱️ Total time elapsed: ${channelStopwatch.elapsedMilliseconds}ms');
        
        if (e is TimeoutException) {
          Logger.error('🕐 TIMEOUT: Gemma initialization took longer than 5 minutes');
          Logger.error('💡 This might indicate:');
          Logger.error('   - Model file corruption');
          Logger.error('   - Insufficient device memory');
          Logger.error('   - Android native code deadlock');
          Logger.error('   - Device CPU/GPU issues');
        }
        
        _lastError = e.toString();
        _isInitialized = false;
        throw GemmaInitializationException('Failed to initialize Gemma: $e');
      }
      
      Logger.info('🔍 Step 7: Validating initialization response...');
      Logger.info('📋 Result type: ${result.runtimeType}');
      Logger.info('📋 Result value: $result');
      
      // Defensive handling: accept both boolean true and Map with status=success
      bool initSuccess = false;
      if (result == true) {
        // Legacy boolean response
        Logger.info('✅ Received legacy boolean success response');
        initSuccess = true;
      } else if (result != null && result is Map && result['status'] == 'success') {
        // New Map response format
        Logger.info('✅ Received Map success response');
        initSuccess = true;
      }
      
      if (initSuccess) {
        Logger.info('✅ Android initialization successful');
        
        // Handle modelInfo based on response type
        if (result is Map) {
          _modelInfo = Map<String, dynamic>.from(result);
        } else {
          // Boolean response - create basic model info
          _modelInfo = {
            'status': 'success',
            'modelSizeMB': 4400,  // Approximate E4B size
            'architecture': 'Gemma 3n E4B',
            'quantization': 'INT4',
            'pleEnabled': true,
            'kvCacheEnabled': true,
            'gpuEnabled': true,
          };
        }
        _isInitialized = true;
        _lastError = null;
        
        // Save cache state for future fast startup
        await _saveCacheState();
        
        Logger.info('=== INITIALIZATION SUCCESS ===');
        Logger.info('📊 Model Info:');
        Logger.info('  Model Size: ${_modelInfo['modelSizeMB']}MB');
        Logger.info('  Memory Footprint: ${_modelInfo['memoryFootprintMB']}MB');
        Logger.info('  Architecture: ${_modelInfo['architecture']}');
        Logger.info('  Quantization: ${_modelInfo['quantization']}');
        Logger.info('  PLE Enabled: ${_modelInfo['pleEnabled']}');
        Logger.info('  KV Cache Enabled: ${_modelInfo['kvCacheEnabled']}');
        Logger.info('  GPU Enabled: ${_modelInfo['gpuEnabled']}');
        Logger.info('  Effective Parameters: ${_modelInfo['effectiveParameters']}');
        Logger.info('  Device Compatible: ${_modelInfo['deviceCompatible']}');
        Logger.info('  Recommended Device: ${_modelInfo['recommendedDevice']}');
        
        Logger.info('✅ Gemma 3n E4B Multimodal initialized successfully');
        Logger.info('⚡ Total initialization time: ${initStopwatch.elapsedMilliseconds}ms');
        Logger.info('=== GEMMA INITIALIZATION END ===');
        
        notifyListeners();
        return true;
      } else {
        Logger.error('❌ Android initialization failed');
        Logger.error('Response: $result');
        final errorMsg = result?['message'] ?? 'Unknown error';
        Logger.error('Error message: $errorMsg');
        throw Exception('Initialization failed: $errorMsg');
      }
      
    } catch (e, stackTrace) {
      Logger.error('❌ Failed to initialize Gemma 3n E4B Multimodal: $e');
      Logger.error('Stack trace: $stackTrace');
      Logger.info('⚡ Initialization failed after ${initStopwatch.elapsedMilliseconds}ms');
      Logger.info('=== GEMMA INITIALIZATION END (FAILED) ===');
      
      _lastError = e.toString();
      _errorCount++;
      _isInitialized = false;
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>> _assessDeviceCapabilities() async {
    try {
      final deviceInfo = await _channel.invokeMethod('getDeviceCapabilities');
      return Map<String, dynamic>.from(deviceInfo);
    } catch (e) {
      Logger.warning('Could not assess device capabilities: $e');
      return {
        'totalRAM': 8192,
        'availableRAM': 4096,
        'hasGPU': true,
        'batteryLevel': 1.0,
        'isLowBattery': false,
        'androidVersion': 30,
        'deviceModel': 'Unknown Device',
        'cpuAbi': 'arm64-v8a',
        'meetsMinimumRAM': true,
        'meetsRecommendedRAM': true,
      };
    }
  }

  bool _isDeviceCompatible() {
    final totalRAM = _deviceCapabilities['totalRAM'] as int? ?? 0;
    final meetsMinRAM = _deviceCapabilities['meetsMinimumRAM'] as bool? ?? false;
    final cpuAbi = _deviceCapabilities['cpuAbi'] as String? ?? '';
    
    if (!meetsMinRAM || totalRAM < 4096) {
      Logger.error('Insufficient RAM: ${totalRAM}MB (minimum 4096MB required)');
      return false;
    }
    
    if (!cpuAbi.contains('64')) {
      Logger.error('64-bit CPU required, found: $cpuAbi');
      return false;
    }
    
    return true;
  }

  Map<String, dynamic> _getOptimizedSettings() {
    final hasHighMemory = (_deviceCapabilities['totalRAM'] as int? ?? 0) >= 6144;
    final hasGPU = _deviceCapabilities['hasGPU'] as bool? ?? true;
    final isLowBattery = _deviceCapabilities['isLowBattery'] as bool? ?? false;
    final availableRAM = (_deviceCapabilities['availableRAM'] as int? ?? 0);
    
    // Based on Google's Gallery app settings for Gemma 3n E4B Multimodal
    return {
      'maxTokens': hasHighMemory ? 4096 : 2048, // Google uses 4096 for E4B
      'temperature': 1.0, // Google's default for E4B
      'topK': 64, // Google's optimized value for E4B
      'topP': 0.95, // Google's default (add this for better generation)
      'enableVision': hasGPU && !isLowBattery && availableRAM > 2048,
      'enableGPU': hasGPU && !isLowBattery,
      'randomSeed': 42,
      'accelerators': hasGPU ? 'cpu,gpu' : 'cpu', // Match Google's format
    };
  }

  Future<String> enhanceTranscription(String rawText) async {
    if (!_isInitialized) {
      Logger.warning('Gemma not initialized, attempting to initialize...');
      final success = await initialize();
      if (!success) {
        Logger.error('Failed to initialize Gemma for transcription enhancement');
        return rawText; // Return original text if enhancement fails
      }
    }
    
    if (rawText.trim().isEmpty) return rawText;
    
    final stopwatch = Stopwatch()..start();
    _isProcessing = true;
    notifyListeners();
    
    try {
      final prompt = _buildTranscriptionPrompt(rawText);
      final result = await _generateWithGemma3n(prompt);
      
      final latencyMs = stopwatch.elapsedMilliseconds.toDouble();
      _trackPerformance(latencyMs, result.tokens.length);
      
      Logger.info('Transcription enhanced in ${latencyMs.toStringAsFixed(0)}ms');
      
      final enhancedText = _extractEnhancedText(result.text, rawText);
      return enhancedText;
      
    } catch (e) {
      Logger.error('Transcription enhancement failed: $e');
      _lastError = 'Transcription enhancement failed: $e';
      _errorCount++;
      return rawText; // Return original on error
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<String> processTextQuery(String query) async {
    Logger.info('=== GEMMA TEXT QUERY PROCESSING ===');
    Logger.info('🧠 Received text query: "${query.substring(0, query.length.clamp(0, 100))}..."');
    Logger.info('📏 Query length: ${query.length} characters');
    
    if (!_isInitialized) {
      Logger.warning('⚠️ Gemma not initialized, attempting to initialize...');
      final initStopwatch = Stopwatch()..start();
      final success = await initialize();
      Logger.info('⚡ Emergency initialization took ${initStopwatch.elapsedMilliseconds}ms');
      
      if (!success) {
        Logger.error('❌ Gemma initialization failed for text query');
        throw Exception('Gemma inference service not available');
      }
      Logger.info('✅ Emergency initialization successful');
    }
    
    final stopwatch = Stopwatch()..start();
    Logger.info('🔄 Starting inference process...');
    Logger.info('📊 Processing state updated to true');
    
    _isProcessing = true;
    notifyListeners();
    
    try {
      Logger.info('🔄 Step 1: Building query prompt...');
      final promptStopwatch = Stopwatch()..start();
      final prompt = _buildQueryPrompt(query);
      Logger.info('⚡ Prompt built in ${promptStopwatch.elapsedMilliseconds}ms');
      Logger.info('📝 Final prompt length: ${prompt.length} characters');
      Logger.debug('🔍 Prompt preview: "${prompt.substring(0, prompt.length.clamp(0, 200))}..."');
      
      Logger.info('🔄 Step 2: Calling Gemma 3n inference...');
      final inferenceStopwatch = Stopwatch()..start();
      final result = await _generateWithGemma3n(prompt);
      Logger.info('⚡ Gemma inference completed in ${inferenceStopwatch.elapsedMilliseconds}ms');
      
      Logger.info('📊 Inference result:');
      Logger.info('  Response length: ${result.text.length} characters');
      Logger.info('  Token count: ${result.tokens.length}');
      Logger.info('  Model: ${result.modelUsed}');
      Logger.info('  Confidence: ${result.confidence}');
      
      final latencyMs = stopwatch.elapsedMilliseconds.toDouble();
      _trackPerformance(latencyMs, result.tokens.length);
      
      Logger.info('🔄 Step 3: Extracting response text...');
      final extractedResponse = _extractResponseText(result.text);
      Logger.info('📤 Final response length: ${extractedResponse.length} characters');
      Logger.info('📝 Response preview: "${extractedResponse.substring(0, extractedResponse.length.clamp(0, 100))}..."');
      
      Logger.info('✅ Query processed successfully in ${latencyMs.toStringAsFixed(0)}ms');
      Logger.info('🎯 Performance: ${result.tokens.length} tokens in ${latencyMs.toStringAsFixed(0)}ms');
      
      return extractedResponse;
      
    } catch (e, stackTrace) {
      Logger.error('❌ GEMMA TEXT QUERY FAILED: $e');
      Logger.error('🔍 Stack trace: $stackTrace');
      Logger.error('📝 Query was: "${query.substring(0, query.length.clamp(0, 200))}..."');
      
      _lastError = 'Query processing failed: $e';
      _errorCount++;
      
      Logger.error('🔄 Re-throwing error - no fallback responses for accessibility users');
      throw Exception('Text query processing failed: $e');
    } finally {
      _isProcessing = false;
      notifyListeners();
      Logger.info('📊 Processing state updated to false');
      Logger.info('=== GEMMA TEXT QUERY COMPLETE ===');
    }
  }

  Future<String> processVisionQuery(String query, String imagePath) async {
    if (!_isInitialized) {
      Logger.warning('Gemma not initialized, attempting to initialize...');
      final success = await initialize();
      if (!success) {
        throw Exception('Gemma inference service not available');
      }
    }
    
    final stopwatch = Stopwatch()..start();
    _isProcessing = true;
    notifyListeners();
    
    try {
      final prompt = _buildVisionPrompt(query);
      final result = await _generateWithVision(prompt, imagePath);
      
      final latencyMs = stopwatch.elapsedMilliseconds.toDouble();
      _trackPerformance(latencyMs, result.tokens.length);
      
      Logger.info('Vision query processed in ${latencyMs.toStringAsFixed(0)}ms');
      
      return _extractResponseText(result.text);
      
    } catch (e) {
      Logger.error('Vision query failed: $e');
      _lastError = 'Vision processing failed: $e';
      _errorCount++;
      throw Exception('Vision processing failed: $e');
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Process image with prompt using E4B multimodal capabilities
  Future<String> processImageWithPrompt(Uint8List imageData, String prompt) async {
    if (!_isInitialized) {
      Logger.warning('Gemma not initialized, attempting to initialize...');
      final success = await initialize();
      if (!success) {
        throw Exception('Gemma inference service not available');
      }
    }
    
    final stopwatch = Stopwatch()..start();
    Logger.info('=== E4B MULTIMODAL IMAGE PROCESSING START ===');
    Logger.info('🖼️ Processing image data: ${imageData.length} bytes');
    Logger.info('📝 Prompt: ${prompt.substring(0, prompt.length.clamp(0, 100))}...');
    
    _isProcessing = true;
    notifyListeners();
    
    try {
      final result = await _generateWithImageData(prompt, imageData);
      
      final latencyMs = stopwatch.elapsedMilliseconds.toDouble();
      _trackPerformance(latencyMs, result.tokens.length);
      
      Logger.info('✅ E4B multimodal processing completed in ${latencyMs.toStringAsFixed(0)}ms');
      Logger.info('📊 Response length: ${result.text.length} characters');
      
      return _extractResponseText(result.text);
      
    } catch (e) {
      Logger.error('❌ E4B multimodal processing failed: $e');
      _lastError = 'Multimodal processing failed: $e';
      _errorCount++;
      throw Exception('E4B multimodal processing failed: $e');
    } finally {
      _isProcessing = false;
      notifyListeners();
      Logger.info('=== E4B MULTIMODAL IMAGE PROCESSING END ===');
    }
  }
  
  /// Main method for ISABELLE's "what's in front of me" functionality
  /// This is what gets called when user says "Isabelle, what is in front of me?"
  Future<String> describeScene(String imagePath) async {
    final sceneStopwatch = Stopwatch()..start();
    
    Logger.info('=== ISABELLE SCENE DESCRIPTION START ===');
    Logger.info('👁️ Processing "what\'s in front of me" request');
    Logger.info('📸 Image path: $imagePath');
    
    if (!_isInitialized) {
      Logger.warning('⚠️ Gemma not initialized, attempting to initialize...');
      final initStopwatch = Stopwatch()..start();
      final success = await initialize();
      Logger.info('⚡ Initialization took ${initStopwatch.elapsedMilliseconds}ms');
      
      if (!success) {
        Logger.error('❌ Gemma initialization failed');
        throw Exception('Gemma inference service not available');
      }
      Logger.info('✅ Gemma initialized successfully');
    }
    
    Logger.info('🔄 Step 1: Starting scene description process...');
    _isProcessing = true;
    notifyListeners();
    
    try {
      // This is the auto-generated prompt that ISABELLE uses
      Logger.info('🔄 Step 2: Building scene description prompt...');
      final prompt = _buildSceneDescriptionPrompt();
      Logger.info('📝 Prompt length: ${prompt.length} characters');
      Logger.info('📝 Prompt preview: ${prompt.substring(0, prompt.length.clamp(0, 100))}...');
      
      Logger.info('🔄 Step 3: Generating vision response...');
      final visionStopwatch = Stopwatch()..start();
      final result = await _generateWithVision(prompt, imagePath);
      Logger.info('⚡ Vision processing completed in ${visionStopwatch.elapsedMilliseconds}ms');
      
      final latencyMs = sceneStopwatch.elapsedMilliseconds.toDouble();
      _trackPerformance(latencyMs, result.tokens.length);
      
      Logger.info('🔄 Step 4: Extracting scene description...');
      final description = _extractSceneDescription(result.text);
      
      Logger.info('=== SCENE DESCRIPTION SUCCESS ===');
      Logger.info('📊 Performance Stats:');
      Logger.info('  Total time: ${latencyMs.toStringAsFixed(0)}ms');
      Logger.info('  Tokens generated: ${result.tokens.length}');
      Logger.info('  Characters in response: ${description.length}');
      Logger.info('  Response preview: ${description.substring(0, description.length.clamp(0, 100))}...');
      Logger.info('⚡ Scene description completed in ${latencyMs.toStringAsFixed(0)}ms');
      Logger.info('=== ISABELLE SCENE DESCRIPTION END ===');
      
      return description;
      
    } catch (e, stackTrace) {
      Logger.error('❌ Scene description failed: $e');
      Logger.error('Stack trace: $stackTrace');
      Logger.info('⚡ Scene description failed after ${sceneStopwatch.elapsedMilliseconds}ms');
      Logger.info('=== ISABELLE SCENE DESCRIPTION END (FAILED) ===');
      
      _lastError = 'Scene description failed: $e';
      _errorCount++;
      throw Exception('Scene description failed: $e');
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<GemmaOutput> _generateWithGemma3n(String prompt) async {
    try {
      final result = await _channel.invokeMethod('generateWithGemma3n', {
        'prompt': prompt,
        'usePLE': _modelInfo['pleEnabled'] ?? true,
        'useKVCache': _modelInfo['kvCacheEnabled'] ?? true,
        'useGPU': _modelInfo['gpuEnabled'] ?? false,
      });
      
      return _parseGemmaOutput(result);
      
    } catch (e) {
      throw Exception('Gemma 3n generation failed: $e');
    }
  }

  Future<GemmaOutput> _generateWithVision(String prompt, String imagePath) async {
    final visionStopwatch = Stopwatch()..start();
    
    Logger.info('=== VISION GENERATION START ===');
    Logger.info('👁️ Starting vision generation...');
    Logger.info('📸 Image path: $imagePath');
    Logger.info('📝 Prompt length: ${prompt.length} characters');
    
    try {
      Logger.info('🔄 Step 1: Calling Android generateWithVision...');
      
      final params = {
        'prompt': prompt,
        'imagePath': imagePath,
      };
      
      Logger.info('📋 Vision params:');
      Logger.info('  Image path: $imagePath');
      Logger.info('  Prompt preview: ${prompt.substring(0, prompt.length.clamp(0, 100))}...');
      
      final channelStopwatch = Stopwatch()..start();
      final result = await _channel.invokeMethod('generateWithVision', params);
      Logger.info('⚡ Android vision call completed in ${channelStopwatch.elapsedMilliseconds}ms');
      
      Logger.info('🔄 Step 2: Parsing vision response...');
      final output = _parseGemmaOutput(result);
      
      Logger.info('=== VISION GENERATION SUCCESS ===');
      Logger.info('📊 Vision Stats:');
      Logger.info('  Total time: ${visionStopwatch.elapsedMilliseconds}ms');
      Logger.info('  Response length: ${output.text.length} characters');
      Logger.info('  Token count: ${output.tokens.length}');
      Logger.info('  Confidence: ${output.confidence}');
      Logger.info('  Response preview: ${output.text.substring(0, output.text.length.clamp(0, 100))}...');
      Logger.info('=== VISION GENERATION END ===');
      
      return output;
      
    } catch (e, stackTrace) {
      Logger.error('❌ Vision generation failed: $e');
      Logger.error('Stack trace: $stackTrace');
      Logger.info('⚡ Vision generation failed after ${visionStopwatch.elapsedMilliseconds}ms');
      Logger.info('=== VISION GENERATION END (FAILED) ===');
      throw Exception('Gemma 3n vision generation failed: $e');
    }
  }

  /// Generate with actual image data (not path) for E4B multimodal
  Future<GemmaOutput> _generateWithImageData(String prompt, Uint8List imageData) async {
    final visionStopwatch = Stopwatch()..start();
    
    Logger.info('=== E4B MULTIMODAL GENERATION START ===');
    Logger.info('🖼️ Starting E4B multimodal generation...');
    Logger.info('📊 Image data size: ${imageData.length} bytes');
    Logger.info('📝 Prompt length: ${prompt.length} characters');
    
    try {
      Logger.info('🔄 Step 1: Calling Android generateWithImageData...');
      
      final params = {
        'prompt': prompt,
        'imageData': imageData,
        'enableMultimodal': true,
        'modelType': 'E4B',
      };
      
      Logger.info('📋 E4B Multimodal params:');
      Logger.info('  Image data size: ${imageData.length} bytes');
      Logger.info('  Enable multimodal: true');
      Logger.info('  Model type: E4B');
      Logger.info('  Prompt preview: ${prompt.substring(0, prompt.length.clamp(0, 100))}...');
      
      final channelStopwatch = Stopwatch()..start();
      final result = await _channel.invokeMethod('generateWithImageData', params);
      Logger.info('⚡ Android E4B multimodal call completed in ${channelStopwatch.elapsedMilliseconds}ms');
      
      Logger.info('🔄 Step 2: Parsing E4B multimodal response...');
      final output = _parseGemmaOutput(result);
      
      Logger.info('=== E4B MULTIMODAL GENERATION SUCCESS ===');
      Logger.info('📊 E4B Multimodal Stats:');
      Logger.info('  Total time: ${visionStopwatch.elapsedMilliseconds}ms');
      Logger.info('  Response length: ${output.text.length} characters');
      Logger.info('  Token count: ${output.tokens.length}');
      Logger.info('  Confidence: ${output.confidence}');
      Logger.info('  Response preview: ${output.text.substring(0, output.text.length.clamp(0, 100))}...');
      Logger.info('=== E4B MULTIMODAL GENERATION END ===');
      
      return output;
      
    } catch (e, stackTrace) {
      Logger.error('❌ E4B multimodal generation failed: $e');
      Logger.error('Stack trace: $stackTrace');
      Logger.info('⚡ E4B multimodal generation failed after ${visionStopwatch.elapsedMilliseconds}ms');
      Logger.info('=== E4B MULTIMODAL GENERATION END (FAILED) ===');
      throw Exception('Gemma 3n E4B multimodal generation failed: $e');
    }
  }

  GemmaOutput _parseGemmaOutput(dynamic result) {
    if (result is Map) {
      final responseText = result['response'] as String? ?? '';
      final metadata = <String, dynamic>{
        'latency': result['latency'] ?? 0,
        'model': result['model'] ?? 'Gemma 3n E4B Multimodal',
        'tokensPerSecond': result['tokensPerSecond'] ?? 0,
        'tokenCount': result['tokenCount'] ?? 0,
        'pleUsed': result['pleUsed'] ?? false,
        'kvCacheUsed': result['kvCacheUsed'] ?? false,
        'gpuUsed': result['gpuUsed'] ?? false,
      };
      
      return GemmaOutput(
        text: responseText,
        confidence: 1.0,
        tokens: responseText.split(' '),
        timestamp: DateTime.now(),
        metadata: metadata,
      );
    } else {
      final responseText = result as String? ?? '';
      return GemmaOutput(
        text: responseText,
        confidence: 1.0,
        tokens: responseText.split(' '),
        timestamp: DateTime.now(),
      );
    }
  }

  void _trackPerformance(double latencyMs, int tokenCount) {
    _totalInferences++;
    _latencyHistory.add(latencyMs);
    
    if (latencyMs > 0) {
      _tokensPerSecond = ((tokenCount / latencyMs) * 1000).round();
    }
    
    // Keep only last 100 measurements
    if (_latencyHistory.length > 100) {
      _latencyHistory.removeAt(0);
    }
    
    _averageLatency = _latencyHistory.reduce((a, b) => a + b) / _latencyHistory.length;
  }

  String _buildTranscriptionPrompt(String rawText) {
    return '''Fix speech transcription errors and improve readability. Keep the meaning intact but correct obvious mistakes:

Raw transcription: "$rawText"

Corrected text:''';
  }

  String _buildQueryPrompt(String query) {
    return '''You are Isabelle, an AI assistant for accessibility. Provide helpful, clear, and concise responses.

User: $query

Isabelle:''';
  }

  String _buildVisionPrompt(String query) {
    return '''You are Isabelle, an AI assistant for blind users. Analyze the provided image and answer the question clearly and descriptively.

Question: $query

Description:''';
  }
  
  /// This is the specific prompt that ISABELLE automatically generates
  /// when the user asks "What's in front of me?"
  String _buildSceneDescriptionPrompt() {
    return '''You are Isabelle, an AI assistant for blind users. Describe what you see in this image clearly and helpfully. Focus on:
- Objects and people in the scene
- Their locations and relationships
- Colors, shapes, and important details
- Any text or signs visible
- Overall scene context

Be concise but descriptive. Speak naturally as if helping a friend understand what's in front of them.

Description:''';
  }

  String _extractEnhancedText(String response, String fallback) {
    final trimmed = response.trim();
    
    // Remove common prompt artifacts using simple string operations
    var cleaned = trimmed;
    
    // Remove prefixes
    if (cleaned.toLowerCase().startsWith('corrected text:')) {
      cleaned = cleaned.substring(15).trim();
    }
    if (cleaned.toLowerCase().startsWith('fixed:')) {
      cleaned = cleaned.substring(6).trim();
    }
    if (cleaned.toLowerCase().startsWith('enhanced:')) {
      cleaned = cleaned.substring(9).trim();
    }
    
    // Remove surrounding quotes using simple replacement
    if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    if (cleaned.startsWith("'") && cleaned.endsWith("'")) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    
    cleaned = cleaned.trim();
    
    // If result is empty or too short, return original
    if (cleaned.isEmpty || cleaned.length < fallback.length * 0.5) {
      return fallback;
    }
    
    return cleaned;
  }

  String _extractResponseText(String response) {
    final trimmed = response.trim();
    
    // Remove common prompt artifacts using simple string operations
    var cleaned = trimmed;
    
    // Remove prefixes
    if (cleaned.toLowerCase().startsWith('isabelle:')) {
      cleaned = cleaned.substring(9).trim();
    }
    if (cleaned.toLowerCase().startsWith('assistant:')) {
      cleaned = cleaned.substring(10).trim();
    }
    if (cleaned.toLowerCase().startsWith('response:')) {
      cleaned = cleaned.substring(9).trim();
    }
    
    // Remove surrounding quotes using simple replacement
    if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    if (cleaned.startsWith("'") && cleaned.endsWith("'")) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    
    cleaned = cleaned.trim();
    
    return cleaned.isNotEmpty ? cleaned : trimmed;
  }
  
  /// Specialized text extraction for scene descriptions
  String _extractSceneDescription(String response) {
    final trimmed = response.trim();
    
    // Remove common prompt artifacts
    var cleaned = trimmed;
    
    // Remove prefixes specific to scene description
    if (cleaned.toLowerCase().startsWith('description:')) {
      cleaned = cleaned.substring(12).trim();
    }
    if (cleaned.toLowerCase().startsWith('i see')) {
      cleaned = cleaned;
    }
    if (cleaned.toLowerCase().startsWith('in this image')) {
      cleaned = cleaned;
    }
    
    // Remove surrounding quotes
    if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    if (cleaned.startsWith("'") && cleaned.endsWith("'")) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    
    cleaned = cleaned.trim();
    
    // Ensure we return something meaningful
    if (cleaned.isEmpty) {
      throw Exception('No meaningful description could be generated from the image analysis');
    }
    
    return cleaned;
  }

  Future<bool> testInference() async {
    if (!_isInitialized) {
      Logger.warning('Cannot test inference - service not initialized');
      return false;
    }
    
    try {
      Logger.info('Testing Gemma inference...');
      final testResponse = await processTextQuery('Hello, are you working?');
      
      if (testResponse.isNotEmpty) {
        Logger.info('Inference test passed: ${testResponse.substring(0, testResponse.length.clamp(0, 50))}...');
        return true;
      } else {
        Logger.error('Inference test failed: empty response');
        return false;
      }
    } catch (e) {
      Logger.error('Inference test failed: $e');
      return false;
    }
  }

  Map<String, dynamic> getPerformanceStats() {
    return {
      'totalInferences': _totalInferences,
      'averageLatency': _averageLatency,
      'tokensPerSecond': _tokensPerSecond,
      'isInitialized': _isInitialized,
      'isProcessing': _isProcessing,
      'currentModelPath': _currentModelPath,
      'errorCount': _errorCount,
      'lastError': _lastError,
      'modelInfo': _modelInfo,
      'deviceCapabilities': _deviceCapabilities,
    };
  }

  Future<Map<String, dynamic>> getDetailedInfo() async {
    try {
      final info = await _channel.invokeMethod('getGemma3nInfo');
      return Map<String, dynamic>.from(info ?? {});
    } catch (e) {
      Logger.error('Failed to get detailed info: $e');
      return {};
    }
  }

  Future<void> reinitialize() async {
    Logger.info('Reinitializing Gemma service...');
    
    if (_isInitialized) {
      await dispose();
    }
    
    _isInitialized = false;
    _currentModelPath = '';
    _modelInfo.clear();
    _lastError = null;
    
    await initialize();
  }

  /// Check if we can skip full initialization by using cached state
  Future<bool> _canSkipInitialization() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();
      
      // Check if we have cache data
      final lastInitSuccess = prefs.getBool('gemma_init_success') ?? false;
      final lastAppVersion = prefs.getString('gemma_init_app_version') ?? '';
      final lastModelPath = prefs.getString('gemma_init_model_path') ?? '';
      final lastInitTime = prefs.getInt('gemma_init_timestamp') ?? 0;
      
      if (!lastInitSuccess) {
        Logger.info('🔍 Cache miss: No previous successful initialization');
        return false;
      }
      
      // Check if app version changed
      if (lastAppVersion != packageInfo.version) {
        Logger.info('🔍 Cache miss: App version changed from $lastAppVersion to ${packageInfo.version}');
        return false;
      }
      
      // Check if model path is the same
      // Get model path
      final appSupportDir = await getApplicationSupportDirectory();
      final currentModelPath = '${appSupportDir.path}/isabelle_models/${AppConstants.modelFileName}';
      if (lastModelPath != currentModelPath) {
        Logger.info('🔍 Cache miss: Model path changed');
        return false;
      }
      
      // Check if model file still exists and hasn't been modified
      final modelFile = File(currentModelPath);
      if (!await modelFile.exists()) {
        Logger.info('🔍 Cache miss: Model file no longer exists');
        return false;
      }
      
      // Check cache age (invalidate after 7 days)
      final now = DateTime.now().millisecondsSinceEpoch;
      final cacheAge = now - lastInitTime;
      final maxCacheAge = 7 * 24 * 60 * 60 * 1000; // 7 days in milliseconds
      
      if (cacheAge > maxCacheAge) {
        Logger.info('🔍 Cache miss: Cache too old (${(cacheAge / (24 * 60 * 60 * 1000)).toStringAsFixed(1)} days)');
        return false;
      }
      
      Logger.info('✅ Cache hit: All conditions met for fast initialization');
      Logger.info('📊 Cache age: ${(cacheAge / (60 * 60 * 1000)).toStringAsFixed(1)} hours');
      return true;
      
    } catch (e) {
      Logger.error('❌ Error checking initialization cache: $e');
      return false;
    }
  }
  
  /// Save successful initialization state to cache
  Future<void> _saveCacheState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();
      
      await prefs.setBool('gemma_init_success', true);
      await prefs.setString('gemma_init_app_version', packageInfo.version);
      await prefs.setString('gemma_init_model_path', _currentModelPath);
      await prefs.setInt('gemma_init_timestamp', DateTime.now().millisecondsSinceEpoch);
      
      Logger.info('💾 Initialization cache saved for future fast startup');
      
    } catch (e) {
      Logger.error('❌ Error saving initialization cache: $e');
    }
  }
  
  /// Clear initialization cache (force full init next time)
  Future<void> _clearCacheState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('gemma_init_success');
      await prefs.remove('gemma_init_app_version');
      await prefs.remove('gemma_init_model_path');
      await prefs.remove('gemma_init_timestamp');
      
      Logger.info('🗑️ Initialization cache cleared');
      
    } catch (e) {
      Logger.error('❌ Error clearing initialization cache: $e');
    }
  }

  @override
  Future<void> dispose() async {
    try {
      if (_isInitialized) {
        await _channel.invokeMethod('disposeGemma3n');
      }
      
      _isInitialized = false;
      _totalInferences = 0;
      _latencyHistory.clear();
      _modelInfo.clear();
      _deviceCapabilities.clear();
      
      Logger.info('Gemma 3n E4B Multimodal service disposed');
    } catch (e) {
      Logger.error('Error disposing Gemma service: $e');
    }
    super.dispose();
  }
}