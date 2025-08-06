# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ISABELLE is a dignity-focused, offline AI accessibility assistant for blind and deaf users. It uses Gemma 3n models (E4B multimodal architecture) for all AI tasks including speech-to-text, image description, and sound classification - completely offline. The app adapts to device capabilities by selecting appropriate model sizes based on available RAM.

## User Flow & Core Features

### 🔄 Stage 1: Device Profiling & Model Selection
The app automatically downloads the appropriate Gemma E4B multimodal model:
- **Primary Model**: `gemma-3n-E4B-it-int4.task` (~3GB, multimodal)
- **Auto-download**: Downloads on first launch to internal storage
- **Fallback Sources**: Multiple download mirrors for reliability

### 🎙️ Stage 2: Role Detection
User selects their mode through voice or touch:
- **Blind Mode**: All interactions via voice/TTS
- **Deaf Mode**: All interactions via text/visual alerts

### 📱 Role-Based Features

#### 🔵 BLIND MODE
- **Vision Assistant**: "What's in front of me?" - Takes photo, describes via Gemma
- **OCR Reader**: Reads text from medicine labels, documents
- **Voice Commands**: All app control via speech
- **Emergency**: Voice-triggered emergency calling

#### 🟣 DEAF MODE
- **Sound Monitoring**: Continuous background audio analysis
- **Alert System**: Vibration + flashlight for important sounds
- **Live Transcription**: Real-time speech-to-text for conversations
- **Emergency**: Auto-detection of alarms, screams

## Essential Commands

### Initial Setup
```bash
# Make setup script executable and run it
chmod +x setup_project.sh
./setup_project.sh

# Setup background services for Android
cd android && ./gradlew installDebug && cd ..
```

### Development Commands
```bash
# Clean and get dependencies
flutter clean && flutter pub get

# Run the app
flutter run

# Build for platforms
flutter build apk --split-per-abi  # Smaller APKs per architecture
flutter build appbundle
flutter build ios

# Run tests
flutter test

# Analyze code
flutter analyze

# Android-specific commands
cd android && ./gradlew clean && cd ..
cd android && ./gradlew assembleDebug && cd ..

# Verify Gemma model deployment
cd android && ./gradlew verifyGemmaDeployment && cd ..
cd android && ./gradlew checkGemmaModel && cd ..
cd android && ./gradlew printGemmaConfig && cd ..
```

## Intended Architecture (Target Structure)

### 📁 Recommended Project Structure
```
lib/
├── main.dart
├── core/
│   ├── config.dart
│   ├── constants.dart
│   └── utils/
│       ├── permission_utils.dart
│       ├── ram_check.dart            # Device profiling
│       └── gemma_wrapper.dart        # Unified Gemma interface
├── onboarding/
│   ├── role_selector.dart            # Voice/touch role selection
│   ├── blind_onboarding_flow.dart    # Blind-specific setup
│   ├── deaf_onboarding_flow.dart     # Deaf-specific setup
│   └── permission_manager.dart       # Role-aware permissions
├── blind/
│   ├── blind_home.dart               # Main blind mode screen
│   ├── speech_assistant.dart         # Voice command processing
│   ├── ocr_reader.dart              # Text recognition
│   ├── object_describer.dart        # "What's in front" feature
│   └── emergency_caller.dart        # Voice-triggered emergency
├── deaf/
│   ├── deaf_home.dart               # Main deaf mode screen
│   ├── sound_listener.dart          # Continuous audio monitoring
│   ├── alert_manager.dart           # Vibration/flash alerts
│   └── torch_vibrator.dart          # Physical alert system
├── shared/
│   ├── emergency_manager.dart       # Common emergency logic
│   ├── storage.dart                 # Local preferences
│   └── audio_player.dart           # Sound playback
```

### 🤖 Android Background Services
```
android/app/src/main/kotlin/com/isabelle/accessibility/
├── MainActivity.kt                   # Main activity
├── BootReceiver.kt                  # Auto-start on boot
├── MicBackgroundService.kt          # Deaf mode audio monitoring
├── EmergencyService.kt              # Emergency detection
└── TorchService.kt                  # Flashlight control
```

### Key Architectural Principles

1. **Role-Based Separation**: Blind and deaf modes have completely separate flows
2. **Offline-First**: All AI processing via local Gemma models
3. **Adaptive Models**: RAM-based model selection for optimal performance
4. **Background Processing**: Deaf mode runs continuously in background
5. **Dignity-Focused**: Minimal interaction required, maximum independence

## Current vs Target State

### Current Implementation
- Basic structure with mixed concerns in services/
- Model loading but not RAM-adaptive
- Partial role separation

### Migration Path
1. Implement RAM detection in `model_downloader_service.dart`
2. Create proper onboarding flow with role selection
3. Separate blind/deaf features into dedicated modules
4. Add background service for deaf mode continuous monitoring
5. Implement Gemma-based speech-to-text (replace external STT)

## Development Guidelines

### RAM-Based Model Selection
```dart
// In model_downloader_service.dart
Future<String> selectModelBasedOnRAM() async {
  final ramMB = await getAvailableRAM();
  if (ramMB < 2048) return 'gemma-lite.tflite';
  else if (ramMB < 4096) return 'gemma-e2b-small.tflite';
  else return 'gemma-e2b-full.tflite';
}
```

### Background Service Setup (Android)
```bash
# Enable background execution for deaf mode
# Add to AndroidManifest.xml:
# <service android:name=".MicBackgroundService" 
#          android:foregroundServiceType="microphone" />

# Test background service
adb shell am startservice -n com.isabelle.accessibility/.MicBackgroundService
```

### Gemma Integration Points
1. **Speech Recognition**: Replace `speech_to_text` with Gemma inference
2. **Image Description**: Camera → Resize → Gemma → TTS
3. **Sound Classification**: Audio buffer → Gemma → Alert decision
4. **Text Extraction**: OCR → Gemma for context understanding

### Testing Different Modes
```bash
# Test blind mode features
flutter run --dart-define=USER_MODE=blind

# Test deaf mode features  
flutter run --dart-define=USER_MODE=deaf

# Test with specific model
flutter run --dart-define=GEMMA_MODEL=gemma-lite.tflite
```

### Critical Implementation Notes

1. **OPTIMAL PERMISSIONS STRATEGY - Default Phone App**
   - **Step 1**: Request "Set as Default Phone App" (single request)
   - **Auto-granted**: READ_CALL_LOG, WRITE_CALL_LOG, READ_CONTACTS, CALL_PHONE, READ_PHONE_STATE
   - **Blind Mode**: Camera + Mic + Location (contacts/calling automatic)
   - **Deaf Mode**: Mic only (contacts/calling automatic)

2. **Background Execution (Deaf Mode)**
   - Use Android foreground service
   - iOS: Background audio capability
   - Continuous mic access with battery optimization

3. **Model Download Strategy**
   - Check available storage before download
   - Progressive download with resume capability
   - Verify model integrity with checksums

4. **Emergency Features**
   - Store emergency contacts locally
   - GPS access only when triggered
   - Fallback to system emergency call

### Platform-Specific Requirements
- **Android**: Min SDK 24, Target SDK 35, NDK 27.0.12077973
- **iOS**: iOS 12.0+, NSMicrophoneUsageDescription, NSCameraUsageDescription
- **Background**: android:foregroundServiceType="microphone|camera"