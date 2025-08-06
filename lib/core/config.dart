import 'package:flutter/material.dart';
import 'constants.dart';

class AppConfig {
  // Singleton pattern
  static final AppConfig _instance = AppConfig._internal();
  factory AppConfig() => _instance;
  AppConfig._internal();
  
  // App settings - simplified for vision assistant only
  bool appInitialized = false;
  String? selectedModel;
  
  // Runtime settings
  bool isModelLoaded = false;
  bool isBackgroundServiceRunning = false;
  
  // Theme configuration
  ThemeData getTheme() {
    return ThemeData(
      primarySwatch: Colors.blue,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      // Large text for accessibility
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(fontSize: 20),
        bodyMedium: TextStyle(fontSize: 18),
      ),
      // High contrast colors
      colorScheme: const ColorScheme.light(
        primary: Colors.blue,
        secondary: Colors.orange,
        surface: Colors.white,
        background: Colors.white,
        error: Colors.red,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.black,
        onBackground: Colors.black,
        onError: Colors.white,
      ),
      // Large touch targets
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(200, 60),
          textStyle: const TextStyle(fontSize: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
  
  // Get text style for vision assistant
  TextStyle getTextStyle(BuildContext context, {bool isTitle = false}) {
    return TextStyle(
      fontSize: isTitle ? 24 : 18,
      fontWeight: isTitle ? FontWeight.bold : FontWeight.normal,
    );
  }
  
  // Voice settings for vision assistant
  Map<String, dynamic> getTTSSettings() {
    return {
      'rate': 0.5, // Slightly slower for clarity
      'pitch': 1.0,
      'volume': 1.0,
      'language': 'en-US',
    };
  }
  
  // Alert settings for vision assistant
  Map<String, dynamic> getAlertSettings() {
    return {
      'vibrationPattern': [0, 500, 200, 500], // Pattern for alerts
      'flashEnabled': true,
      'flashCount': AppConstants.flashAlertCount,
      'notificationEnabled': true,
    };
  }
  
  // Reset configuration
  void reset() {
    appInitialized = false;
    selectedModel = null;
    isModelLoaded = false;
    isBackgroundServiceRunning = false;
  }
}