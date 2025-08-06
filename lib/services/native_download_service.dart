import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/core_utils.dart';

class NativeDownloadProgress {
  final int downloaded;
  final int total;
  final int percentage;
  final int speedBps;
  final int elapsedMs;

  NativeDownloadProgress({
    required this.downloaded,
    required this.total,
    required this.percentage,
    required this.speedBps,
    required this.elapsedMs,
  });

  factory NativeDownloadProgress.fromMap(Map<String, dynamic> map) {
    return NativeDownloadProgress(
      downloaded: (map['downloaded'] ?? 0).toInt(),  // Handle Long from Kotlin
      total: (map['total'] ?? 0).toInt(),            // Handle Long from Kotlin  
      percentage: map['percentage'] ?? 0,
      speedBps: (map['speedBps'] ?? 0).toInt(),      // Handle Long from Kotlin
      elapsedMs: map['elapsedMs'] ?? 0,
    );
  }

  String get downloadedGB => (downloaded / (1024 * 1024 * 1024)).toStringAsFixed(2);
  String get totalGB => (total / (1024 * 1024 * 1024)).toStringAsFixed(2);
  String get speedMBps => (speedBps / (1024 * 1024)).toStringAsFixed(1);
  String get formattedSpeed => '$speedMBps MB/s';
  
  String get remainingTime {
    if (speedBps == 0) return '--:--';
    
    final remainingBytes = total - downloaded;
    final remainingSeconds = remainingBytes ~/ speedBps;
    
    if (remainingSeconds > 3600) {
      final hours = remainingSeconds ~/ 3600;
      final minutes = (remainingSeconds % 3600) ~/ 60;
      return '$hours:${minutes.toString().padLeft(2, '0')}:${(remainingSeconds % 60).toString().padLeft(2, '0')}';
    } else {
      final minutes = remainingSeconds ~/ 60;
      final seconds = remainingSeconds % 60;
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

  // Legacy compatibility methods
  String get downloadedMB => (downloaded / (1024 * 1024)).toStringAsFixed(1);
  String get totalMB => (total / (1024 * 1024)).toStringAsFixed(1);
  int get speed => speedBps; // Legacy field
}

class NativeDownloadService extends ChangeNotifier {
  static const MethodChannel _methodChannel = MethodChannel('com.isabelle.accessibility/native_downloader');
  static const EventChannel _eventChannel = EventChannel('com.isabelle.accessibility/download_progress');
  
  bool _isDownloading = false;
  bool _downloadCompleted = false;
  NativeDownloadProgress? _currentProgress;
  StreamSubscription? _progressSubscription;
  Completer<String>? _completer;
  
  // Getters
  bool get isDownloading => _isDownloading;
  bool get downloadCompleted => _downloadCompleted;
  NativeDownloadProgress? get currentProgress => _currentProgress;

  /// Initialize the native download service
  static Future<void> initialize() async {
    try {
      await _methodChannel.invokeMethod('initialize');
      Logger.info('✅ Native download service initialized');
    } catch (e) {
      Logger.error('❌ Failed to initialize native download service: $e');
      rethrow;
    }
  }

  /// Check if model is downloaded at specific path
  static Future<bool> isModelDownloaded(String modelPath) async {
    try {
      Logger.info('🔍 Checking model file at: $modelPath');
      final modelFile = File(modelPath);
      final exists = await modelFile.exists();
      Logger.info('📁 File exists: $exists');
      
      if (exists) {
        final fileSize = await modelFile.length();
        final fileSizeGB = (fileSize / (1024 * 1024 * 1024));
        Logger.info('📁 Model file found: ${fileSizeGB.toStringAsFixed(1)}GB');
        Logger.info('📁 File size in bytes: $fileSize');
        Logger.info('📁 Minimum required: ${2500 * 1024 * 1024} bytes (2.5GB)');
        
        if (fileSize >= 2500 * 1024 * 1024) { // 2.5GB minimum for model (file is actually 2.57GB)
          Logger.info('✅ Model file is valid (size >= 2.5GB)');
          return true;
        } else {
          Logger.warning('⚠️ Model file too small: ${fileSizeGB.toStringAsFixed(1)}GB < 2.5GB');
          return false;
        }
      } else {
        Logger.info('❌ Model file does not exist at path');
        return false;
      }
    } catch (e) {
      Logger.error('❌ Error checking model at $modelPath: $e');
      return false;
    }
  }

  /// Legacy method for compatibility with ModelLoadingScreen
  static Future<bool> downloadModelNative({
    required String url,
    required String targetPath,
    required Function(NativeDownloadProgress) onProgress,
  }) async {
    try {
      Logger.info('🚀 Starting native high-speed download...');
      Logger.info('📥 URL: $url');
      Logger.info('📁 Target: $targetPath');

      // Use EventChannel for streaming progress
      StreamSubscription? progressSubscription;
      final completer = Completer<bool>();

      progressSubscription = _eventChannel.receiveBroadcastStream().listen(
        (event) {
          Logger.info('📨 Received event: $event');
          final eventMap = Map<String, dynamic>.from(event);
          
          if (eventMap['status'] == 'complete') {
            Logger.info('✅ NATIVE DOWNLOAD COMPLETE - Received completion event');
            progressSubscription?.cancel();
            completer.complete(true);
          } else if (eventMap['status'] == 'error') {
            final error = eventMap['error'] as String;
            Logger.error('❌ Native download error: $error');
            progressSubscription?.cancel();
            completer.complete(false);
          } else {
            // Regular progress update
            final progress = NativeDownloadProgress.fromMap(eventMap);
            onProgress(progress);
            // Reduce log frequency to avoid spam
            if (progress.percentage % 5 == 0) {
              Logger.info('📊 Native Progress: ${progress.percentage}% @ ${progress.formattedSpeed}');
            }
          }
        },
        onError: (error) {
          Logger.error('❌ Native download stream error: $error');
          progressSubscription?.cancel();
          completer.complete(false);
        },
      );

      // Start the native download
      await _methodChannel.invokeMethod('startDownload', {
        'url': url,
        'targetPath': targetPath,
      });
      
      // Wait for completion
      final success = await completer.future;
      return success;
      
    } catch (e) {
      Logger.error('❌ Native download error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  /// Cancel download
  Future<void> cancelDownload() async {
    if (_isDownloading) {
      Logger.info('🛑 Cancelling native download...');
      await _methodChannel.invokeMethod('cancelDownload');
    }
  }

  /// Check if model is available (use file system check)
  Future<bool> isModelAvailable() async {
    try {
      // Check multiple possible locations where model might exist
      final locations = await _getAllPossibleModelPaths();
      
      for (final modelPath in locations) {
        if (await isModelDownloaded(modelPath)) {
          return true;
        }
      }
      
      Logger.info('📁 Model file not found in any expected location');
      return false;
    } catch (e) {
      Logger.error('❌ Error checking model availability: $e');
      return false;
    }
  }
  
  /// Get all possible model paths to check for existing downloads
  Future<List<String>> _getAllPossibleModelPaths() async {
    final paths = <String>[];
    
    // Path 1: Current path (ApplicationSupportDirectory)
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      paths.add('${appSupportDir.path}/isabelle_models/gemma-3n-E4B-it-int4.task');
    } catch (e) {
      Logger.warning('Could not get ApplicationSupportDirectory: $e');
    }
    
    // Path 2: Old path (ApplicationDocumentsDirectory) for backwards compatibility
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      paths.add('${appDocDir.path}/isabelle_models/gemma-3n-E4B-it-int4.task');
    } catch (e) {
      Logger.warning('Could not get ApplicationDocumentsDirectory: $e');
    }
    
    // Path 3: External storage (in case it was downloaded there)
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        paths.add('${externalDir.path}/isabelle_models/gemma-3n-E4B-it-int4.task');
      }
    } catch (e) {
      Logger.warning('Could not get ExternalStorageDirectory: $e');
    }
    
    Logger.info('🔍 Checking model in these locations: $paths');
    return paths;
  }
}