import 'dart:io';
import 'package:flutter/services.dart';

class RAMChecker {
  static const MethodChannel _channel = MethodChannel('com.isabelle.accessibility/system_info');
  
  /// Returns available RAM in MB
  static Future<int> getAvailableRAM() async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod('getAvailableRAM');
        return result as int;
      } else if (Platform.isIOS) {
        // iOS implementation
        final result = await _channel.invokeMethod('getAvailableRAM');
        return result as int;
      } else {
        // Default for other platforms
        return 4096; // Assume 4GB
      }
    } catch (e) {
      print('Error getting RAM: $e');
      return 2048; // Default to 2GB on error
    }
  }
  
  /// Returns the appropriate model name based on available RAM
  static Future<String> selectModelForDevice() async {
    final ramMB = await getAvailableRAM();
    
    if (ramMB < 2048) {
      return 'gemma-lite.tflite';
    } else if (ramMB < 4096) {
      return 'gemma-e2b-small.tflite';
    } else {
      return 'gemma-e2b-full.tflite';
    }
  }
  
  /// Get model download URL based on model name
  static String getModelUrl(String modelName) {
    // For now, all devices use the same optimized Gemma 3n E2B model
    // In future, we can have different model sizes
    return 'https://pub-70e5ead52e0a44729fbb3eec76e1fbfa.r2.dev/gemma-3n-e2b-it-int4.task';
  }
  
  /// Get expected model size in MB for UI display
  static int getModelSizeMB(String modelName) {
    // Current Gemma 3n E2B INT4 model is 3.14GB
    // Future models can have different sizes based on RAM
    return 3217; // 3.14GB in MB
  }
}