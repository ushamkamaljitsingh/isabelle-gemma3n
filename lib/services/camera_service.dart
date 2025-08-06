import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import '../core/constants.dart';
import '../utils/core_utils.dart';

class CameraService extends ChangeNotifier {
  // Camera Controller
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isPreviewActive = false;
  bool _isCapturing = false;
  
  // Auto-capture for continuous monitoring
  Timer? _autoCaptureTimer;
  bool _autoCaptureEnabled = false;
  Function(String)? _onImageCaptured;
  int _autoCaptureIntervalMs = 2000;
  
  // Flash and Focus
  FlashMode _flashMode = FlashMode.off;
  FocusMode _focusMode = FocusMode.auto;
  ExposureMode _exposureMode = ExposureMode.auto;
  
  // Statistics
  int _totalCaptured = 0;
  DateTime? _lastCaptureTime;
  List<String> _capturedImagePaths = [];
  
  // Error tracking
  String? _lastError;
  int _errorCount = 0;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isPreviewActive => _isPreviewActive;
  bool get isCapturing => _isCapturing;
  bool get autoCaptureEnabled => _autoCaptureEnabled;
  CameraController? get controller => _controller;
  FlashMode get flashMode => _flashMode;
  FocusMode get focusMode => _focusMode;
  ExposureMode get exposureMode => _exposureMode;
  int get totalCaptured => _totalCaptured;
  DateTime? get lastCaptureTime => _lastCaptureTime;
  List<String> get capturedImagePaths => List.unmodifiable(_capturedImagePaths);
  String? get lastError => _lastError;
  int get errorCount => _errorCount;
  int get autoCaptureIntervalMs => _autoCaptureIntervalMs;

  Future<bool> initialize() async {
    try {
      Logger.info('Initializing Camera Service...');
      
      await _requestCameraPermission();
      
      _cameras = await availableCameras();
      
      if (_cameras.isEmpty) {
        throw Exception('No cameras available on this device');
      }
      
      Logger.info('Found ${_cameras.length} camera(s)');
      for (int i = 0; i < _cameras.length; i++) {
        Logger.info('Camera $i: ${_cameras[i].name} (${_cameras[i].lensDirection})');
      }
      
      // Initialize with back camera (preferred for accessibility features)
      final backCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
      
      await _initializeCamera(backCamera);
      
      _isInitialized = true;
      _lastError = null;
      Logger.info('Camera Service initialized successfully');
      notifyListeners();
      return true;
      
    } catch (e) {
      Logger.error('Failed to initialize Camera Service: $e');
      _lastError = e.toString();
      _errorCount++;
      _isInitialized = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      throw Exception('Camera permission not granted');
    }
    Logger.info('Camera permission granted');
  }

  Future<void> _initializeCamera(CameraDescription camera) async {
    try {
      // Dispose existing controller if any
      await _controller?.dispose();
      
      _controller = CameraController(
        camera,
        ResolutionPreset.medium, // Balance between quality and performance
        enableAudio: false, // No audio needed for accessibility features
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      
      await _controller!.initialize();
      
      // Set initial camera settings
      await _controller!.setFlashMode(_flashMode);
      await _controller!.setFocusMode(_focusMode);
      await _controller!.setExposureMode(_exposureMode);
      
      Logger.info('Camera initialized: ${camera.name} (${_controller!.value.previewSize})');
      
    } catch (e) {
      Logger.error('Failed to initialize camera: $e');
      throw Exception('Camera initialization failed: $e');
    }
  }

  Future<CameraController?> startPreview() async {
    if (!_isInitialized) {
      final success = await initialize();
      if (!success) {
        throw Exception('Failed to initialize camera');
      }
    }
    
    if (_controller == null || !_controller!.value.isInitialized) {
      throw Exception('Camera not properly initialized');
    }
    
    try {
      _isPreviewActive = true;
      notifyListeners();
      
      Logger.info('Camera preview started');
      return _controller;
      
    } catch (e) {
      Logger.error('Failed to start camera preview: $e');
      _isPreviewActive = false;
      _lastError = e.toString();
      _errorCount++;
      notifyListeners();
      return null;
    }
  }

  Future<void> stopPreview() async {
    if (_isPreviewActive) {
      _isPreviewActive = false;
      await stopAutoCapture();
      notifyListeners();
      Logger.info('Camera preview stopped');
    }
  }

  Future<String> captureImage({bool optimize = true}) async {
    if (!_isInitialized || _controller == null || !_controller!.value.isInitialized) {
      throw Exception('Camera not ready for capture');
    }
    
    if (_isCapturing) {
      throw Exception('Capture already in progress');
    }
    
    try {
      _isCapturing = true;
      notifyListeners();
      
      Logger.debug('Capturing image...');
      
      // Capture image
      final XFile image = await _controller!.takePicture();
      
      // Process and optimize image if needed
      String finalPath = image.path;
      if (optimize) {
        finalPath = await _optimizeImage(image.path);
      }
      
      _totalCaptured++;
      _lastCaptureTime = DateTime.now();
      _capturedImagePaths.add(finalPath);
      
      // Limit stored paths to prevent memory issues
      if (_capturedImagePaths.length > 50) {
        final oldPath = _capturedImagePaths.removeAt(0);
        _cleanupOldImage(oldPath);
      }
      
      Logger.info('Image captured: $finalPath (${_totalCaptured} total)');
      notifyListeners();
      
      return finalPath;
      
    } catch (e) {
      Logger.error('Failed to capture image: $e');
      _lastError = e.toString();
      _errorCount++;
      rethrow;
    } finally {
      _isCapturing = false;
      notifyListeners();
    }
  }

  Future<String> _optimizeImage(String originalPath) async {
    try {
      // Read original image
      final bytes = await File(originalPath).readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        Logger.warning('Failed to decode image for optimization');
        return originalPath;
      }
      
      Logger.debug('Original image: ${image.width}x${image.height}');
      
      // Resize if too large
      img.Image processed = image;
      
      if (image.width > AppConstants.MAX_IMAGE_WIDTH || 
          image.height > AppConstants.MAX_IMAGE_HEIGHT) {
        
        final aspectRatio = image.width / image.height;
        int newWidth, newHeight;
        
        if (aspectRatio > 1) {
          // Landscape
          newWidth = AppConstants.MAX_IMAGE_WIDTH;
          newHeight = (AppConstants.MAX_IMAGE_WIDTH / aspectRatio).round();
        } else {
          // Portrait or square
          newHeight = AppConstants.MAX_IMAGE_HEIGHT;
          newWidth = (AppConstants.MAX_IMAGE_HEIGHT * aspectRatio).round();
        }
        
        processed = img.copyResize(
          image,
          width: newWidth,
          height: newHeight,
          interpolation: img.Interpolation.linear,
        );
        
        Logger.debug('Resized to: ${processed.width}x${processed.height}');
      }
      
      // Auto-enhance for better AI processing
      processed = img.adjustColor(processed, contrast: 1.1, brightness: 1.05);
      
      // Save optimized image
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final optimizedPath = '${directory.path}/optimized_$timestamp.jpg';
      
      await File(optimizedPath).writeAsBytes(
        img.encodeJpg(processed, quality: 85),
      );
      
      // Clean up original if it's a temporary file
      if (originalPath.contains('temp') || originalPath.contains('cache')) {
        try {
          await File(originalPath).delete();
        } catch (e) {
          Logger.debug('Could not delete original temp file: $e');
        }
      }
      
      Logger.debug('Image optimized: $optimizedPath');
      return optimizedPath;
      
    } catch (e) {
      Logger.error('Failed to optimize image: $e');
      return originalPath;
    }
  }

  Future<void> startAutoCapture({
    required Function(String) onImageCaptured,
    int intervalMs = 2000,
  }) async {
    if (_autoCaptureEnabled) {
      await stopAutoCapture();
    }
    
    _onImageCaptured = onImageCaptured;
    _autoCaptureEnabled = true;
    _autoCaptureIntervalMs = intervalMs;
    notifyListeners();
    
    Logger.info('Starting auto-capture (${intervalMs}ms interval)');
    
    _autoCaptureTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (timer) async {
        if (!_autoCaptureEnabled || !_isPreviewActive) {
          timer.cancel();
          return;
        }
        
        try {
          final imagePath = await captureImage(optimize: true);
          _onImageCaptured?.call(imagePath);
          Logger.debug('Auto-captured: ${imagePath.split('/').last}');
        } catch (e) {
          Logger.error('Auto-capture failed: $e');
          // Don't stop auto-capture for single failures
        }
      },
    );
    
    Logger.info('Auto-capture started successfully');
  }

  Future<void> stopAutoCapture() async {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _autoCaptureEnabled = false;
    _onImageCaptured = null;
    notifyListeners();
    
    Logger.info('Auto-capture stopped');
  }

  Future<void> switchCamera() async {
    if (_cameras.length < 2) {
      throw Exception('Only one camera available');
    }
    
    final currentCamera = _controller?.description;
    CameraDescription newCamera;
    
    if (currentCamera?.lensDirection == CameraLensDirection.back) {
      newCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
    } else {
      newCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
    }
    
    await _initializeCamera(newCamera);
    
    if (_isPreviewActive) {
      notifyListeners();
    }
    
    Logger.info('Switched to ${newCamera.lensDirection} camera');
  }

  Future<void> setFlashMode(FlashMode mode) async {
    if (_controller == null) {
      Logger.warning('Cannot set flash mode - controller not initialized');
      return;
    }
    
    try {
      await _controller!.setFlashMode(mode);
      _flashMode = mode;
      notifyListeners();
      Logger.info('Flash mode set to: $mode');
    } catch (e) {
      Logger.error('Failed to set flash mode: $e');
      _lastError = e.toString();
      _errorCount++;
    }
  }

  Future<void> setFocusMode(FocusMode mode) async {
    if (_controller == null) {
      Logger.warning('Cannot set focus mode - controller not initialized');
      return;
    }
    
    try {
      await _controller!.setFocusMode(mode);
      _focusMode = mode;
      notifyListeners();
      Logger.info('Focus mode set to: $mode');
    } catch (e) {
      Logger.error('Failed to set focus mode: $e');
      _lastError = e.toString();
      _errorCount++;
    }
  }

  Future<void> setExposureMode(ExposureMode mode) async {
    if (_controller == null) {
      Logger.warning('Cannot set exposure mode - controller not initialized');
      return;
    }
    
    try {
      await _controller!.setExposureMode(mode);
      _exposureMode = mode;
      notifyListeners();
      Logger.info('Exposure mode set to: $mode');
    } catch (e) {
      Logger.error('Failed to set exposure mode: $e');
      _lastError = e.toString();
      _errorCount++;
    }
  }

  Future<void> focusOnPoint(Offset point) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      Logger.warning('Cannot focus - controller not ready');
      return;
    }
    
    try {
      await _controller!.setFocusPoint(point);
      await _controller!.setExposurePoint(point);
      Logger.debug('Focused on point: ${point.dx.toStringAsFixed(2)}, ${point.dy.toStringAsFixed(2)}');
    } catch (e) {
      Logger.error('Failed to focus on point: $e');
      _lastError = e.toString();
      _errorCount++;
    }
  }

  Future<void> setZoomLevel(double zoom) async {
    if (_controller == null || !_controller!.value.isInitialized) {
      Logger.warning('Cannot set zoom - controller not ready');
      return;
    }
    
    try {
      final maxZoom = await _controller!.getMaxZoomLevel();
      final minZoom = await _controller!.getMinZoomLevel();
      final clampedZoom = zoom.clamp(minZoom, maxZoom);
      
      await _controller!.setZoomLevel(clampedZoom);
      Logger.debug('Zoom level set to: ${clampedZoom.toStringAsFixed(1)}x');
    } catch (e) {
      Logger.error('Failed to set zoom level: $e');
      _lastError = e.toString();
      _errorCount++;
    }
  }

  List<Map<String, dynamic>> getCamerasInfo() {
    return _cameras.map((camera) => {
      'name': camera.name,
      'lensDirection': camera.lensDirection.toString(),
      'sensorOrientation': camera.sensorOrientation,
    }).toList();
  }

  Future<void> cleanupOldImages({int maxAgeHours = 24}) async {
    try {
      final directory = await getTemporaryDirectory();
      final files = directory.listSync();
      final cutoffTime = DateTime.now().subtract(Duration(hours: maxAgeHours));
      
      int deletedCount = 0;
      for (final file in files) {
        if (file is File && 
            (file.path.contains('optimized_') || file.path.contains('captured_'))) {
          try {
            final stat = await file.stat();
            if (stat.modified.isBefore(cutoffTime)) {
              await file.delete();
              deletedCount++;
            }
          } catch (e) {
            Logger.debug('Could not process file ${file.path}: $e');
          }
        }
      }
      
      if (deletedCount > 0) {
        Logger.info('Cleaned up $deletedCount old images');
      }
    } catch (e) {
      Logger.error('Failed to cleanup old images: $e');
    }
  }

  void _cleanupOldImage(String path) {
    try {
      File(path).deleteSync();
      Logger.debug('Cleaned up old image: ${path.split('/').last}');
    } catch (e) {
      Logger.debug('Could not cleanup image $path: $e');
    }
  }

  Future<bool> testCamera() async {
    try {
      Logger.info('Testing camera functionality...');
      
      if (!_isInitialized) {
        final success = await initialize();
        if (!success) {
          Logger.error('Camera test failed: initialization failed');
          return false;
        }
      }
      
      final controller = await startPreview();
      if (controller == null) {
        Logger.error('Camera test failed: preview failed');
        return false;
      }
      
      await Future.delayed(const Duration(seconds: 1));
      
      final imagePath = await captureImage();
      final imageFile = File(imagePath);
      
      if (await imageFile.exists()) {
        final size = await imageFile.length();
        Logger.info('Camera test passed: captured ${size} bytes');
        
        // Cleanup test image
        await imageFile.delete();
        
        await stopPreview();
        return true;
      } else {
        Logger.error('Camera test failed: no image captured');
        return false;
      }
      
    } catch (e) {
      Logger.error('Camera test failed: $e');
      return false;
    }
  }

  Map<String, dynamic> getCameraStats() {
    return {
      'isInitialized': _isInitialized,
      'isPreviewActive': _isPreviewActive,
      'isCapturing': _isCapturing,
      'autoCaptureEnabled': _autoCaptureEnabled,
      'autoCaptureIntervalMs': _autoCaptureIntervalMs,
      'totalCaptured': _totalCaptured,
      'lastCaptureTime': _lastCaptureTime?.toIso8601String(),
      'flashMode': _flashMode.toString(),
      'focusMode': _focusMode.toString(),
      'exposureMode': _exposureMode.toString(),
      'availableCameras': _cameras.length,
      'currentCamera': _controller?.description.lensDirection.toString(),
      'errorCount': _errorCount,
      'lastError': _lastError,
      'capturedImagePaths': _capturedImagePaths.length,
    };
  }

  @override
  void dispose() {
    stopAutoCapture();
    stopPreview();
    _controller?.dispose();
    
    // Clean up any remaining temporary images
    for (final path in _capturedImagePaths) {
      _cleanupOldImage(path);
    }
    
    super.dispose();
  }
}