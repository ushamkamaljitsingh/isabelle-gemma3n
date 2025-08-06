import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/constants.dart';
import 'core/config.dart';
import 'services/gemma_inference_service.dart';
import 'services/camera_service.dart';
import 'services/audio_service.dart';
import 'screens/model_loading_screen.dart';
import 'screens/role_selector_screen.dart';
import 'blind/blind_home.dart';
import 'utils/core_utils.dart';
import 'shared/storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  Logger.info('=== ISABELLE AI VISION ASSISTANT STARTUP ===');
  Logger.info('🚀 Starting ISABELLE - AI Vision Assistant for Blind Users');
  Logger.info('Platform: ${Platform.operatingSystem}');
  
  // Initialize storage
  try {
    await Storage.init();
    Logger.info('✅ Storage initialized');
  } catch (e) {
    Logger.error('❌ Failed to initialize storage: $e');
  }
  
  // Set system UI overlay style
  try {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    Logger.info('✅ System UI overlay style configured');
  } catch (e) {
    Logger.error('❌ Failed to set system UI overlay: $e');
  }
  
  Logger.info('🎯 Launching Vision Assistant...');
  runApp(const IsabelleApp());
}

class IsabelleApp extends StatelessWidget {
  const IsabelleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Logger.info('🏗️ Building ISABELLE Vision Assistant');
    
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) {
          Logger.info('🧠 Creating GemmaInferenceService provider');
          return GemmaInferenceService();
        }),
        ChangeNotifierProvider(create: (_) {
          Logger.info('📸 Creating CameraService provider');
          return CameraService();
        }),
        ChangeNotifierProvider(create: (_) {
          Logger.info('🔊 Creating AudioService provider');
          return AudioService();
        }),
      ],
      child: MaterialApp(
        title: 'ISABELLE Vision',
        theme: AppConfig().getTheme(),
        home: const AppInitializer(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({Key? key}) : super(key: key);

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isLoading = true;
  String _initializationStatus = 'Initializing ISABELLE Vision...';
  
  @override
  void initState() {
    super.initState();
    // Use post frame callback to ensure navigation happens after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    final stopwatch = Stopwatch()..start();
    Logger.info('=== APP INITIALIZATION START ===');
    
    try {
      // Check if Gemma model is available
      Logger.info('🤖 Checking Gemma model availability...');
      if (mounted) {
        setState(() {
          _initializationStatus = 'Checking AI model...';
        });
      }
      
      // Always navigate to model loading screen first
      // It will check if model exists and either download or proceed
      Logger.info('📊 Navigating to model loading screen...');
      _navigateToModelLoading();
      
    } catch (e, stackTrace) {
      Logger.error('❌ App initialization failed: $e');
      Logger.error('Stack trace: $stackTrace');
      
      setState(() {
        _initializationStatus = 'Initialization failed. Loading model...';
      });
      
      _navigateToModelLoading();
    }
    
    Logger.info('App initialization completed in ${stopwatch.elapsedMilliseconds}ms');
  }
  
  Future<void> _connectServices() async {
    if (!mounted) return;
    
    try {
      Logger.info('🔗 Connecting services to initialized Gemma...');
      
      final audioService = Provider.of<AudioService>(context, listen: false);
      final gemmaService = Provider.of<GemmaInferenceService>(context, listen: false);
      
      // Verify Gemma is already initialized (it should be from ModelLoadingScreen)
      if (gemmaService.isInitialized) {
        Logger.info('✅ Gemma service already initialized, connecting AudioService');
        // Connect AudioService to GemmaInferenceService for offline STT
        await audioService.setGemmaService(gemmaService);
        Logger.info('✅ Services connected successfully');
      } else {
        Logger.warning('⚠️ Gemma service not initialized - this should not happen');
      }
      
    } catch (e) {
      Logger.error('❌ Failed to connect services: $e');
    }
  }
  
  Future<void> _initializeOfflineServices() async {
    if (!mounted) return;
    
    setState(() {
      _initializationStatus = 'Initializing AI services...';
    });
    
    try {
      Logger.info('🔊 Initializing offline services...');
      
      final audioService = Provider.of<AudioService>(context, listen: false);
      final gemmaService = Provider.of<GemmaInferenceService>(context, listen: false);
      
      // Initialize GemmaInferenceService
      if (!gemmaService.isInitialized) {
        Logger.info('🧠 Initializing Gemma inference service...');
        final gemmaInitSuccess = await gemmaService.initialize();
        if (!gemmaInitSuccess) {
          Logger.error('❌ Failed to initialize Gemma service');
        } else {
          Logger.info('✅ Gemma service initialized successfully');
        }
      }
      
      // Connect AudioService to GemmaInferenceService for offline STT
      await audioService.setGemmaService(gemmaService);
      
      Logger.info('✅ Offline services initialized');
      
    } catch (e) {
      Logger.error('❌ Failed to initialize offline services: $e');
    }
  }
  
  void _navigateToModelLoading() {
    if (!mounted) return;
    
    Logger.info('🔄 NAVIGATION: Pushing ModelLoadingScreen');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ModelLoadingScreen(
          onComplete: () {
            Logger.info('🔥 onComplete callback triggered!');
            Logger.info('✅ Model loading completed - navigating immediately');
            try {
              // Navigate immediately, connect services after navigation
              _navigateToVisionAssistant();
              Logger.info('✅ Navigation call completed');
              
              // Connect services in the background after navigation
              Future.microtask(() async {
                try {
                  await _connectServices();
                  Logger.info('✅ Services connected in background');
                } catch (e) {
                  Logger.error('❌ Background service connection failed: $e');
                }
              });
            } catch (e, stackTrace) {
              Logger.error('❌ Error in onComplete callback: $e');
              Logger.error('❌ Stack trace: $stackTrace');
            }
          },
        ),
      ),
    );
  }
  
  void _navigateToVisionAssistant() {
    Logger.info('🎯 _navigateToVisionAssistant called');
    Logger.info('🔍 Widget mounted: $mounted');
    
    if (!mounted) {
      Logger.error('❌ Widget not mounted, cannot navigate');
      return;
    }
    
    try {
      Logger.info('🎯 NAVIGATION: About to push RoleSelectorScreen');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const RoleSelectorScreen()),
      );
      Logger.info('✅ RoleSelectorScreen navigation completed successfully');
    } catch (e, stackTrace) {
      Logger.error('❌ Navigation to RoleSelectorScreen failed: $e');
      Logger.error('❌ Stack trace: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.white,
              Colors.purple.shade50,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue.shade600,
                      Colors.purple.shade600,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.shade200,
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.remove_red_eye,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // App Title
              const Text(
                'ISABELLE',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  color: Color(0xFF2D3748),
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Subtitle
              Text(
                'AI Vision Assistant',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Technology badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Text(
                  'Powered by AI • Offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              
              const SizedBox(height: 60),
              
              // Loading Indicator
              Container(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.blue.shade600,
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Status Text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  _initializationStatus,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Feature highlight
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.visibility,
                        color: Colors.blue.shade600,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vision Description',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          Text(
                            'AI describes what you\'re looking at',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}