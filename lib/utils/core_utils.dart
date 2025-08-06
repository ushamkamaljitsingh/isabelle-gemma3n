// lib/utils/core_utils.dart
// Consolidated core utilities for ISABELLE app

import 'dart:developer' as developer;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

/// Simple logging utility for the application
class Logger {
  static const String _appName = 'Isabelle';
  
  /// Log info message
  static void info(String message) {
    // Send to both Flutter console and Android logcat
    print('I/$_appName: $message');
    developer.log(
      message,
      name: _appName,
      level: 800, // Info level
    );
  }
  
  /// Log debug message
  static void debug(String message) {
    // Send to both Flutter console and Android logcat
    print('D/$_appName: $message');
    developer.log(
      message,
      name: _appName,
      level: 700, // Debug level
    );
  }
  
  /// Log warning message
  static void warning(String message) {
    // Send to both Flutter console and Android logcat
    print('W/$_appName: $message');
    developer.log(
      message,
      name: _appName,
      level: 900, // Warning level
    );
  }
  
  /// Log error message
  static void error(String message) {
    // Send to both Flutter console and Android logcat
    print('E/$_appName: $message');
    developer.log(
      message,
      name: _appName,
      level: 1000, // Error level
    );
  }
  
  /// Log message with custom level
  static void log(String message, {int level = 800}) {
    // Send to both Flutter console and Android logcat
    print('L/$_appName: $message');
    developer.log(
      message,
      name: _appName,
      level: level,
    );
  }
}

/// Comprehensive permission utilities for accessibility features
class PermissionUtils {
  /// Get required permissions based on user role
  static List<Permission> getRequiredPermissions(String userRole) {
    if (userRole == 'blind') {
      return [
        Permission.microphone,
        Permission.camera,
        Permission.location,
        Permission.phone,
        Permission.contacts,
        Permission.notification,
      ];
    } else if (userRole == 'deaf') {
      return [
        Permission.microphone,
        Permission.notification,
        Permission.phone,
        Permission.contacts,
        Permission.storage,
        Permission.accessNotificationPolicy,
      ];
    }
    
    // Default permissions for general use
    return [
      Permission.microphone,
      Permission.notification,
      Permission.phone,
      Permission.contacts,
    ];
  }

  /// Request all necessary permissions for the app
  static Future<bool> requestAllPermissions() async {
    Logger.info('Requesting all app permissions...');
    
    final permissions = [
      Permission.microphone,
      Permission.camera,
      Permission.phone,
      Permission.contacts,
      Permission.location,
      Permission.notification,
      Permission.storage,
      Permission.systemAlertWindow,
      Permission.accessNotificationPolicy,
    ];
    
    bool allGranted = true;
    
    for (final permission in permissions) {
      try {
        final status = await permission.request();
        Logger.info('Permission ${permission.toString()}: $status');
        
        if (status != PermissionStatus.granted) {
          allGranted = false;
          Logger.warning('Permission denied: ${permission.toString()}');
        }
      } catch (e) {
        Logger.error('Error requesting permission ${permission.toString()}: $e');
        allGranted = false;
      }
    }
    
    Logger.info('All permissions granted: $allGranted');
    return allGranted;
  }

  /// Check if specific permission is granted
  static Future<bool> isPermissionGranted(Permission permission) async {
    final status = await permission.status;
    return status == PermissionStatus.granted;
  }

  /// Check if all role-based permissions are granted
  static Future<bool> areRolePermissionsGranted(String userRole) async {
    final requiredPermissions = getRequiredPermissions(userRole);
    
    for (final permission in requiredPermissions) {
      if (!await isPermissionGranted(permission)) {
        return false;
      }
    }
    
    return true;
  }

  /// Request specific permission with proper error handling
  static Future<bool> requestPermission(Permission permission) async {
    try {
      final status = await permission.request();
      Logger.info('Requested ${permission.toString()}: $status');
      return status == PermissionStatus.granted;
    } catch (e) {
      Logger.error('Failed to request ${permission.toString()}: $e');
      return false;
    }
  }

  /// Show permission rationale dialog
  static Future<bool> showPermissionRationale(
    BuildContext context,
    Permission permission,
    String title,
    String message,
  ) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    ) ?? false;
  }

  /// Open app settings for permission management
  static Future<void> openAppSettings() async {
    Logger.info('Opening app settings for permission management');
    await openAppSettings();
  }
}