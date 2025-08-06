#!/bin/bash

# Isabelle Project Setup Script
# This script creates necessary directories and fixes common Flutter issues

echo "🔧 Setting up Isabelle Flutter project..."

# Create required asset directories
echo "📁 Creating asset directories..."
mkdir -p assets/models
mkdir -p assets/images
mkdir -p assets/sounds
mkdir -p assets/audio_models
mkdir -p fonts

echo "✅ Asset directories created"

# Create placeholder files to prevent build errors
echo "📄 Creating placeholder files..."

# Create a simple notification sound file placeholder
touch assets/sounds/notification.wav
touch assets/sounds/emergency_alert.wav
touch assets/sounds/success.wav
touch assets/sounds/default_alert.wav

echo "# Model files will be downloaded by the app" > assets/models/README.md
echo "# Place custom images here" > assets/images/README.md
echo "# Audio processing models go here" > assets/audio_models/README.md

echo "✅ Placeholder files created"

# Clean Flutter project
echo "🧹 Cleaning Flutter project..."
flutter clean

# Get dependencies
echo "📦 Getting Flutter dependencies..."
flutter pub get

# Upgrade dependencies
echo "⬆️ Upgrading dependencies..."
flutter pub upgrade

# Clean Android build
echo "🤖 Cleaning Android build cache..."
cd android
./gradlew clean
cd ..

# Final clean and get
echo "🔄 Final cleanup..."
flutter clean
flutter pub get

echo ""
echo "✅ Setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Replace your pubspec.yaml with the fixed version"
echo "2. Replace your audio_service.dart with the fixed version"
echo "3. Run: chmod +x setup_project.sh"
echo "4. Run: ./setup_project.sh"
echo "5. Try building: flutter run"
echo ""
echo "🔍 If you still get errors:"
echo "- Check Flutter version: flutter --version"
echo "- Update Flutter: flutter upgrade"
echo "- Check Android SDK is properly configured"
echo "- Ensure you're using Flutter 3.16+ for v2 embedding support"
echo ""
echo "🎯 Target Flutter version: 3.16.0 or higher"
echo "🎯 Target Android compileSdkVersion: 34 or higher"