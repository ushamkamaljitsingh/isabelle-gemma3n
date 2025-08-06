import 'dart:async';
import 'package:flutter/services.dart';
import '../utils/core_utils.dart';

/// Emergency sound detection service for deaf users
/// Detects life-threatening sounds and triggers emergency calls
class EmergencySoundService {
  static const MethodChannel _channel = MethodChannel('sound_detection');
  
  // Stream controllers for different event types
  final StreamController<EmergencySound> _emergencySoundController = 
      StreamController<EmergencySound>.broadcast();
  final StreamController<SoundAlert> _soundAlertController = 
      StreamController<SoundAlert>.broadcast();
  final StreamController<EmergencyCall> _emergencyCallController = 
      StreamController<EmergencyCall>.broadcast();
  
  // Public streams
  Stream<EmergencySound> get onEmergencySound => _emergencySoundController.stream;
  Stream<SoundAlert> get onSoundAlert => _soundAlertController.stream;
  Stream<EmergencyCall> get onEmergencyCall => _emergencyCallController.stream;
  
  bool _isListening = false;
  bool get isListening => _isListening;
  
  EmergencySoundService() {
    _setupMethodCallHandlers();
  }
  
  void _setupMethodCallHandlers() {
    _channel.setMethodCallHandler((call) async {
      Logger.info('🔊 EmergencySoundService: ${call.method}');
      
      switch (call.method) {
        case 'onSoundDetected':
          _handleSoundDetected(call.arguments);
          break;
        case 'onEmergencySound':
          _handleEmergencySound(call.arguments);
          break;
        case 'onEmergencyCall':
          _handleEmergencyCall(call.arguments);
          break;
        case 'onEmergencyCallError':
          _handleEmergencyCallError(call.arguments);
          break;
      }
    });
  }
  
  void _handleSoundDetected(dynamic arguments) {
    try {
      final soundData = Map<String, dynamic>.from(arguments);
      final alert = SoundAlert(
        category: soundData['category'] ?? 'unknown',
        emoji: soundData['emoji'] ?? '🔊',
        description: soundData['description'] ?? 'Sound detected',
        confidence: (soundData['confidence'] as num?)?.toDouble() ?? 0.0,
        level: _parseAlertLevel(soundData['level']),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          soundData['timestamp'] ?? DateTime.now().millisecondsSinceEpoch
        ),
      );
      
      Logger.info('🔊 Sound Alert: ${alert.emoji} ${alert.description}');
      _soundAlertController.add(alert);
      
    } catch (e) {
      Logger.error('Error handling sound detection: $e');
    }
  }
  
  void _handleEmergencySound(dynamic arguments) {
    try {
      final emergencyData = Map<String, dynamic>.from(arguments);
      final emergency = EmergencySound(
        category: emergencyData['category'] ?? 'unknown',
        emoji: emergencyData['emoji'] ?? '🚨',
        description: emergencyData['description'] ?? 'Emergency sound detected',
        confidence: (emergencyData['confidence'] as num?)?.toDouble() ?? 0.0,
        level: _parseAlertLevel(emergencyData['level']),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          emergencyData['timestamp'] ?? DateTime.now().millisecondsSinceEpoch
        ),
      );
      
      Logger.warning('🚨 EMERGENCY SOUND: ${emergency.emoji} ${emergency.description}');
      _emergencySoundController.add(emergency);
      
    } catch (e) {
      Logger.error('Error handling emergency sound: $e');
    }
  }
  
  void _handleEmergencyCall(dynamic arguments) {
    try {
      final callData = Map<String, dynamic>.from(arguments);
      final call = EmergencyCall(
        phoneNumber: callData['phoneNumber'] ?? '',
        description: callData['description'] ?? 'Emergency Call',
        status: callData['status'] ?? 'unknown',
        timestamp: DateTime.now(),
      );
      
      Logger.warning('📞 EMERGENCY CALL: ${call.description} - ${call.phoneNumber}');
      _emergencyCallController.add(call);
      
    } catch (e) {
      Logger.error('Error handling emergency call: $e');
    }
  }
  
  void _handleEmergencyCallError(dynamic arguments) {
    try {
      final errorData = Map<String, dynamic>.from(arguments);
      final call = EmergencyCall(
        phoneNumber: errorData['phoneNumber'] ?? '',
        description: errorData['error'] ?? 'Emergency Call Failed',
        status: 'failed',
        timestamp: DateTime.now(),
      );
      
      Logger.error('❌ EMERGENCY CALL FAILED: ${call.description}');
      _emergencyCallController.add(call);
      
    } catch (e) {
      Logger.error('Error handling emergency call error: $e');
    }
  }
  
  AlertLevel _parseAlertLevel(dynamic level) {
    if (level == null) return AlertLevel.medium;
    
    switch (level.toString().toUpperCase()) {
      case 'EMERGENCY':
        return AlertLevel.emergency;
      case 'HIGH':
        return AlertLevel.high;
      case 'MEDIUM':
        return AlertLevel.medium;
      case 'LOW':
        return AlertLevel.low;
      default:
        return AlertLevel.medium;
    }
  }
  
  /// Start listening for environmental sounds
  Future<bool> startSoundDetection() async {
    try {
      Logger.info('🎯 Starting emergency sound detection...');
      
      final result = await _channel.invokeMethod('startSoundDetection');
      final success = result['success'] ?? false;
      
      if (success) {
        _isListening = true;
        Logger.info('✅ Emergency sound detection started');
      } else {
        Logger.error('❌ Failed to start emergency sound detection');
      }
      
      return success;
    } catch (e) {
      Logger.error('Error starting sound detection: $e');
      return false;
    }
  }
  
  /// Stop listening for environmental sounds
  Future<bool> stopSoundDetection() async {
    try {
      Logger.info('🛑 Stopping emergency sound detection...');
      
      final result = await _channel.invokeMethod('stopSoundDetection');
      final success = result['success'] ?? false;
      
      if (success) {
        _isListening = false;
        Logger.info('✅ Emergency sound detection stopped');
      } else {
        Logger.error('❌ Failed to stop emergency sound detection');
      }
      
      return success;
    } catch (e) {
      Logger.error('Error stopping sound detection: $e');
      return false;
    }
  }
  
  // DEBUG ONLY - Remove these methods for production
  // These are kept for internal development but should NOT be exposed in production UI
  
  /*
  /// Test emergency detection system - INTERNAL USE ONLY
  Future<bool> testEmergencyDetection(String soundType) async {
    try {
      Logger.info('🧪 Testing emergency detection for: $soundType');
      
      final result = await _channel.invokeMethod('testEmergencyDetection', {
        'soundType': soundType,
      });
      
      return result['success'] ?? false;
    } catch (e) {
      Logger.error('Error testing emergency detection: $e');
      return false;
    }
  }
  
  /// Simulate an emergency sound for testing - INTERNAL USE ONLY
  Future<bool> simulateEmergencySound(String soundType, {double confidence = 0.9}) async {
    try {
      Logger.warning('🔥 SIMULATING EMERGENCY: $soundType');
      
      final result = await _channel.invokeMethod('simulateEmergencySound', {
        'soundType': soundType,
        'confidence': confidence,
      });
      
      return result['success'] ?? false;
    } catch (e) {
      Logger.error('Error simulating emergency sound: $e');
      return false;
    }
  }
  */
  
  /// Get current sound detection status
  Future<Map<String, dynamic>> getStatus() async {
    try {
      final result = await _channel.invokeMethod('getSoundDetectionStatus');
      return Map<String, dynamic>.from(result);
    } catch (e) {
      Logger.error('Error getting sound detection status: $e');
      return {'isActive': false, 'classifier': 'None'};
    }
  }
  
  void dispose() {
    _emergencySoundController.close();
    _soundAlertController.close();
    _emergencyCallController.close();
  }
}

enum AlertLevel {
  emergency,
  high, 
  medium,
  low
}

class SoundAlert {
  final String category;
  final String emoji;
  final String description;
  final double confidence;
  final AlertLevel level;
  final DateTime timestamp;
  
  SoundAlert({
    required this.category,
    required this.emoji,
    required this.description,
    required this.confidence,
    required this.level,
    required this.timestamp,
  });
  
  @override
  String toString() => '$emoji $description (${(confidence * 100).toInt()}%)';
}

class EmergencySound extends SoundAlert {
  EmergencySound({
    required super.category,
    required super.emoji,
    required super.description,
    required super.confidence,
    required super.level,
    required super.timestamp,
  });
}

class EmergencyCall {
  final String phoneNumber;
  final String description;
  final String status; // 'calling', 'failed', 'completed'
  final DateTime timestamp;
  
  EmergencyCall({
    required this.phoneNumber,
    required this.description,
    required this.status,
    required this.timestamp,
  });
  
  @override
  String toString() => '$description: $phoneNumber ($status)';
}