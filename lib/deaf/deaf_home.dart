import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/core_utils.dart';
import '../services/emergency_sound_service.dart';

class DeafHome extends StatefulWidget {
  const DeafHome({Key? key}) : super(key: key);

  @override
  State<DeafHome> createState() => _DeafHomeState();
}

class _DeafHomeState extends State<DeafHome> with TickerProviderStateMixin {
  final EmergencySoundService _emergencyService = EmergencySoundService();
  
  // Animation controllers
  late AnimationController _starsController;
  late AnimationController _alertController;
  late AnimationController _emergencyController;
  
  late Animation<double> _starsAnimation;
  late Animation<double> _alertPulse;
  late Animation<double> _emergencyPulse;
  
  // State
  bool _isListening = false;
  List<SoundAlert> _recentSounds = [];
  SoundAlert? _lastAlert;
  EmergencySound? _currentEmergency;
  List<EmergencyCall> _emergencyCalls = [];
  String _status = 'Ready to protect you';
  
  // Stream subscriptions
  StreamSubscription<SoundAlert>? _soundSubscription;
  StreamSubscription<EmergencySound>? _emergencySubscription;
  StreamSubscription<EmergencyCall>? _callSubscription;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _setupServiceListeners();
    _startEmergencyMonitoring();
  }

  void _setupAnimations() {
    _starsController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );
    
    _alertController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _emergencyController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _starsAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _starsController,
      curve: Curves.linear,
    ));
    
    _alertPulse = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _alertController,
      curve: Curves.elasticOut,
    ));
    
    _emergencyPulse = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _emergencyController,
      curve: Curves.easeInOut,
    ));
    
    _starsController.repeat();
  }
  
  void _setupServiceListeners() {
    // Listen for general sound alerts
    _soundSubscription = _emergencyService.onSoundAlert.listen((alert) {
      setState(() {
        _lastAlert = alert;
        _recentSounds.insert(0, alert);
        if (_recentSounds.length > 10) _recentSounds.removeLast();
        _status = '${alert.emoji} ${alert.description}';
      });
      
      // Trigger alert animation
      _alertController.forward().then((_) => _alertController.reverse());
      
      // Haptic feedback for important sounds
      if (alert.level == AlertLevel.high || alert.level == AlertLevel.emergency) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.lightImpact();
      }
    });
    
    // Listen for EMERGENCY sounds
    _emergencySubscription = _emergencyService.onEmergencySound.listen((emergency) {
      setState(() {
        _currentEmergency = emergency;
        _status = '🚨 EMERGENCY: ${emergency.description}';
      });
      
      // Strong emergency animations
      _emergencyController.repeat(reverse: true);
      
      // Strong haptic feedback
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 100), () => HapticFeedback.heavyImpact());
      Future.delayed(const Duration(milliseconds: 200), () => HapticFeedback.heavyImpact());
      
      Logger.warning('🚨 EMERGENCY UI ALERT: ${emergency.description}');
    });
    
    // Listen for emergency calls
    _callSubscription = _emergencyService.onEmergencyCall.listen((call) {
      setState(() {
        _emergencyCalls.insert(0, call);
        if (_emergencyCalls.length > 5) _emergencyCalls.removeLast();
      });
      
      Logger.warning('📞 EMERGENCY CALL UI: ${call.description}');
    });
  }
  
  Future<void> _startEmergencyMonitoring() async {
    try {
      final success = await _emergencyService.startSoundDetection();
      setState(() {
        _isListening = success;
        _status = success ? 'Monitoring for emergency sounds...' : 'Failed to start monitoring';
      });
      
      if (success) {
        Logger.info('✅ Emergency sound monitoring started');
      } else {
        Logger.error('❌ Failed to start emergency sound monitoring');
      }
    } catch (e) {
      Logger.error('Error starting emergency monitoring: $e');
      setState(() {
        _status = 'Error starting monitoring';
      });
    }
  }
  
  Future<void> _stopEmergencyMonitoring() async {
    try {
      final success = await _emergencyService.stopSoundDetection();
      setState(() {
        _isListening = !success;
        _status = success ? 'Monitoring stopped' : 'Failed to stop monitoring';
        _currentEmergency = null;
      });
      
      _emergencyController.stop();
    } catch (e) {
      Logger.error('Error stopping emergency monitoring: $e');
    }
  }
  
  // Production mode - real detection only
  // Test features removed for production deployment
  
  Future<void> _clearEmergency() async {
    setState(() {
      _currentEmergency = null;
      _status = 'Emergency cleared';
    });
    _emergencyController.stop();
  }

  @override
  void dispose() {
    _starsController.dispose();
    _alertController.dispose();
    _emergencyController.dispose();
    _soundSubscription?.cancel();
    _emergencySubscription?.cancel();
    _callSubscription?.cancel();
    _emergencyService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 2.0,
            colors: [
              _currentEmergency != null ? const Color(0xFF2D0A0A) : const Color(0xFF0A0A0A),
              _currentEmergency != null ? const Color(0xFF4A1515) : const Color(0xFF1A0F2E),
              _currentEmergency != null ? const Color(0xFF1A0505) : const Color(0xFF0D1B2A),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Animated starry background
            AnimatedBuilder(
              animation: _starsAnimation,
              builder: (context, child) {
                return CustomPaint(
                  painter: DeafModeStarsPainter(_starsAnimation.value, _currentEmergency != null),
                  size: Size.infinite,
                );
              },
            ),
            
            SafeArea(
              child: Column(
                children: [
                  // Header
                  Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          _currentEmergency != null 
                              ? const Color(0xFFFF4444).withOpacity(0.2)
                              : Colors.white.withOpacity(0.1),
                          _currentEmergency != null 
                              ? const Color(0xFFAA0000).withOpacity(0.1)
                              : Colors.white.withOpacity(0.05),
                        ],
                      ),
                      border: Border.all(
                        color: _currentEmergency != null 
                            ? const Color(0xFFFF4444).withOpacity(0.5)
                            : Colors.white.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: _currentEmergency != null 
                                ? [const Color(0xFFFF4444), const Color(0xFFFFAAAA)]
                                : [const Color(0xFF00FFFF), const Color(0xFF8A2BE2)],
                          ).createShader(bounds),
                          child: const Text(
                            'ISABELLE GUARDIAN',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Emergency Sound Detection • Deaf Mode',
                          style: TextStyle(
                            fontSize: 12,
                            color: _currentEmergency != null 
                                ? const Color(0xFFFFAAAA)
                                : const Color(0xFF00CCAA),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Emergency Alert Section
                  if (_currentEmergency != null)
                    AnimatedBuilder(
                      animation: _emergencyPulse,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _emergencyPulse.value,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFFF4444),
                                  Color(0xFFAA0000),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF4444).withOpacity(0.5),
                                  blurRadius: 30,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '🚨 EMERGENCY DETECTED',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '${_currentEmergency!.emoji} ${_currentEmergency!.description}',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Confidence: ${(_currentEmergency!.confidence * 100).toInt()}%',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _clearEmergency,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFFAA0000),
                                  ),
                                  child: const Text('CLEAR EMERGENCY'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  
                  const SizedBox(height: 20),
                  
                  // Status Section
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.15),
                          Colors.white.withOpacity(0.05),
                        ],
                      ),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isListening 
                                    ? const Color(0xFF00FF41)
                                    : const Color(0xFFFF6B35),
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isListening 
                                        ? const Color(0xFF00FF41)
                                        : const Color(0xFFFF6B35)).withOpacity(0.6),
                                    blurRadius: 12,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _isListening ? 'MONITORING ACTIVE' : 'MONITORING INACTIVE',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _isListening 
                                    ? const Color(0xFF00FF41)
                                    : const Color(0xFFFF6B35),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _status,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Emergency Calls Log
                  if (_emergencyCalls.isNotEmpty) ...[
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Emergency Calls',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...(_emergencyCalls.take(3).map((call) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: call.status == 'failed' 
                            ? const Color(0xFFFF4444).withOpacity(0.2)
                            : const Color(0xFF00FF41).withOpacity(0.2),
                        border: Border.all(
                          color: call.status == 'failed' 
                              ? const Color(0xFFFF4444)
                              : const Color(0xFF00FF41),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            call.status == 'failed' ? '❌' : '📞',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              call.description,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          Text(
                            call.phoneNumber,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ))),
                    const SizedBox(height: 20),
                  ],
                  
                  // Control Buttons
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Main toggle button
                          GestureDetector(
                            onTap: _isListening ? _stopEmergencyMonitoring : _startEmergencyMonitoring,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    _isListening 
                                        ? const Color(0xFF00FF41)
                                        : const Color(0xFFFF6B35),
                                    _isListening 
                                        ? const Color(0xFF00AA22)
                                        : const Color(0xFFAA3300),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isListening 
                                        ? const Color(0xFF00FF41)
                                        : const Color(0xFFFF6B35)).withOpacity(0.4),
                                    blurRadius: 30,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isListening ? Icons.shield : Icons.shield_outlined,
                                size: 48,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 30),
                          
                          // Production mode - real emergency detection only
                          Text(
                            _isListening 
                                ? 'Actively monitoring for emergency sounds'
                                : 'Tap shield to start monitoring',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DeafModeStarsPainter extends CustomPainter {
  final double animationValue;
  final bool isEmergency;

  DeafModeStarsPainter(this.animationValue, this.isEmergency);

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);
    
    final starColors = isEmergency 
        ? [const Color(0xFFFF4444), const Color(0xFFFFAAAA), const Color(0xFFFF8888)]
        : [const Color(0xFF00FFFF), const Color(0xFF8A2BE2), const Color(0xFF00D2FF)];
    
    for (int i = 0; i < 100; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final twinkle = (math.sin(animationValue * 2 * math.pi + i * 0.5) + 1) / 2;
      
      final paint = Paint()
        ..color = starColors[i % starColors.length].withOpacity(twinkle * 0.8);
      
      canvas.drawCircle(Offset(x, y), 1.5 + twinkle, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}