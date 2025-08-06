import 'package:shared_preferences/shared_preferences.dart';

/// Local storage manager for app preferences
class Storage {
  static const String _keyUserMode = 'user_mode';
  static const String _keyBackgroundEnabled = 'background_monitoring_enabled';
  static const String _keyOnboardingComplete = 'onboarding_complete';
  static const String _keyEmergencyContacts = 'emergency_contacts';
  static const String _keyModelDownloaded = 'model_downloaded';
  
  static late SharedPreferences _prefs;
  
  /// Initialize storage
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }
  
  /// User mode (blind/deaf)
  static String? getUserMode() => _prefs.getString(_keyUserMode);
  static Future<void> setUserMode(String mode) => _prefs.setString(_keyUserMode, mode);
  
  /// Background monitoring for deaf users
  static bool getBackgroundEnabled() => _prefs.getBool(_keyBackgroundEnabled) ?? false;
  static Future<void> setBackgroundEnabled(bool enabled) => _prefs.setBool(_keyBackgroundEnabled, enabled);
  
  /// Onboarding status
  static bool isOnboardingComplete() => _prefs.getBool(_keyOnboardingComplete) ?? false;
  static Future<void> setOnboardingComplete(bool complete) => _prefs.setBool(_keyOnboardingComplete, complete);
  
  /// Emergency contacts
  static List<String> getEmergencyContacts() => _prefs.getStringList(_keyEmergencyContacts) ?? [];
  static Future<void> setEmergencyContacts(List<String> contacts) => _prefs.setStringList(_keyEmergencyContacts, contacts);
  
  /// Model download status
  static bool isModelDownloaded() => _prefs.getBool(_keyModelDownloaded) ?? false;
  static Future<void> setModelDownloaded(bool downloaded) => _prefs.setBool(_keyModelDownloaded, downloaded);
  
  /// Clear all data
  static Future<void> clear() => _prefs.clear();
}