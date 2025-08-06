import 'package:flutter/material.dart';

class AppConstants {
  // App Info
  static const String appName = 'ISABELLE';
  static const String appTagline = 'AI Vision Assistant for Blind Users';
  
  
  // Model Information - YOUR ACTUAL Gemma 3n model
  static const String modelFileName = 'gemma-3n-E4B-it-int4.task'; // YOUR real MediaPipe .task file
  
  // Storage Keys
  static const String keyAppInitialized = 'app_initialized';
  
  // Audio Settings
  static const int audioSampleRate = 16000;
  static const int audioBufferSize = 8192;
  
  // Speech Recognition Settings
  static const int SPEECH_LISTEN_DURATION_SECONDS = 10;
  static const int SPEECH_PAUSE_DURATION_SECONDS = 2;
  static const bool SPEECH_PARTIAL_RESULTS = true;
  static const String SPEECH_LOCALE = 'en-US';
  
  // Text-to-Speech Settings
  static const String TTS_LANGUAGE = 'en-US';
  static const double TTS_SPEECH_RATE = 0.8;
  static const double TTS_PITCH = 1.0;
  static const double TTS_VOLUME = 1.0;
  
  
  // Camera Settings
  static const double cameraResolutionPreset = 0.7; // 70% quality
  static const int MAX_IMAGE_WIDTH = 1920;
  static const int MAX_IMAGE_HEIGHT = 1080;
  
  // Sound Detection Thresholds (for audio service)
  static const double NORMAL_SOUND_THRESHOLD = 0.3;
  static const double EMERGENCY_SOUND_THRESHOLD = 0.8;
  
  // Alert Thresholds
  static const Duration vibrationDuration = Duration(milliseconds: 500);
  static const Duration urgentVibrationDuration = Duration(milliseconds: 1000);
  static const int flashAlertCount = 3;
  
  // UI Constants
  static const double largeFontSize = 24.0;
  static const double extraLargeFontSize = 32.0;
  static const Duration animationDuration = Duration(milliseconds: 300);
  
  // Emergency
  static const String emergencyNumber = '911'; // Default, can be localized
  static const int emergencyTimeoutSeconds = 10;
  
  // Model Download - ULTRA-FAST Direct Download for Maximum Speed
  // PRIMARY: Your actual Gemma 3n E4B model endpoint
  static const String MODEL_URL = 'https://storage.googleapis.com/gemma3n/models/gemma/gemma-3n-E4B-it-int4.task';
  static const String MODEL_URL_FAST = 'https://storage.googleapis.com/gemma3n/models/gemma/gemma-3n-E4B-it-int4.task';
  
  // SINGLE SOURCE: No fallbacks needed - direct download from your specified endpoint
  static const List<String> MODEL_URLS_PRIORITY = [
    // Primary: Your actual Gemma 3n E4B model - optimized for 11+ MB/s with parallel downloads
    'https://storage.googleapis.com/gemma3n/models/gemma/gemma-3n-E4B-it-int4.task',
  ];
  
  // Legacy fallback URLs (kept for compatibility)
  static const String MODEL_URL_GOOGLE = 'https://storage.googleapis.com/gemma3n/models/gemma/gemma-3n-E4B-it-int4.task';
  static const String MODEL_URL_KAGGLE = 'https://storage.googleapis.com/gemma3n/models/gemma/gemma-3n-E4B-it-int4.task';
  static const String MODEL_CHECKSUM_URL = 'https://storage.googleapis.com/gemma3n/models/gemma/gemma-3n-E4B-it-int4.task.sha256';
  
  // ACTUAL MODEL: Gemma 3n E4B model specifications
  static const int MODEL_SIZE_BYTES = 4724464025; // ~4.4GB for actual Gemma 3n E4B model
  
  // Model configuration for MediaPipe tasks-genai (.task format)
  static const String MODEL_VARIANT = 'gemma-3n-E4B-it'; // YOUR multimodal variant
  static const String MODEL_QUANTIZATION = 'int4'; // INT4 quantization
  static const String MODEL_FORMAT = 'task'; // MediaPipe .task format (NOT .tflite)
  // ULTRA-FAST DOWNLOAD CONFIGURATION (Optimized for 11+ MB/s)
  static const int downloadChunkSize = 80 * 1024 * 1024; // 80MB chunks for maximum speed
  static const int maxParallelConnections = 6; // Optimal 6 parallel streams
  static const int connectionTimeoutSeconds = 8; // Ultra-fast timeout
  static const int downloadRetryAttempts = 3; // Quick retries
  static const int mirrorSwitchThresholdMBps = 8; // Switch if speed < 8MB/s
  
  // Background Service
  static const String backgroundChannelId = 'isabelle_background';
  static const String backgroundChannelName = 'ISABELLE Background Service';
  static const String backgroundNotificationTitle = 'ISABELLE is listening';
  static const String backgroundNotificationBody = 'Monitoring sounds for you';
  
  // Emergency Settings
  static const String EMERGENCY_NUMBER = 'tel:911'; // Default emergency number
  static const String EMERGENCY_TEXT = 'Emergency alert from ISABELLE accessibility app. Please send help.';
  static const int EMERGENCY_TIMEOUT_SECONDS = 10;
  
  // UI Colors
  static const Color primaryTeal = Color(0xFF00FFFF);
  static const Color secondaryTeal = Color(0xFF00CCAA);
  static const Color backgroundDark = Color(0xFF0B1426);
  static const Color backgroundMedium = Color(0xFF1A0F2E);
  static const Color backgroundLight = Color(0xFF0A0E1A);
  static const Color backgroundColor = Color(0xFF0B1426);
  static const Color cardBackground = Color(0xFF1A0F2E);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textTertiary = Color(0xFF808080);
  static const Color successColor = Color(0xFF00FF00);
  static const Color warningColor = Color(0xFFFFAA00);
  static const Color errorColor = Color(0xFFFF6B6B);
}