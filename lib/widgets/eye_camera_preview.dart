import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../utils/core_utils.dart';

class EyeCameraPreview extends StatefulWidget {
  final CameraController? cameraController;
  final bool isVisible;
  final bool isProcessing;
  final String processingText;
  final VoidCallback? onClose;
  final double eyeSize;

  const EyeCameraPreview({
    Key? key,
    required this.cameraController,
    required this.isVisible,
    this.isProcessing = false,
    this.processingText = 'Processing with Gemma 3n...',
    this.onClose,
    this.eyeSize = 300.0,
  }) : super(key: key);

  @override
  State<EyeCameraPreview> createState() => _EyeCameraPreviewState();
}

class _EyeCameraPreviewState extends State<EyeCameraPreview>
    with TickerProviderStateMixin {
  late AnimationController _blinkController;
  late AnimationController _pulseController;
  late AnimationController _scanController;
  late AnimationController _irisController;
  
  late Animation<double> _blinkAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scanAnimation;
  late Animation<double> _irisAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _scanController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _irisController = AnimationController(
      duration: const Duration(milliseconds: 4000),
      vsync: this,
    );

    _blinkAnimation = Tween<double>(
      begin: 1.0,
      end: 0.1,
    ).animate(CurvedAnimation(
      parent: _blinkController,
      curve: const Interval(0.0, 0.1, curve: Curves.easeInOut),
    ));

    _pulseAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _scanAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scanController,
      curve: Curves.easeInOut,
    ));

    _irisAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(CurvedAnimation(
      parent: _irisController,
      curve: Curves.linear,
    ));

    // Start animations
    _pulseController.repeat(reverse: true);
    _irisController.repeat();
    
    if (widget.isProcessing) {
      _scanController.repeat();
    }
    
    // Periodic blinking
    _startBlinking();
  }

  void _startBlinking() {
    Future.delayed(Duration(milliseconds: 2000 + math.Random().nextInt(4000)), () {
      if (mounted) {
        _blinkController.forward().then((_) {
          _blinkController.reverse().then((_) {
            _startBlinking();
          });
        });
      }
    });
  }

  @override
  void didUpdateWidget(EyeCameraPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isProcessing != oldWidget.isProcessing) {
      if (widget.isProcessing) {
        _scanController.repeat();
      } else {
        _scanController.stop();
      }
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    _pulseController.dispose();
    _scanController.dispose();
    _irisController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Logger.info('🔍 EyeCameraPreview.build() Debug:');
    Logger.info('  - widget.isVisible: ${widget.isVisible}');
    Logger.info('  - widget.cameraController != null: ${widget.cameraController != null}');
    Logger.info('  - widget.cameraController?.value.isInitialized: ${widget.cameraController?.value.isInitialized}');
    
    return AnimatedOpacity(
      opacity: widget.isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 500),
      child: Container(
        width: widget.eyeSize,
        height: widget.eyeSize * 0.6, // Eye shape ratio
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Eye glow effect
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: widget.eyeSize + 20,
                    height: (widget.eyeSize * 0.6) + 20,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular((widget.eyeSize + 20) / 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FFFF).withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: const Color(0xFF9C4EFF).withOpacity(0.2),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            
            // Main eye shape with camera preview
            AnimatedBuilder(
              animation: Listenable.merge([_blinkAnimation, _irisAnimation]),
              builder: (context, child) {
                return ClipPath(
                  clipper: EyeShapeClipper(
                    blinkAmount: _blinkAnimation.value,
                    eyeWidth: widget.eyeSize,
                    eyeHeight: widget.eyeSize * 0.6,
                  ),
                  child: Container(
                    width: widget.eyeSize,
                    height: widget.eyeSize * 0.6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.eyeSize / 2),
                    ),
                    child: Stack(
                      children: [
                        // Premium camera preview with seamless integration
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(widget.eyeSize / 2),
                              gradient: widget.cameraController?.value.isInitialized == true 
                                  ? null
                                  : RadialGradient(
                                      center: Alignment.center,
                                      radius: 0.8,
                                      colors: [
                                        const Color(0xFF1A0F2E),
                                        const Color(0xFF0D1B2A),
                                        const Color(0xFF0A0A0A),
                                      ],
                                    ),
                            ),
                            child: widget.cameraController?.value.isInitialized == true
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(widget.eyeSize / 2),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(widget.eyeSize / 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.3),
                                            blurRadius: 10,
                                            spreadRadius: 2,
                                            offset: const Offset(0, 0),
                                          ),
                                        ],
                                      ),
                                      child: Transform.scale(
                                        scale: 1.15, // Perfect scale for seamless fit
                                        child: CameraPreview(widget.cameraController!),
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: RadialGradient(
                                              colors: [
                                                const Color(0xFF00FFFF).withOpacity(0.2),
                                                Colors.transparent,
                                              ],
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.camera_alt_rounded,
                                            color: const Color(0xFF00FFFF).withOpacity(0.8),
                                            size: widget.eyeSize * 0.12,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(20),
                                            color: Colors.black.withOpacity(0.3),
                                            border: Border.all(
                                              color: const Color(0xFF00FFFF).withOpacity(0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            'Initializing Vision...',
                                            style: TextStyle(
                                              color: const Color(0xFF00FFFF).withOpacity(0.9),
                                              fontSize: widget.eyeSize * 0.035,
                                              fontWeight: FontWeight.w500,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                        
                        // Iris (center circle with Gemma branding)
                        Positioned.fill(
                          child: Center(
                            child: Transform.rotate(
                              angle: _irisAnimation.value,
                              child: Container(
                                width: widget.eyeSize * 0.35,
                                height: widget.eyeSize * 0.35,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      const Color(0xFF000000).withOpacity(0.1),
                                      const Color(0xFF00FFFF).withOpacity(0.3),
                                      const Color(0xFF9C4EFF).withOpacity(0.5),
                                      const Color(0xFF000000).withOpacity(0.8),
                                    ],
                                    stops: const [0.0, 0.3, 0.7, 1.0],
                                  ),
                                  border: Border.all(
                                    color: const Color(0xFF00FFFF).withOpacity(0.6),
                                    width: 2,
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    // Iris pattern
                                    ...List.generate(8, (index) {
                                      return Positioned.fill(
                                        child: Transform.rotate(
                                          angle: (index * math.pi / 4) + _irisAnimation.value * 0.5,
                                          child: Container(
                                            margin: EdgeInsets.all(widget.eyeSize * 0.05),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: const Color(0xFF00FFFF).withOpacity(0.2),
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        
                        // Pupil (central AI indicator)
                        Positioned.fill(
                          child: Center(
                            child: Container(
                              width: widget.eyeSize * 0.15,
                              height: widget.eyeSize * 0.15,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black,
                                border: Border.all(
                                  color: widget.isProcessing 
                                      ? const Color(0xFF00FF00)
                                      : const Color(0xFF00FFFF),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: widget.isProcessing 
                                        ? const Color(0xFF00FF00).withOpacity(0.6)
                                        : const Color(0xFF00FFFF).withOpacity(0.6),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: widget.isProcessing
                                    ? SizedBox(
                                        width: widget.eyeSize * 0.08,
                                        height: widget.eyeSize * 0.08,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          valueColor: AlwaysStoppedAnimation(
                                            const Color(0xFF00FF00),
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.auto_awesome,
                                        size: widget.eyeSize * 0.06,
                                        color: const Color(0xFF00FFFF),
                                      ),
                              ),
                            ),
                          ),
                        ),
                        
                        // Scanning overlay when processing
                        if (widget.isProcessing)
                          AnimatedBuilder(
                            animation: _scanAnimation,
                            builder: (context, child) {
                              return Positioned.fill(
                                child: CustomPaint(
                                  painter: EyeScanPainter(
                                    progress: _scanAnimation.value,
                                    eyeWidth: widget.eyeSize,
                                    eyeHeight: widget.eyeSize * 0.6,
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            
            // Top status indicator
            Positioned(
              top: -25,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1426).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF00FFFF).withOpacity(0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isProcessing) ...[
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation(
                            const Color(0xFF00FFFF),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      widget.isProcessing ? 'Gemma 3n E4B' : 'ISABELLE Vision',
                      style: const TextStyle(
                        color: Color(0xFF00FFFF),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Close button
            if (widget.onClose != null)
              Positioned(
                top: -20,
                right: -15,
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1426).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF00FFFF).withOpacity(0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Color(0xFF00FFFF),
                      size: 14,
                    ),
                  ),
                ),
              ),
            
            // Bottom processing text
            if (widget.isProcessing)
              Positioned(
                bottom: -30,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1426).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF00FFFF).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    widget.processingText,
                    style: TextStyle(
                      color: const Color(0xFF00FFFF),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      shadows: [
                        Shadow(
                          color: const Color(0xFF00FFFF).withOpacity(0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class EyeShapeClipper extends CustomClipper<Path> {
  final double blinkAmount;
  final double eyeWidth;
  final double eyeHeight;

  EyeShapeClipper({
    required this.blinkAmount,
    required this.eyeWidth,
    required this.eyeHeight,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radiusX = eyeWidth / 2;
    final radiusY = (eyeHeight / 2) * blinkAmount;
    
    // Create eye shape (ellipse)
    path.addOval(Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: radiusX * 2,
      height: radiusY * 2,
    ));
    
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => true;
}

class EyeScanPainter extends CustomPainter {
  final double progress;
  final double eyeWidth;
  final double eyeHeight;

  EyeScanPainter({
    required this.progress,
    required this.eyeWidth,
    required this.eyeHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF00FFFF).withOpacity(0.0),
          const Color(0xFF00FFFF).withOpacity(0.4),
          const Color(0xFF9C4EFF).withOpacity(0.6),
          const Color(0xFF00FFFF).withOpacity(0.4),
          const Color(0xFF00FFFF).withOpacity(0.0),
        ],
        stops: const [0.0, 0.4, 0.5, 0.6, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 15));

    // Calculate scanning line position
    final lineY = size.height * progress;
    
    // Draw scanning line
    canvas.drawRect(
      Rect.fromLTWH(0, lineY - 7, size.width, 15),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}