package com.isabelle.accessibility

import android.content.Context
import android.database.Cursor
import android.provider.ContactsContract
import android.util.Log
import kotlinx.coroutines.*
import java.util.*

/**
 * ISABELLE Contact Matching Service - Intelligent contact lookup for blind users
 * Matches voice commands like "Call my mother" to actual phone contacts
 * Handles fuzzy matching, relationship keywords, and accessibility optimizations
 */
class ContactMatchingService(private val context: Context) {
    companion object {
        private const val TAG = "ContactMatchingService"
        
        // Common relationship keywords for blind users
        private val RELATIONSHIP_KEYWORDS = mapOf(
            // Family relationships
            "mother" to listOf("mom", "mama", "mother", "mum", "mommy"),
            "father" to listOf("dad", "papa", "father", "daddy", "pop"),
            "sister" to listOf("sister", "sis"),
            "brother" to listOf("brother", "bro"),
            "wife" to listOf("wife", "spouse"),
            "husband" to listOf("husband", "spouse"),
            "son" to listOf("son", "boy"),
            "daughter" to listOf("daughter", "girl"),
            "grandmother" to listOf("grandma", "grandmother", "nana", "granny"),
            "grandfather" to listOf("grandpa", "grandfather", "papa"),
            
            // Common names/nicknames
            "doctor" to listOf("doctor", "dr", "doc"),
            "home" to listOf("home", "house"),
            "work" to listOf("work", "office", "job"),
            "emergency" to listOf("emergency", "911", "help")
        )
        
        // Emergency keywords that should trigger emergency calling
        private val EMERGENCY_KEYWORDS = listOf(
            "911", "emergency", "help", "police", "fire", "ambulance", "rescue"
        )
    }
    
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var cachedContacts = mutableListOf<ContactInfo>()
    private var lastContactsSync = 0L
    private val contactsCacheTimeout = 300000L // 5 minutes
    
    data class ContactInfo(
        val id: String,
        val name: String,
        val phoneNumber: String,
        val displayName: String,
        val relationship: String? = null,
        val isStarred: Boolean = false,
        val timesContacted: Int = 0,
        val lastTimeContacted: Long = 0L
    )
    
    data class CallMatchResult(
        val contact: ContactInfo?,
        val confidence: Float,
        val isEmergency: Boolean = false,
        val emergencyType: String? = null,
        val matchReason: String
    )
    
    /**
     * Process voice command to find matching contact for calling
     */
    suspend fun processVoiceCallCommand(voiceCommand: String): CallMatchResult = withContext(Dispatchers.IO) {
        try {
            Log.i(TAG, "🗣️ Processing voice call command: '$voiceCommand'")
            
            val normalizedCommand = normalizeVoiceCommand(voiceCommand)
            
            // Check for emergency keywords first
            val emergencyMatch = checkForEmergencyCall(normalizedCommand)
            if (emergencyMatch != null) {
                return@withContext emergencyMatch
            }
            
            // Extract the contact name from the command
            val contactName = extractContactName(normalizedCommand)
            if (contactName.isEmpty()) {
                return@withContext CallMatchResult(
                    contact = null,
                    confidence = 0.0f,
                    matchReason = "Could not extract contact name from command"
                )
            }
            
            Log.i(TAG, "🔍 Extracted contact name: '$contactName'")
            
            // Ensure we have up-to-date contacts
            ensureContactsLoaded()
            
            // Find best matching contact
            val matchedContact = findBestContactMatch(contactName)
            
            Log.i(TAG, "📞 Contact match result: ${matchedContact?.contact?.name} (confidence: ${matchedContact?.confidence})")
            
            return@withContext matchedContact ?: CallMatchResult(
                contact = null,
                confidence = 0.0f,
                matchReason = "No matching contact found for '$contactName'"
            )
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to process voice call command", e)
            return@withContext CallMatchResult(
                contact = null,
                confidence = 0.0f,
                matchReason = "Error processing command: ${e.message}"
            )
        }
    }
    
    /**
     * Normalize voice command for better matching
     */
    private fun normalizeVoiceCommand(command: String): String {
        return command
            .lowercase()
            .replace(Regex("[^a-zA-Z0-9\\s]"), "") // Remove punctuation
            .replace(Regex("\\s+"), " ") // Normalize whitespace
            .trim()
    }
    
    /**
     * Check if the command is requesting an emergency call
     */
    private fun checkForEmergencyCall(normalizedCommand: String): CallMatchResult? {
        EMERGENCY_KEYWORDS.forEach { keyword ->
            if (normalizedCommand.contains(keyword)) {
                Log.w(TAG, "🚨 Emergency keyword detected: '$keyword'")
                return CallMatchResult(
                    contact = null,
                    confidence = 1.0f,
                    isEmergency = true,
                    emergencyType = "voice_activated_emergency",
                    matchReason = "Emergency keyword '$keyword' detected in voice command"
                )
            }
        }
        return null
    }
    
    /**
     * Extract contact name from voice command
     */
    private fun extractContactName(normalizedCommand: String): String {
        // Common patterns for call commands
        val callPatterns = listOf(
            Regex("call\\s+(.+)"),
            Regex("phone\\s+(.+)"),
            Regex("dial\\s+(.+)"),
            Regex("ring\\s+(.+)")
        )
        
        for (pattern in callPatterns) {
            val match = pattern.find(normalizedCommand)
            if (match != null) {
                var contactName = match.groupValues[1].trim()
                
                // Remove common prefixes
                contactName = contactName
                    .removePrefix("my ")
                    .removePrefix("the ")
                    .trim()
                
                return contactName
            }
        }
        
        // If no pattern matches, return the whole command (fallback)
        return normalizedCommand
    }
    
    /**
     * Ensure contacts are loaded and up-to-date
     */
    private suspend fun ensureContactsLoaded() {
        val currentTime = System.currentTimeMillis()
        if (cachedContacts.isEmpty() || (currentTime - lastContactsSync) > contactsCacheTimeout) {
            Log.i(TAG, "🔄 Loading contacts from device...")
            loadContactsFromDevice()
            lastContactsSync = currentTime
        }
    }
    
    /**
     * Load contacts from device contacts database
     */
    private suspend fun loadContactsFromDevice() = withContext(Dispatchers.IO) {
        try {
            val contacts = mutableListOf<ContactInfo>()
            
            val projection = arrayOf(
                ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
                ContactsContract.CommonDataKinds.Phone.STARRED,
                ContactsContract.CommonDataKinds.Phone.TIMES_CONTACTED,
                ContactsContract.CommonDataKinds.Phone.LAST_TIME_CONTACTED
            )
            
            val cursor: Cursor? = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                projection,
                null,
                null,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC"
            )
            
            cursor?.use { c ->
                while (c.moveToNext()) {
                    try {
                        val contactId = c.getString(c.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.CONTACT_ID))
                        val displayName = c.getString(c.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)) ?: ""
                        val phoneNumber = c.getString(c.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)) ?: ""
                        val isStarred = c.getInt(c.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.STARRED)) == 1
                        val timesContacted = c.getInt(c.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.TIMES_CONTACTED))
                        val lastTimeContacted = c.getLong(c.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.LAST_TIME_CONTACTED))
                        
                        if (displayName.isNotEmpty() && phoneNumber.isNotEmpty()) {
                            contacts.add(
                                ContactInfo(
                                    id = contactId,
                                    name = displayName,
                                    phoneNumber = phoneNumber,
                                    displayName = displayName,
                                    isStarred = isStarred,
                                    timesContacted = timesContacted,
                                    lastTimeContacted = lastTimeContacted
                                )
                            )
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "⚠️ Error reading contact row: ${e.message}")
                    }
                }
            }
            
            cachedContacts = contacts
            Log.i(TAG, "✅ Loaded ${cachedContacts.size} contacts from device")
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to load contacts from device", e)
        }
    }
    
    /**
     * Find the best matching contact for the given name
     */
    private fun findBestContactMatch(contactName: String): CallMatchResult? {
        if (cachedContacts.isEmpty()) {
            Log.w(TAG, "⚠️ No contacts available for matching")
            return null
        }
        
        val matches = mutableListOf<Pair<ContactInfo, Float>>()
        
        for (contact in cachedContacts) {
            val confidence = calculateMatchConfidence(contactName, contact)
            if (confidence > 0.3f) { // Minimum threshold for consideration
                matches.add(Pair(contact, confidence))
            }
        }
        
        if (matches.isEmpty()) {
            return null
        }
        
        // Sort by confidence (highest first)
        matches.sortByDescending { it.second }
        
        val bestMatch = matches.first()
        val confidence = bestMatch.second
        
        // Boost confidence for starred contacts or frequently contacted
        val adjustedConfidence = if (bestMatch.first.isStarred) {
            Math.min(1.0f, confidence + 0.2f)
        } else if (bestMatch.first.timesContacted > 10) {
            Math.min(1.0f, confidence + 0.1f)
        } else {
            confidence
        }
        
        return CallMatchResult(
            contact = bestMatch.first,
            confidence = adjustedConfidence,
            matchReason = "Contact name match with ${(adjustedConfidence * 100).toInt()}% confidence"
        )
    }
    
    /**
     * Calculate match confidence between voice command and contact
     */
    private fun calculateMatchConfidence(voiceCommand: String, contact: ContactInfo): Float {
        val contactName = contact.displayName.lowercase()
        val command = voiceCommand.lowercase()
        
        // Exact match
        if (contactName == command) {
            return 1.0f
        }
        
        // Check if command contains the full contact name
        if (contactName.contains(command) || command.contains(contactName)) {
            return 0.9f
        }
        
        // Check relationship keywords
        val relationshipMatch = checkRelationshipMatch(command, contactName)
        if (relationshipMatch > 0) {
            return relationshipMatch
        }
        
        // Word-based matching
        val contactWords = contactName.split("\\s+".toRegex())
        val commandWords = command.split("\\s+".toRegex())
        
        var matchedWords = 0
        var totalWords = Math.max(contactWords.size, commandWords.size)
        
        for (contactWord in contactWords) {
            for (commandWord in commandWords) {
                if (contactWord.equals(commandWord, ignoreCase = true)) {
                    matchedWords++
                    break
                } else if (contactWord.length > 3 && commandWord.length > 3) {
                    // Fuzzy match for longer words (handles mispronunciation)
                    val similarity = calculateStringSimilarity(contactWord, commandWord)
                    if (similarity > 0.7f) {
                        matchedWords++
                        break
                    }
                }
            }
        }
        
        return if (totalWords > 0) matchedWords.toFloat() / totalWords.toFloat() else 0.0f
    }
    
    /**
     * Check for relationship-based matching (e.g., "mom" -> "Mother")
     */
    private fun checkRelationshipMatch(command: String, contactName: String): Float {
        for ((relationship, keywords) in RELATIONSHIP_KEYWORDS) {
            for (keyword in keywords) {
                if (command.contains(keyword)) {
                    // Check if contact name contains the relationship
                    if (contactName.contains(relationship, ignoreCase = true) ||
                        keywords.any { contactName.contains(it, ignoreCase = true) }) {
                        return 0.95f // High confidence for relationship matches
                    }
                }
            }
        }
        return 0.0f
    }
    
    /**
     * Calculate string similarity using Levenshtein distance
     */
    private fun calculateStringSimilarity(s1: String, s2: String): Float {
        val longer = if (s1.length > s2.length) s1 else s2
        val shorter = if (s1.length > s2.length) s2 else s1
        
        val longerLength = longer.length
        if (longerLength == 0) return 1.0f
        
        val editDistance = levenshteinDistance(longer, shorter)
        return (longerLength - editDistance) / longerLength.toFloat()
    }
    
    /**
     * Calculate Levenshtein distance between two strings
     */
    private fun levenshteinDistance(s1: String, s2: String): Int {
        val dp = Array(s1.length + 1) { IntArray(s2.length + 1) }
        
        for (i in 0..s1.length) {
            dp[i][0] = i
        }
        
        for (j in 0..s2.length) {
            dp[0][j] = j
        }
        
        for (i in 1..s1.length) {
            for (j in 1..s2.length) {
                val cost = if (s1[i - 1] == s2[j - 1]) 0 else 1
                dp[i][j] = minOf(
                    dp[i - 1][j] + 1,      // deletion
                    dp[i][j - 1] + 1,      // insertion
                    dp[i - 1][j - 1] + cost // substitution
                )
            }
        }
        
        return dp[s1.length][s2.length]
    }
    
    /**
     * Get emergency contacts for priority matching
     */
    suspend fun getEmergencyContacts(): List<ContactInfo> = withContext(Dispatchers.IO) {
        ensureContactsLoaded()
        
        // Return starred contacts and frequently contacted as emergency contacts
        return@withContext cachedContacts
            .filter { it.isStarred || it.timesContacted > 20 }
            .sortedByDescending { it.timesContacted }
            .take(10)
    }
    
    /**
     * Refresh contacts cache manually
     */
    suspend fun refreshContacts() {
        loadContactsFromDevice()
    }
    
    fun cleanup() {
        serviceScope.cancel()
        cachedContacts.clear()
        Log.i(TAG, "🧹 ContactMatchingService cleanup completed")
    }
}