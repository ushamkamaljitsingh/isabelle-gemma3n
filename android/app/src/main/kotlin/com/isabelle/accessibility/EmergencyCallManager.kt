package com.isabelle.accessibility

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.ContactsContract
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*

/**
 * Emergency calling system for life-threatening sound detection
 * Auto-calls emergency contacts and local emergency services
 */
class EmergencyCallManager(private val context: Context) {
    companion object {
        private const val TAG = "EmergencyCallManager"
        
        // Country-specific emergency numbers
        private val EMERGENCY_NUMBERS = mapOf(
            "US" to "911",      // USA
            "CA" to "911",      // Canada  
            "IN" to "101",      // India (Fire), 102 (Ambulance), 100 (Police)
            "GB" to "999",      // UK
            "AU" to "000",      // Australia
            "DE" to "112",      // Germany
            "FR" to "112",      // France
            "JP" to "119",      // Japan (Fire/Ambulance)
            "CN" to "119",      // China (Fire)
            "BR" to "193",      // Brazil (Fire)
            "RU" to "101",      // Russia (Fire)
            "ZA" to "10177"     // South Africa (Fire)
        )
        
        // Default emergency number if country not detected
        private const val DEFAULT_EMERGENCY = "911"
        
        // Delhi specific numbers
        private val DELHI_EMERGENCY = mapOf(
            "fire" to "101",
            "police" to "100", 
            "ambulance" to "102",
            "disaster" to "108"
        )
    }
    
    data class EmergencyContact(
        val name: String,
        val phoneNumber: String,
        val relationship: String
    )
    
    private val emergencyScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    // Callbacks
    var onEmergencyCallStarted: ((String, String) -> Unit)? = null
    var onEmergencyCallFailed: ((String, String) -> Unit)? = null
    var onContactsLoaded: ((List<EmergencyContact>) -> Unit)? = null
    
    /**
     * Trigger emergency response for life-threatening sounds
     */
    fun triggerEmergencyResponse(soundType: String, confidence: Float) {
        Log.w(TAG, "🚨 EMERGENCY DETECTED: $soundType (confidence: $confidence)")
        
        emergencyScope.launch {
            try {
                // Step 1: Get emergency contacts
                val emergencyContacts = getEmergencyContacts()
                Log.i(TAG, "Found ${emergencyContacts.size} emergency contacts")
                
                // Step 2: Call emergency contacts first
                for (contact in emergencyContacts.take(3)) { // Limit to 3 contacts
                    try {
                        makeEmergencyCall(contact.phoneNumber, "Contact: ${contact.name}")
                        delay(2000) // 2 second delay between calls
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to call ${contact.name}: ${e.message}")
                    }
                }
                
                // Step 3: Call local emergency services after a delay
                delay(5000) // 5 second delay before calling emergency services
                
                val emergencyNumber = getLocalEmergencyNumber(soundType)
                makeEmergencyCall(emergencyNumber, "Emergency Services")
                
            } catch (e: Exception) {
                Log.e(TAG, "Emergency response failed: ${e.message}")
                withContext(Dispatchers.Main) {
                    onEmergencyCallFailed?.invoke(soundType, e.message ?: "Unknown error")
                }
            }
        }
    }
    
    /**
     * Get local emergency number based on country and sound type
     */
    private fun getLocalEmergencyNumber(soundType: String): String {
        val telephonyManager = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val countryCode = telephonyManager.networkCountryIso?.uppercase()
        
        Log.i(TAG, "Detected country: $countryCode")
        
        // Special handling for India/Delhi
        if (countryCode == "IN") {
            return when (soundType.lowercase()) {
                "fire_alarm", "smoke_alarm" -> DELHI_EMERGENCY["fire"] ?: "101"
                "siren" -> DELHI_EMERGENCY["police"] ?: "100"
                "glass_breaking" -> DELHI_EMERGENCY["police"] ?: "100"
                else -> DELHI_EMERGENCY["fire"] ?: "101"
            }
        }
        
        // Use country-specific emergency numbers
        return EMERGENCY_NUMBERS[countryCode] ?: DEFAULT_EMERGENCY
    }
    
    /**
     * Make an emergency call
     */
    private suspend fun makeEmergencyCall(phoneNumber: String, description: String) {
        if (!hasCallPermission()) {
            Log.e(TAG, "No call permission - cannot make emergency call")
            return
        }
        
        withContext(Dispatchers.Main) {
            try {
                Log.w(TAG, "🚨 CALLING $description: $phoneNumber")
                
                val callIntent = Intent(Intent.ACTION_CALL).apply {
                    data = Uri.parse("tel:$phoneNumber")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                
                context.startActivity(callIntent)
                
                onEmergencyCallStarted?.invoke(phoneNumber, description)
                Log.i(TAG, "✅ Emergency call initiated to $description")
                
            } catch (e: Exception) {
                Log.e(TAG, "Failed to make emergency call to $description: ${e.message}")
                onEmergencyCallFailed?.invoke(phoneNumber, e.message ?: "Call failed")
            }
        }
    }
    
    /**
     * Get emergency contacts from user's contacts
     * Looks for contacts with emergency keywords or ICE (In Case of Emergency)
     */
    private suspend fun getEmergencyContacts(): List<EmergencyContact> {
        return withContext(Dispatchers.IO) {
            val contacts = mutableListOf<EmergencyContact>()
            
            if (!hasContactsPermission()) {
                Log.w(TAG, "No contacts permission - using default emergency contacts")
                return@withContext getDefaultEmergencyContacts()
            }
            
            try {
                val cursor = context.contentResolver.query(
                    ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                    arrayOf(
                        ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                        ContactsContract.CommonDataKinds.Phone.NUMBER,
                        ContactsContract.CommonDataKinds.Phone.TYPE
                    ),
                    null, null,
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC"
                )
                
                cursor?.use { c ->
                    while (c.moveToNext()) {
                        val name = c.getString(0) ?: continue
                        val phone = c.getString(1) ?: continue
                        val type = c.getInt(2)
                        
                        // Look for emergency indicators in contact names
                        val nameLower = name.lowercase()
                        if (nameLower.contains("ice") || // In Case of Emergency
                            nameLower.contains("emergency") ||
                            nameLower.contains("mom") || nameLower.contains("dad") ||
                            nameLower.contains("mother") || nameLower.contains("father") ||
                            nameLower.contains("spouse") || nameLower.contains("partner") ||
                            nameLower.contains("guardian") ||
                            type == ContactsContract.CommonDataKinds.Phone.TYPE_MAIN) {
                            
                            contacts.add(EmergencyContact(
                                name = name,
                                phoneNumber = phone.replace("[^+\\d]".toRegex(), ""),
                                relationship = determineRelationship(name, type)
                            ))
                        }
                    }
                }
                
                Log.i(TAG, "Found ${contacts.size} emergency contacts from phone book")
                
            } catch (e: Exception) {
                Log.e(TAG, "Error reading contacts: ${e.message}")
            }
            
            // If no emergency contacts found, add some defaults
            if (contacts.isEmpty()) {
                contacts.addAll(getDefaultEmergencyContacts())
            }
            
            contacts.take(5) // Limit to 5 contacts
        }
    }
    
    private fun determineRelationship(name: String, type: Int): String {
        val nameLower = name.lowercase()
        return when {
            nameLower.contains("mom") || nameLower.contains("mother") -> "Mother"
            nameLower.contains("dad") || nameLower.contains("father") -> "Father" 
            nameLower.contains("spouse") || nameLower.contains("partner") -> "Partner"
            nameLower.contains("ice") -> "Emergency Contact"
            nameLower.contains("emergency") -> "Emergency Contact"
            type == ContactsContract.CommonDataKinds.Phone.TYPE_MAIN -> "Primary Contact"
            else -> "Emergency Contact"
        }
    }
    
    private fun getDefaultEmergencyContacts(): List<EmergencyContact> {
        // These would normally be set by user in app settings
        return listOf(
            EmergencyContact("Emergency Contact 1", "", "Primary"),
            EmergencyContact("Emergency Contact 2", "", "Secondary")
        )
    }
    
    private fun hasCallPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context, 
            Manifest.permission.CALL_PHONE
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    private fun hasContactsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context, 
            Manifest.permission.READ_CONTACTS
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    /**
     * Development mode - verify emergency detection without making actual calls
     * This is for internal testing only, not exposed in production UI
     */
    fun testEmergencyDetection(soundType: String) {
        Log.i(TAG, "🧪 DEVELOPMENT MODE - Verifying emergency detection for: $soundType")
        
        emergencyScope.launch {
            val contacts = getEmergencyContacts()
            val emergencyNumber = getLocalEmergencyNumber(soundType)
            
            withContext(Dispatchers.Main) {
                Log.i(TAG, "Test Results:")
                Log.i(TAG, "- Emergency contacts: ${contacts.size}")
                Log.i(TAG, "- Emergency number: $emergencyNumber")
                Log.i(TAG, "- Call permission: ${hasCallPermission()}")
                
                onContactsLoaded?.invoke(contacts)
            }
        }
    }
    
    fun cleanup() {
        emergencyScope.cancel()
    }
}