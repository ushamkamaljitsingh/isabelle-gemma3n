import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/core_utils.dart';
import '../blind/blind_home.dart';
import '../deaf/deaf_home.dart';

class RoleSelectorScreen extends StatefulWidget {
  const RoleSelectorScreen({Key? key}) : super(key: key);

  @override
  State<RoleSelectorScreen> createState() => _RoleSelectorScreenState();
}

class _RoleSelectorScreenState extends State<RoleSelectorScreen> 
    with TickerProviderStateMixin {
  late AnimationController _starsController;
  late AnimationController _pulseController;
  
  late Animation<double> _starsAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _starsController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _starsAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _starsController,
      curve: Curves.linear,
    ));
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _starsController.repeat();
    _pulseController.repeat(reverse: true);
  }

  void _selectBlindMode() {
    Logger.info('👁️ User selected Blind Mode (Vision Assistant)');
    HapticFeedback.lightImpact();
    
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const BlindHome()),
    );
  }

  void _selectDeafMode() {
    Logger.info('👂 User selected Deaf Mode (Emergency Sound Detection)');
    HapticFeedback.lightImpact();
    
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const DeafHome()),
    );
  }

  @override
  void dispose() {
    _starsController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLandscape = screenSize.width > screenSize.height;
    
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 2.0,
            colors: [
              Color(0xFF0A0A0A),
              Color(0xFF1A0F2E),
              Color(0xFF0D1B2A),
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
                  painter: RoleSelectorStarsPainter(_starsAnimation.value),
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
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.1),
                          Colors.white.withOpacity(0.05),
                        ],
                      ),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              Color(0xFF00FFFF),
                              Color(0xFF0080FF),
                              Color(0xFF8A2BE2),
                            ],
                          ).createShader(bounds),
                          child: const Text(
                            'ISABELLE',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Choose Your Assistance Mode',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF00CCAA),
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Mode Selection Cards
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      child: isLandscape 
                          ? Row(
                              children: [
                                Expanded(child: _buildBlindModeCard()),
                                const SizedBox(width: 20),
                                Expanded(child: _buildDeafModeCard()),
                              ],
                            )
                          : Column(
                              children: [
                                Expanded(child: _buildBlindModeCard()),
                                const SizedBox(height: 20),
                                Expanded(child: _buildDeafModeCard()),
                              ],
                            ),
                    ),
                  ),
                  
                  // Footer
                  Container(
                    margin: const EdgeInsets.all(20),
                    child: Text(
                      'Both modes work completely offline with AI',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                      ),
                      textAlign: TextAlign.center,
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

  Widget _buildBlindModeCard() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return GestureDetector(
          onTap: _selectBlindMode,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF00D2FF).withOpacity(0.2),
                  const Color(0xFF0080FF).withOpacity(0.1),
                ],
              ),
              border: Border.all(
                color: const Color(0xFF00D2FF).withOpacity(0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D2FF).withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Eye icon with pulse animation
                  Transform.scale(
                    scale: 1.0 + (_pulseAnimation.value - 1.0) * 0.1,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF00D2FF),
                            const Color(0xFF0080FF),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00D2FF).withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.remove_red_eye_rounded,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF00D2FF), Color(0xFF0080FF)],
                    ).createShader(bounds),
                    child: const Text(
                      'BLIND MODE',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  const Text(
                    'AI Vision Assistant',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF00CCAA),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Text(
                    '• Describe what you\'re looking at\n'
                    '• Read text from images\n'
                    '• Voice commands\n'
                    '• Real-time scene description',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.8),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDeafModeCard() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return GestureDetector(
          onTap: _selectDeafMode,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFFF6B35).withOpacity(0.2),
                  const Color(0xFFFF3B71).withOpacity(0.1),
                ],
              ),
              border: Border.all(
                color: const Color(0xFFFF6B35).withOpacity(0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B35).withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Shield icon with pulse animation
                  Transform.scale(
                    scale: 1.0 + (_pulseAnimation.value - 1.0) * 0.1,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFFF6B35),
                            const Color(0xFFFF3B71),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF6B35).withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFFFF6B35), Color(0xFFFF3B71)],
                    ).createShader(bounds),
                    child: const Text(
                      'DEAF MODE',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  const Text(
                    'Emergency Sound Detection',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFFFFAAAA),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Text(
                    '• 🚨 Fire alarm detection\n'
                    '• 🚓 Siren & emergency sounds\n'
                    '• 📞 Auto-call emergency contacts\n'
                    '• 💥 Glass breaking alerts',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.8),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class RoleSelectorStarsPainter extends CustomPainter {
  final double animationValue;

  RoleSelectorStarsPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);
    
    final starColors = [
      const Color(0xFF00FFFF),
      const Color(0xFF8A2BE2),
      const Color(0xFF00D2FF),
      const Color(0xFFFF6B35),
    ];
    
    for (int i = 0; i < 80; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final twinkle = (math.sin(animationValue * 2 * math.pi + i * 0.5) + 1) / 2;
      
      final paint = Paint()
        ..color = starColors[i % starColors.length].withOpacity(twinkle * 0.6);
      
      canvas.drawCircle(Offset(x, y), 1.0 + twinkle * 0.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}