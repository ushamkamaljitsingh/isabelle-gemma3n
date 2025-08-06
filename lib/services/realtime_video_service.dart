// lib/services/realtime_video_service.dart
import 'package:flutter/services.dart';
import '../utils/core_utils.dart';

class RealtimeVideoService {
  static const MethodChannel _channel = MethodChannel('com.isabelle.accessibility/realtime_video');
  
  bool _isDescribing = false;
  
  // Callbacks
  Function(String description, int frameNumber)? onSceneDescription;
  Function(String error)? onError;
  
  bool get isDescribing => _isDescribing;
  
  RealtimeVideoService() {
    _setupMethodCallHandler();
  }
  
  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onSceneDescription':
          final args = call.arguments as Map<String, dynamic>;
          final description = args['description'] as String;
          final frameNumber = args['frameNumber'] as int;
          Logger.info('📺 Real-time description: ${description.substring(0, description.length.clamp(0, 50))}...');
          onSceneDescription?.call(description, frameNumber);
          break;
          
        case 'onError':
          final error = call.arguments as String;
          Logger.error('❌ Real-time video error: $error');
          onError?.call(error);
          break;
          
        default:
          Logger.warning('Unknown method call from native: ${call.method}');
      }
    });
  }
  
  /// Start real-time video description
  Future<bool> startRealtimeDescriber() async {
    try {
      Logger.info('🎥 Starting real-time video describer...');
      
      final result = await _channel.invokeMethod('startRealtimeDescriber');
      final success = result['success'] as bool;
      
      if (success) {
        _isDescribing = true;
        Logger.info('✅ Real-time video describer started successfully');
      } else {
        Logger.error('❌ Failed to start real-time video describer');
      }
      
      return success;
      
    } catch (e) {
      Logger.error('❌ Error starting real-time video describer: $e');
      return false;
    }
  }
  
  /// Stop real-time video description
  Future<bool> stopRealtimeDescriber() async {
    try {
      Logger.info('🛑 Stopping real-time video describer...');
      
      final result = await _channel.invokeMethod('stopRealtimeDescriber');
      final success = result['success'] as bool;
      
      if (success) {
        _isDescribing = false;
        Logger.info('✅ Real-time video describer stopped successfully');
      } else {
        Logger.error('❌ Failed to stop real-time video describer');
      }
      
      return success;
      
    } catch (e) {
      Logger.error('❌ Error stopping real-time video describer: $e');
      return false;
    }
  }
  
  /// Get current status of real-time video describer
  Future<Map<String, dynamic>> getRealtimeStatus() async {
    try {
      final result = await _channel.invokeMethod('getRealtimeStatus');
      return Map<String, dynamic>.from(result);
    } catch (e) {
      Logger.error('❌ Error getting real-time status: $e');
      return {'isDescribing': false, 'error': e.toString()};
    }
  }
  
  /// Toggle real-time video description on/off
  Future<bool> toggleRealtimeDescriber() async {
    if (_isDescribing) {
      return await stopRealtimeDescriber();
    } else {
      return await startRealtimeDescriber();
    }
  }
}