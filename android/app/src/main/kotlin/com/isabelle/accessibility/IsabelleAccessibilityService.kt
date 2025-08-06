package com.isabelle.accessibility

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import android.content.Context
import android.media.AudioManager
import android.os.Vibrator
import android.os.VibrationEffect
import android.os.Build
import kotlinx.coroutines.*

/**
 * ISABELLE System-Wide Accessibility Service
 * Provides global accessibility features and emergency gesture recognition
 */
class IsabelleAccessibilityService : AccessibilityService() {
    companion object {
        private const val TAG = "IsabelleAccessibilityService"
        
        // Emergency gesture patterns
        private const val EMERGENCY_TRIPLE_TAP_TIMEOUT = 1000L // 1 second
        private const val EMERGENCY_HOLD_DURATION = 3000L // 3 seconds
    }
    
    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var overlayView: View? = null
    private var windowManager: WindowManager? = null
    private var vibrator: Vibrator? = null
    private var audioManager: AudioManager? = null
    
    // Emergency gesture detection
    private var lastTapTime = 0L
    private var tapCount = 0
    private var isEmergencyMode = false
    
    // Accessibility monitoring
    private var lastNotificationTime = 0L
    private var lastSystemAlertTime = 0L
    
    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(TAG, "🌟 ISABELLE Accessibility Service Connected")
        
        setupAccessibilityService()
        initializeSystemIntegration()
        createEmergencyOverlay()
        
        Log.i(TAG, "✅ System-wide accessibility monitoring active")
    }
    
    private fun setupAccessibilityService() {
        val info = AccessibilityServiceInfo().apply {
            // Monitor all events for comprehensive accessibility
            eventTypes = AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED or
                        AccessibilityEvent.TYPE_ANNOUNCEMENT or
                        AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                        AccessibilityEvent.TYPE_VIEW_CLICKED or
                        AccessibilityEvent.TYPE_GESTURE_DETECTION_START or
                        AccessibilityEvent.TYPE_GESTURE_DETECTION_END
            
            // Monitor all apps
            packageNames = null
            
            // Enable gesture detection
            flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                   AccessibilityServiceInfo.FLAG_REQUEST_TOUCH_EXPLORATION_MODE or
                   AccessibilityServiceInfo.FLAG_REQUEST_ENHANCED_WEB_ACCESSIBILITY or
                   AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            
            // Set feedback type
            feedbackType = AccessibilityServiceInfo.FEEDBACK_HAPTIC or
                          AccessibilityServiceInfo.FEEDBACK_AUDIBLE or
                          AccessibilityServiceInfo.FEEDBACK_VISUAL
            
            // No delay for real-time accessibility
            notificationTimeout = 0
        }
        
        serviceInfo = info
        Log.i(TAG, "✅ Accessibility service configuration complete")
    }
    
    private fun initializeSystemIntegration() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        
        Log.i(TAG, "✅ System services initialized")
    }
    
    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        when (event.eventType) {
            AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED -> {
                handleSystemNotification(event)
            }
            AccessibilityEvent.TYPE_ANNOUNCEMENT -> {
                handleSystemAnnouncement(event)
            }
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                handleWindowChange(event)
            }
            AccessibilityEvent.TYPE_VIEW_CLICKED -> {
                handleViewClick(event)
            }
            AccessibilityEvent.TYPE_GESTURE_DETECTION_START -> {
                handleGestureStart(event)
            }
            AccessibilityEvent.TYPE_GESTURE_DETECTION_END -> {
                handleGestureEnd(event)
            }
        }
    }
    
    private fun handleSystemNotification(event: AccessibilityEvent) {
        val currentTime = System.currentTimeMillis()
        
        // Avoid spam - only process notifications every 2 seconds
        if (currentTime - lastNotificationTime < 2000) return
        lastNotificationTime = currentTime
        
        val packageName = event.packageName?.toString() ?: "unknown"
        val text = event.text?.joinToString(" ") ?: "notification"
        
        Log.i(TAG, "🔔 System notification: $packageName - $text")
        
        // Analyze notification for deaf users
        analyzeNotificationForDeafUsers(packageName, text)
    }
    
    private fun analyzeNotificationForDeafUsers(packageName: String, text: String) {
        val urgentPackages = setOf(
            "com.android.dialer",        // Phone calls
            "com.android.mms",           // SMS messages  
            "com.android.phone",         // System phone
            "android",                   // System alerts
            "com.android.systemui"       // System UI alerts
        )
        
        val urgentKeywords = setOf(
            "emergency", "urgent", "alarm", "call", "missed call", 
            "fire", "police", "ambulance", "911", "danger"
        )
        
        val isUrgent = urgentPackages.contains(packageName) || 
                      urgentKeywords.any { text.lowercase().contains(it) }
        
        if (isUrgent) {
            Log.w(TAG, "🚨 URGENT notification detected: $text")
            triggerUrgentNotificationAlert(text)
        } else {
            Log.i(TAG, "📱 Normal notification: $text")
            triggerNormalNotificationAlert(text)
        }
    }
    
    private fun triggerUrgentNotificationAlert(text: String) {
        Log.w(TAG, "🚨 Triggering URGENT notification alert")
        
        // Strong vibration pattern for urgent notifications
        vibrator?.let { vib ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val pattern = longArrayOf(0, 300, 100, 300, 100, 300, 100, 300)
                val effect = VibrationEffect.createWaveform(pattern, -1)
                vib.vibrate(effect)
            } else {
                vib.vibrate(longArrayOf(0, 300, 100, 300, 100, 300, 100, 300), -1)
            }
        }
        
        // Show urgent overlay
        showNotificationOverlay(text, true)
        
        // Launch ISABELLE if not running for urgent notifications
        launchIsabelleForUrgentAlert()
    }
    
    private fun triggerNormalNotificationAlert(text: String) {
        Log.i(TAG, "📱 Triggering normal notification alert")
        
        // Gentle vibration for normal notifications
        vibrator?.let { vib ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val effect = VibrationEffect.createOneShot(200, VibrationEffect.DEFAULT_AMPLITUDE)
                vib.vibrate(effect)
            } else {
                vib.vibrate(200)
            }
        }
        
        // Show brief overlay
        showNotificationOverlay(text, false)
    }
    
    private fun handleSystemAnnouncement(event: AccessibilityEvent) {
        val announcement = event.text?.joinToString(" ") ?: "system announcement"
        Log.i(TAG, "📢 System announcement: $announcement")
        
        // Convert system announcements to visual alerts for deaf users
        showAnnouncementOverlay(announcement)
    }
    
    private fun handleWindowChange(event: AccessibilityEvent) {
        val packageName = event.packageName?.toString()
        val className = event.className?.toString()
        
        Log.d(TAG, "🏠 Window changed: $packageName - $className")
        
        // Special handling for emergency/critical apps
        if (packageName?.contains("dialer") == true || 
            packageName?.contains("phone") == true) {
            Log.i(TAG, "📞 Phone app opened - monitoring for accessibility")
            enablePhoneAccessibilityMode()
        }
    }
    
    private fun handleViewClick(event: AccessibilityEvent) {
        // Monitor for potential emergency button presses
        val contentDescription = event.contentDescription?.toString()
        val text = event.text?.joinToString(" ")
        
        if (contentDescription?.lowercase()?.contains("emergency") == true ||
            text?.lowercase()?.contains("emergency") == true) {
            Log.w(TAG, "🚨 Emergency button clicked detected")
            monitorEmergencyAction()
        }
    }
    
    private fun handleGestureStart(event: AccessibilityEvent) {
        Log.d(TAG, "👆 Gesture detection started")
        detectEmergencyGestures()
    }
    
    private fun handleGestureEnd(event: AccessibilityEvent) {
        Log.d(TAG, "👆 Gesture detection ended")
    }
    
    private fun detectEmergencyGestures() {
        val currentTime = System.currentTimeMillis()
        
        // Detect triple-tap emergency gesture
        if (currentTime - lastTapTime < EMERGENCY_TRIPLE_TAP_TIMEOUT) {
            tapCount++
        } else {
            tapCount = 1
        }
        
        lastTapTime = currentTime
        
        if (tapCount >= 3) {
            Log.w(TAG, "🚨 EMERGENCY TRIPLE-TAP detected!")
            triggerEmergencyGestureAlert()
            tapCount = 0
        }
    }
    
    private fun triggerEmergencyGestureAlert() {
        Log.w(TAG, "🚨 Processing emergency gesture...")
        
        // Strong emergency vibration
        vibrator?.let { vib ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val pattern = longArrayOf(0, 500, 200, 500, 200, 500)
                val effect = VibrationEffect.createWaveform(pattern, -1)
                vib.vibrate(effect)
            } else {
                vib.vibrate(longArrayOf(0, 500, 200, 500, 200, 500), -1)
            }
        }
        
        // Launch ISABELLE emergency mode
        launchIsabelleEmergencyMode()
    }
    
    private fun createEmergencyOverlay() {
        // This will be used for system-wide emergency alerts
        Log.i(TAG, "🆘 Emergency overlay system ready")
    }
    
    private fun showNotificationOverlay(text: String, isUrgent: Boolean) {
        serviceScope.launch {
            try {
                // Remove existing overlay
                overlayView?.let { 
                    windowManager?.removeView(it)
                    overlayView = null
                }
                
                // Create overlay for deaf users
                val layoutInflater = LayoutInflater.from(this@IsabelleAccessibilityService)
                val overlayLayout = layoutInflater.inflate(
                    android.R.layout.simple_list_item_1, null
                ) as TextView
                
                overlayLayout.text = if (isUrgent) "🚨 URGENT: $text" else "📱 $text"
                overlayLayout.setBackgroundColor(
                    if (isUrgent) 0xFFFF0000.toInt() else 0xFF0066CC.toInt()
                )
                overlayLayout.setTextColor(0xFFFFFFFF.toInt())
                overlayLayout.textSize = if (isUrgent) 18f else 14f
                overlayLayout.setPadding(20, 20, 20, 20)
                
                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
                    } else {
                        WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
                    },
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                    PixelFormat.TRANSLUCENT
                )
                
                params.gravity = Gravity.TOP
                
                windowManager?.addView(overlayLayout, params)
                overlayView = overlayLayout
                
                // Auto-hide after 3 seconds (5 seconds for urgent)
                val hideDelay = if (isUrgent) 5000L else 3000L
                Handler(Looper.getMainLooper()).postDelayed({
                    overlayView?.let { 
                        windowManager?.removeView(it)
                        overlayView = null
                    }
                }, hideDelay)
                
            } catch (e: Exception) {
                Log.e(TAG, "Failed to show notification overlay", e)
            }
        }
    }
    
    private fun showAnnouncementOverlay(announcement: String) {
        Log.i(TAG, "📢 Showing announcement overlay: $announcement")
        showNotificationOverlay("📢 $announcement", false)
    }
    
    private fun enablePhoneAccessibilityMode() {
        Log.i(TAG, "📞 Enabling phone accessibility mode")
        
        // Auto-enable speakerphone for deaf users
        audioManager?.let { audio ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                audio.isSpeakerphoneOn = true
                Log.i(TAG, "🔊 Speakerphone auto-enabled for deaf accessibility")
            }
        }
    }
    
    private fun monitorEmergencyAction() {
        Log.w(TAG, "🚨 Monitoring emergency action...")
        // TODO: Connect to ISABELLE emergency system
    }
    
    private fun launchIsabelleForUrgentAlert() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("emergency_alert", true)
                putExtra("alert_type", "urgent_notification")
            }
            startActivity(intent)
            Log.i(TAG, "🚀 Launched ISABELLE for urgent alert")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch ISABELLE for urgent alert", e)
        }
    }
    
    private fun launchIsabelleEmergencyMode() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("emergency_mode", true)
                putExtra("trigger", "system_gesture")
            }
            startActivity(intent)
            Log.w(TAG, "🆘 Launched ISABELLE in EMERGENCY MODE")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch ISABELLE emergency mode", e)
        }
    }
    
    override fun onGesture(gestureId: Int): Boolean {
        Log.i(TAG, "👆 Custom gesture detected: $gestureId")
        
        // Handle custom accessibility gestures
        return when (gestureId) {
            GESTURE_SWIPE_UP -> {
                Log.i(TAG, "⬆️ Swipe up - Launch ISABELLE")
                launchIsabelleFromGesture()
                true
            }
            GESTURE_SWIPE_DOWN -> {
                Log.i(TAG, "⬇️ Swipe down - Quick emergency")
                launchIsabelleEmergencyMode()
                true
            }
            else -> {
                super.onGesture(gestureId)
            }
        }
    }
    
    private fun launchIsabelleFromGesture() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                putExtra("launched_from", "accessibility_gesture")
            }
            startActivity(intent)
            Log.i(TAG, "🚀 Launched ISABELLE from accessibility gesture")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch ISABELLE from gesture", e)
        }
    }
    
    override fun onInterrupt() {
        Log.w(TAG, "⚠️ Accessibility service interrupted")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        
        // Clean up overlay
        overlayView?.let { 
            windowManager?.removeView(it)
            overlayView = null
        }
        
        // Cancel coroutines
        serviceScope.cancel()
        
        Log.i(TAG, "🔚 ISABELLE Accessibility Service destroyed")
    }
}