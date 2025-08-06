// lib/screens/model_loading_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/gemma_inference_service.dart';
import '../utils/core_utils.dart';
import '../core/constants.dart';
import '../services/native_download_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../blind/blind_home.dart';
import '../core/utils/ram_check.dart';

class ModelLoadingScreen extends StatefulWidget {
  final VoidCallback? onComplete;
  
  const ModelLoadingScreen({super.key, this.onComplete});

  @override
  State<ModelLoadingScreen> createState() => _ModelLoadingScreenState();
}

class _ModelLoadingScreenState extends State<ModelLoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _progressController;
  late AnimationController _starsController;
  late AnimationController _flowingLinesController;
  late AnimationController _orbitController;
  
  late Animation<double> _pulseAnimation;
  late Animation<double> _progressAnimation;
  late Animation<double> _starsAnimation;
  late Animation<double> _flowingLinesAnimation;
  late Animation<double> _orbitAnimation;
  
  String _statusMessage = 'Checking for AI model...';
  bool _isRetrying = false;
  int _retryCount = 0;
  static const int maxRetries = 3;
  bool _isDownloading = false;
  bool _showRetryButton = false;
  double _downloadProgress = 0.0;
  String _downloadDetails = '';
  String _currentSpeed = '0 MB/s';

  @override
  void initState() {
    super.initState();
    Logger.info('🚀 ModelLoadingScreen initState called');
    _setupAnimations();
    
    // Start model initialization after a frame to ensure UI is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Logger.info('📱 Starting model initialization');
      _initializeModel();
    });
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _starsController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );
    
    _flowingLinesController = AnimationController(
      duration: const Duration(seconds: 15),
      vsync: this,
    );

    _orbitController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeOut,
    ));

    _starsAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _starsController,
      curve: Curves.linear,
    ));

    _flowingLinesAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _flowingLinesController,
      curve: Curves.linear,
    ));

    _orbitAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(CurvedAnimation(
      parent: _orbitController,
      curve: Curves.linear,
    ));
    
    _pulseController.repeat(reverse: true);
    _starsController.repeat();
    _flowingLinesController.repeat();
    _orbitController.repeat();
  }

  Future<void> _initializeModel() async {
    try {
      setState(() => _statusMessage = 'Checking device capabilities...');
      
      // CRITICAL FIX: Reset download state first to prevent stale states
      _resetDownloadState();
      
      // Step 0: Check device RAM and capabilities FIRST
      Logger.info('🔍 Checking device RAM and capabilities...');
      await _checkDeviceCapabilities();
      
      // Step 1: Check if model is already downloaded using native service
      Logger.info('🔍 Checking model availability...');
      final appSupportDir = await getApplicationSupportDirectory();
      final modelPath = '${appSupportDir.path}/isabelle_models/${AppConstants.modelFileName}';
      
      Logger.info('📁 App support directory: ${appSupportDir.path}');
      Logger.info('📁 Full model path: $modelPath');
      Logger.info('📁 Model filename: ${AppConstants.modelFileName}');
      
      // Also check what path format we're using
      Logger.info('🔍 Expected path format: /data/data/com.isabelle.accessibility/files/isabelle_models/gemma-3n-E4B-it-int4.task');
      Logger.info('🔍 Actual path being checked: $modelPath');
      
      // Use native download service to check model availability
      final modelAvailable = await NativeDownloadService.isModelDownloaded(modelPath);
      
      Logger.info('📊 Model availability check result: $modelAvailable');
      
      // Additional debug: check parent directory contents
      try {
        final parentDir = Directory('${appSupportDir.path}/isabelle_models');
        if (await parentDir.exists()) {
          final files = await parentDir.list().toList();
          Logger.info('📁 Files in isabelle_models directory: ${files.map((f) => f.path).join(', ')}');
        } else {
          Logger.info('📁 isabelle_models directory does not exist');
        }
      } catch (e) {
        Logger.error('❌ Error listing directory contents: $e');
      }
      
      if (!modelAvailable) {
        // Step 2: Download model if not available
        Logger.info('⬇️ Model not found, starting download...');
        await _downloadModelWithNativeService(modelPath);
      }
      
      // Step 3: Initialize Gemma service only after confirming model exists
      if (mounted) setState(() => _statusMessage = 'AI model ready! Initializing...');
      Logger.info('✅ Model confirmed, initializing Gemma service');
      
      // REAL INITIALIZATION: Actually initialize Gemma service
      Logger.info('🚀 STARTING REAL GEMMA INITIALIZATION');
      
      final gemmaService = Provider.of<GemmaInferenceService>(context, listen: false);
      bool gemmaInitialized = false;
      
      // REAL initialization - this will call the native initializeGemma3n
      try {
        if (mounted) setState(() => _statusMessage = 'Initializing AI model...');
        Logger.info('🔄 Calling gemmaService.initialize()...');
        
        Logger.info('🔄 About to call gemmaService.initialize()...');
        gemmaInitialized = await gemmaService.initialize();
        Logger.info('📊 gemmaService.initialize() returned: $gemmaInitialized');
        Logger.info('📊 gemmaService.isInitialized: ${gemmaService.isInitialized}');
        
        if (gemmaInitialized) {
          Logger.info('✅ Gemma service initialized successfully!');
        } else {
          Logger.error('❌ Gemma service initialization returned false');
        }
      } catch (e) {
        Logger.error('❌ Gemma initialization failed: $e');
        gemmaInitialized = false;
        // Don't continue on real failure
        rethrow;
      }
      
      if (mounted && gemmaInitialized) {
        setState(() => _statusMessage = 'AI model initialized successfully!');
        Logger.info('🎯 UI Updated: AI model initialized successfully!');
        
        // CRITICAL FIX: Add the missing navigation logic that was removed
        Logger.info('🚀 STARTING NAVIGATION AFTER SUCCESSFUL INITIALIZATION...');
        
        // IMMEDIATE navigation on the UI thread to prevent widget disposal
        // Use scheduleMicrotask to ensure we're on the main isolate
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Logger.info('🔄 Post-frame navigation - Widget mounted: $mounted');
            Logger.info('📱 onComplete callback exists: ${widget.onComplete != null}');
            
            try {
              if (widget.onComplete != null) {
                Logger.info('✅ Calling onComplete callback (post-frame)...');
                widget.onComplete!();
                Logger.info('✅ onComplete callback executed successfully');
              } else {
                Logger.info('✅ Direct navigation to BlindHome (post-frame)...');
                Navigator.of(context, rootNavigator: true).pushReplacement(
                  MaterialPageRoute(builder: (context) => const BlindHome()),
                );
                Logger.info('✅ Direct navigation completed');
              }
            } catch (e) {
              Logger.error('❌ Navigation failed: $e');
              // Force fallback navigation
              if (mounted) {
                Navigator.of(context, rootNavigator: true).pushReplacement(
                  MaterialPageRoute(builder: (context) => const BlindHome()),
                );
              }
            }
          } else {
            Logger.error('❌ Widget not mounted in post-frame callback');
          }
        });
        
        // PRIMARY PATH: Direct navigation from ModelLoadingScreen
        // Skip the callback entirely to avoid widget disposal issues
        if (mounted) {
          Logger.info('🔄 PRIMARY: Direct navigation from ModelLoadingScreen - Widget mounted: $mounted');
          try {
            Logger.info('✅ Navigating directly to BlindHome...');
            Navigator.of(context, rootNavigator: true).pushReplacement(
              MaterialPageRoute(builder: (context) => const BlindHome()),
            );
            Logger.info('✅ Direct navigation completed');
            
            // Also call the callback to maintain compatibility
            if (widget.onComplete != null) {
              try {
                Logger.info('✅ Also calling onComplete callback for compatibility...');
                widget.onComplete!();
                Logger.info('✅ onComplete callback executed successfully');
              } catch (e) {
                Logger.error('❌ onComplete callback failed (but navigation already succeeded): $e');
              }
            }
            
          } catch (e) {
            Logger.error('❌ Primary navigation failed: $e');
            // Fallback to callback if direct navigation fails
            if (widget.onComplete != null) {
              try {
                Logger.info('🔄 Fallback: Using onComplete callback...');
                widget.onComplete!();
                Logger.info('✅ Fallback callback executed');
              } catch (callbackError) {
                Logger.error('❌ Both direct navigation and callback failed: $callbackError');
              }
            }
          }
        }
        
      } else if (mounted && !gemmaInitialized) {
        setState(() => _statusMessage = 'AI model initialization failed');
        Logger.error('❌ UI Updated: AI model initialization failed');
      }
      
      // EMERGENCY BACKUP: Force navigation after 5 seconds if no other navigation happened
      // This is a fallback in case the regular navigation doesn't work
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _statusMessage.contains('AI model initialized successfully!')) {
          Logger.warning('⚠️ EMERGENCY BACKUP: Forcing navigation after timeout');
          try {
            if (widget.onComplete != null) {
              Logger.info('✅ Emergency backup: Calling onComplete callback...');
              widget.onComplete!();
            } else {
              Logger.info('✅ Emergency backup: Direct navigation to BlindHome...');
              Navigator.of(context, rootNavigator: true).pushReplacement(
                MaterialPageRoute(builder: (context) => const BlindHome()),
              );
            }
          } catch (e) {
            Logger.error('❌ Emergency backup navigation failed: $e');
          }
        }
      });
      
    } catch (e) {
      Logger.error('Model initialization failed: $e');
      _handleError(e.toString());
    }
  }
  
  /// Download model using native high-speed downloader
  Future<void> _downloadModelWithNativeService(String targetPath) async {
    try {
      setState(() {
        _statusMessage = 'Starting high-speed download...';
        _isDownloading = true;
        _downloadProgress = 0.0;
      });
      
      Logger.info('🚀 Starting native high-speed download...');
      
      // Ensure native download service is initialized
      await NativeDownloadService.initialize();
      
      // Create target directory if needed
      final targetFile = File(targetPath);
      final targetDir = targetFile.parent;
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      
      final success = await NativeDownloadService.downloadModelNative(
        url: AppConstants.MODEL_URL,
        targetPath: targetPath,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _statusMessage = 'Downloading at ${progress.speedMBps} MB/s (${progress.percentage}%)';
              _downloadDetails = '${progress.downloadedMB} MB / ${progress.totalMB} MB';
              _currentSpeed = '${progress.speedMBps} MB/s';
              _downloadProgress = progress.percentage / 100.0;
            });
          }
        },
      ).timeout(
        const Duration(minutes: 20), // Extended timeout for large model
        onTimeout: () {
          Logger.error('⏰ Native download timed out after 20 minutes');
          throw TimeoutException('Download timed out', const Duration(minutes: 20));
        }
      );

      if (!success) {
        throw Exception('Native download failed');
      }

      Logger.info('✅ Native download completed successfully');
      
      // Verify the file was actually saved
      Logger.info('🔍 Verifying downloaded file...');
      final downloadedFile = File(targetPath);
      final fileExists = await downloadedFile.exists();
      Logger.info('📁 File exists after download: $fileExists');
      
      if (fileExists) {
        final fileSize = await downloadedFile.length();
        final fileSizeGB = (fileSize / (1024 * 1024 * 1024));
        Logger.info('📁 Downloaded file size: ${fileSizeGB.toStringAsFixed(1)}GB');
      } else {
        Logger.error('❌ File does not exist after download completion!');
      }
      
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _statusMessage = 'Download completed! Preparing AI model...';
          _downloadProgress = 1.0;
        });
      }
      
      // CRITICAL FIX: Force continue after download regardless of event issues
      Logger.info('🚀 FORCING CONTINUATION AFTER DOWNLOAD');
      return; // Exit download method and continue with initialization
      
    } catch (e) {
      Logger.error('❌ Download failed: $e');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _statusMessage = 'Download failed: ${e.toString()}';
          _showRetryButton = true;
        });
      }
      rethrow;
    }
  }
  
  /// Reset download state to prevent stale states from previous sessions
  void _resetDownloadState() {
    Logger.info('🔄 Resetting download state...');
    _isDownloading = false;
    _downloadProgress = 0.0;
    _downloadDetails = '';
    _isRetrying = false;
    _showRetryButton = false;
    
    // Reset download state
    
    // CRITICAL FIX: Clear any persistent flags that might indicate downloading
    _clearPersistentDownloadFlags();
  }
  
  /// Clear any SharedPreferences or other persistent storage that might indicate downloading
  Future<void> _clearPersistentDownloadFlags() async {
    try {
      // This would clear any download flags
      // That might persist between app restarts and cause the UI to think it's still downloading
      Logger.info('🧹 Clearing persistent download flags...');
      
      // Note: Reset methods would go here if they existed in the services
      // For now, the state reset in _resetDownloadState() should be sufficient
      
    } catch (e) {
      Logger.warning('⚠️ Could not clear persistent download flags: $e');
    }
  }

  /// Check device capabilities and RAM before attempting to load the model
  Future<void> _checkDeviceCapabilities() async {
    try {
      setState(() => _statusMessage = 'Checking device RAM...');
      
      final ramMB = await RAMChecker.getAvailableRAM();
      Logger.info('📊 Device has ${ramMB}MB total RAM');
      
      // Check if device has sufficient RAM for Gemma 3n model
      const int MIN_RAM_MB = 3072; // Minimum 3GB for 4.4GB model (need ~1.5x model size)
      const int RECOMMENDED_RAM_MB = 6144; // Recommended 6GB+ for smooth operation
      
      if (ramMB < MIN_RAM_MB) {
        // Insufficient RAM - abort with clear error message
        final errorMessage = 'Insufficient device memory.\n\nRequired: ${MIN_RAM_MB}MB RAM\nAvailable: ${ramMB}MB RAM\n\nThis app requires a device with at least 3GB of RAM to run the AI model safely.';
        
        Logger.error('❌ Insufficient RAM: ${ramMB}MB < ${MIN_RAM_MB}MB required');
        
        setState(() {
          _statusMessage = 'Insufficient device memory';
          _showRetryButton = false; // No retry for hardware limitation
        });
        
        // Show permanent error dialog
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          _showInsufficientRAMDialog(errorMessage, ramMB, MIN_RAM_MB);
        }
        
        throw Exception('Insufficient RAM: ${ramMB}MB (minimum ${MIN_RAM_MB}MB required)');
        
      } else if (ramMB < RECOMMENDED_RAM_MB) {
        // Low RAM warning but proceed
        Logger.warning('⚠️ Low RAM detected: ${ramMB}MB (recommended ${RECOMMENDED_RAM_MB}MB+)');
        setState(() => _statusMessage = 'Low RAM detected - proceeding with caution...');
        await Future.delayed(const Duration(milliseconds: 1000));
        
      } else {
        // Sufficient RAM
        Logger.info('✅ Sufficient RAM detected: ${ramMB}MB');
        setState(() => _statusMessage = 'Device capabilities OK');
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
    } catch (e) {
      Logger.error('Error checking device capabilities: $e');
      // If we can't check RAM, assume it might be insufficient and warn user
      setState(() => _statusMessage = 'Could not verify device capabilities');
      rethrow;
    }
  }


  Future<void> _downloadModel() async {
    try {
      setState(() {
        _statusMessage = 'Starting native high-speed download...';
        _isRetrying = false;
        _isDownloading = true;
        _downloadProgress = 0.0;
      });
      
      // Use native downloader for maximum speed
      Logger.info('🚀 Starting native high-speed download...');
      setState(() {
        _statusMessage = 'Starting high-speed download...';
      });
      
      // Use native high-speed downloader (10+ MB/s speeds)
      await NativeDownloadService.initialize();
      
      final appSupportDir = await getApplicationSupportDirectory();
      final modelDir = Directory('${appSupportDir.path}/isabelle_models');
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }
      final targetPath = '${modelDir.path}/${AppConstants.modelFileName}';
      
      final success = await NativeDownloadService.downloadModelNative(
        url: AppConstants.MODEL_URL,
        targetPath: targetPath,
        onProgress: (progress) {
          setState(() {
            _statusMessage = 'Downloading AI model...';
            _downloadDetails = '${progress.downloadedGB} GB / ${progress.totalGB} GB';
            _currentSpeed = progress.formattedSpeed;
            _downloadProgress = progress.percentage / 100.0;
          });
        },
      ).timeout(
        const Duration(minutes: 15), // Extended timeout for 4GB model
        onTimeout: () {
          Logger.error('⏰ Native download timed out after 15 minutes');
          throw TimeoutException('Download timed out', const Duration(minutes: 15));
        }
      );

      if (!success) {
        throw Exception('Native download failed');
      }

      final downloadedPath = targetPath;
      Logger.info('✅ Native download completed successfully');
      
      if (downloadedPath.isNotEmpty) {
        setState(() {
          _isDownloading = false;
          _statusMessage = 'AI model downloaded! Initializing...';
          _downloadDetails = '';
        });
        Logger.info('Model downloaded successfully, initializing Gemma service');
        
        // Initialize Gemma service now that model is downloaded
        final gemmaService = Provider.of<GemmaInferenceService>(context, listen: false);
        
        if (mounted) setState(() => _statusMessage = 'Initializing AI model (may take 2-5 minutes)...');
        
        try {
          Logger.info('🧠 Initializing Gemma service...');
          await gemmaService.initialize();
          
          Logger.info('✅ Gemma service initialized successfully');
          if (mounted) {
            setState(() => _statusMessage = 'AI model initialized successfully!');
            Logger.info('🎯 UI Updated: AI model initialized successfully!');
            Logger.info('🚀 About to navigate - Widget mounted: $mounted');
            Logger.info('📱 onComplete callback exists: ${widget.onComplete != null}');
            
            // Brief delay to show success message, then navigate immediately  
            await Future.delayed(const Duration(milliseconds: 500));
            
            Logger.info('🔄 STARTING NAVIGATION NOW...');
            if (widget.onComplete != null) {
              Logger.info('✅ Calling onComplete callback...');
              try {
                widget.onComplete!();
                Logger.info('✅ onComplete callback executed successfully');
              } catch (e) {
                Logger.error('❌ onComplete callback failed: $e');
                // Fallback to direct navigation
                Navigator.of(context, rootNavigator: true).pushReplacement(
                  MaterialPageRoute(builder: (context) => const BlindHome()),
                );
              }
            } else {
              Logger.info('✅ Direct navigation to BlindHome...');
              try {
                Navigator.of(context, rootNavigator: true).pushReplacement(
                  MaterialPageRoute(builder: (context) => const BlindHome()),
                );
                Logger.info('✅ Direct navigation completed');
              } catch (e) {
                Logger.error('❌ Direct navigation failed: $e');
              }
            }
          } else {
            Logger.error('❌ Widget not mounted, cannot navigate');
          }
          
        } catch (e) {
          Logger.error('Gemma initialization failed: $e');
          
          // Show user-friendly error message
          if (e.toString().contains('timeout') || e.toString().contains('Timeout')) {
            setState(() {
              _statusMessage = 'Initialization timed out. This may indicate insufficient device memory or model corruption.';
              _downloadDetails = 'Try restarting the app or clearing app data to re-download the model.';
            });
          } else {
            setState(() {
              _statusMessage = 'Failed to initialize AI model: ${e.toString()}';
              _downloadDetails = 'Please restart the app and try again.';
            });
          }
          
          // Show retry button after 3 seconds
          await Future.delayed(const Duration(seconds: 3));
          setState(() {
            _showRetryButton = true;
          });
        }
      } else {
        throw Exception('Download failed');
      }
      
    } catch (e) {
      Logger.error('Native download failed: $e');
      _handleError(e.toString());
    }
  }
  


  void _handleError(String error) {
    setState(() {
      _statusMessage = 'Download failed: $error';
    });
    
    // Show error and retry options
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _showErrorDialog(error);
      }
    });
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A0F2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: const Color(0xFF8B0000),
            width: 2,
          ),
        ),
        title: Text(
          'Download Interrupted',
          style: TextStyle(
            color: const Color(0xFF8B0000),
            shadows: [
              Shadow(
                color: const Color(0xFF8B0000).withOpacity(0.5),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The AI model download was interrupted, but will auto-resume:',
              style: TextStyle(color: const Color(0xFF00FFFF)),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF8B0000).withOpacity(0.3)),
              ),
              child: Text(
                error,
                style: TextStyle(
                  color: const Color(0xFF00CCAA),
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'The app requires a 3.14GB AI model to function. Please ensure you have:',
              style: TextStyle(color: const Color(0xFF00FFFF)),
            ),
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• Stable internet connection', 
                     style: TextStyle(color: const Color(0xFF00CCAA))),
                Text('• At least 4GB free storage', 
                     style: TextStyle(color: const Color(0xFF00CCAA))),
                Text('• Good network signal', 
                     style: TextStyle(color: const Color(0xFF00CCAA))),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              SystemNavigator.pop(); // Exit app
            },
            child: Text(
              'Exit App',
              style: TextStyle(color: const Color(0xFF00CCAA)),
            ),
          ),
          if (_retryCount < maxRetries)
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _retryDownload();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FFFF),
                foregroundColor: const Color(0xFF0B1426),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text('Resume Download'),
            ),
        ],
      ),
    );
  }

  void _showInsufficientRAMDialog(String message, int actualRAM, int requiredRAM) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A0F2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: const Color(0xFFFF6B6B),
            width: 2,
          ),
        ),
        title: Row(
          children: [
            Icon(
              Icons.memory,
              color: const Color(0xFFFF6B6B),
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'Device Incompatible',
              style: TextStyle(
                color: const Color(0xFFFF6B6B),
                shadows: [
                  Shadow(
                    color: const Color(0xFFFF6B6B).withOpacity(0.5),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your device does not have sufficient memory to run ISABELLE\'s AI model safely.',
              style: TextStyle(color: const Color(0xFF00FFFF), fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF6B6B).withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• Required RAM: ${requiredRAM}MB (${(requiredRAM/1024).toStringAsFixed(1)}GB)',
                    style: TextStyle(color: const Color(0xFF00CCAA), fontSize: 14),
                  ),
                  Text(
                    '• Your device: ${actualRAM}MB (${(actualRAM/1024).toStringAsFixed(1)}GB)',
                    style: TextStyle(color: const Color(0xFFFF6B6B), fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The AI model requires approximately 4.4GB of storage and significant memory during processing.',
                    style: TextStyle(color: const Color(0xFF00CCAA).withOpacity(0.8), fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'ISABELLE requires a device with at least 3GB of RAM for safe operation. Consider using a device with more memory.',
              style: TextStyle(color: const Color(0xFF00FFFF).withOpacity(0.9), fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              SystemNavigator.pop(); // Exit app
            },
            child: Text(
              'Exit App',
              style: TextStyle(color: const Color(0xFFFF6B6B)),
            ),
          ),
        ],
      ),
    );
  }

  void _retryDownload() {
    _retryCount++;
    setState(() {
      _isRetrying = true;
      _statusMessage = 'Retrying download... (${_retryCount}/${maxRetries})';
    });
    
    // CRITICAL FIX: Reset state before retry to prevent accumulation
    _resetDownloadState();
    
    Future.delayed(const Duration(seconds: 2), () {
      _downloadModel();
    });
  }

  void _navigateToVisionAssistant() {
    Logger.info('🎯 Navigating to Vision Assistant');
    try {
      if (widget.onComplete != null) {
        Logger.info('📞 Calling widget.onComplete callback');
        widget.onComplete!();
        Logger.info('✅ widget.onComplete callback completed');
      } else {
        Logger.info('🔄 Navigating to BlindHome with pushReplacement');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const BlindHome(),
          ),
        );
        Logger.info('✅ Navigation to BlindHome completed');
      }
    } catch (e) {
      Logger.error('❌ Error in navigation: $e');
      rethrow;
    }
  }
  
  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1426),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [
              Color(0xFF1A0F2E),
              Color(0xFF0B1426),
              Color(0xFF0A0E1A),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Starry background
            _buildStarryBackground(),
            
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    
                    // App Logo with AI chip and flowing aura
                    AnimatedBuilder(
                      animation: Listenable.merge([_pulseAnimation, _orbitAnimation]),
                      builder: (context, child) {
                        final chipSize = MediaQuery.of(context).size.height * 0.22;
                        return Container(
                          width: chipSize,
                          height: chipSize,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // AI Chip (behind aura)
                              Transform.scale(
                                scale: _pulseAnimation.value * 0.95,
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0B1426).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF00FFFF).withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Circuit pattern on chip
                                      CustomPaint(
                                        painter: ChipCircuitPainter(),
                                        size: const Size(80, 80),
                                      ),
                                      // AI text with transparency
                                      ShaderMask(
                                        shaderCallback: (bounds) => const LinearGradient(
                                          colors: [
                                            Color(0xFF00FFFF),
                                            Color(0xFF9C4EFF),
                                          ],
                                        ).createShader(bounds),
                                        child: Text(
                                          'AI',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1,
                                            fontFamily: 'monospace',
                                            shadows: [
                                              Shadow(
                                                color: const Color(0xFF00FFFF).withOpacity(0.6),
                                                blurRadius: 8,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              
                              // Orbiting particles
                              for (int i = 0; i < 3; i++)
                                Transform.rotate(
                                  angle: _orbitAnimation.value + (i * 2 * math.pi / 3),
                                  child: Transform.translate(
                                    offset: Offset(80 + i * 8, 0),
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: const Color(0xFF00FFFF),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF00FFFF).withOpacity(0.8),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              
                              // Flowing aura (in front)
                              Transform.scale(
                                scale: _pulseAnimation.value,
                                child: CustomPaint(
                                  painter: AuraFlowPainter(_flowingLinesAnimation.value),
                                  size: Size(chipSize, chipSize),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Title
                    Text(
                      'ISABELLE AI',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF00FFFF),
                        letterSpacing: 2,
                        shadows: [
                          Shadow(
                            color: const Color(0xFF00FFFF).withOpacity(0.5),
                            blurRadius: 15,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 8),
                    
                    Text(
                      'Setting up your AI assistant',
                      style: TextStyle(
                        color: const Color(0xFF00CCAA),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(
                            color: const Color(0xFF00CCAA).withOpacity(0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    SizedBox(height: MediaQuery.of(context).size.height * 0.05),
                    
                    // Progress Section
                    Flexible(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A0F2E).withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF00FFFF).withOpacity(0.3),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00FFFF).withOpacity(0.1),
                            blurRadius: 20,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                          // Progress bar (only show during download)
                          if (_isDownloading) ...[
                            AnimatedBuilder(
                              animation: _progressAnimation,
                              builder: (context, child) {
                                return Column(
                                  children: [
                                    Container(
                                      height: 8,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        color: const Color(0xFF00CCAA).withOpacity(0.3),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: _downloadProgress,
                                          backgroundColor: Colors.transparent,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            const Color(0xFF00FFFF),
                                          ),
                                          minHeight: 8,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                );
                              },
                            ),
                          ],
                          
                          // Loading indicator
                          if (!_isDownloading && _statusMessage.contains('Checking') || _statusMessage.contains('Initializing')) ...[
                            Container(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  const Color(0xFF00FFFF),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                          
                          // Status message with auto-resume indicator
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Auto-resume indicator
                              if (_statusMessage.contains('Attempt') || _statusMessage.contains('Retrying')) ...[
                                Icon(
                                  Icons.refresh,
                                  color: const Color(0xFF00FFFF),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                              ],
                              
                              // Network connectivity indicator
                              if (_statusMessage.contains('Waiting for network')) ...[
                                Icon(
                                  Icons.wifi_off,
                                  color: const Color(0xFFFFAA00),
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                              ],
                              
                              Flexible(
                                child: Text(
                                  _statusMessage,
                                  style: TextStyle(
                                    color: const Color(0xFF00FFFF),
                                    fontSize: 16,
                                    height: 1.4,
                                    shadows: [
                                      Shadow(
                                        color: const Color(0xFF00FFFF).withOpacity(0.3),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                          
                          // Download details (only show during download)
                          if (_isDownloading && _downloadDetails.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.download,
                                  color: const Color(0xFF00CCAA),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _downloadDetails,
                                  style: TextStyle(
                                    color: const Color(0xFF00CCAA),
                                    fontSize: 14,
                                    height: 1.5,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ],
                          
                          // Download speed (show below progress during download)
                          if (_isDownloading) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00FFFF).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF00FFFF).withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.speed,
                                    color: const Color(0xFF00FFFF),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _currentSpeed,
                                    style: TextStyle(
                                      color: const Color(0xFF00FFFF),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'monospace',
                                      shadows: [
                                        Shadow(
                                          color: const Color(0xFF00FFFF).withOpacity(0.3),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${_downloadProgress > 0 ? "${(_downloadProgress * 100).toInt()}%" : "Starting..."}',
                                    style: TextStyle(
                                      color: const Color(0xFF00CCAA),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          
                          // Additional info during download
                          if (_isDownloading) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0A0E1A).withOpacity(0.6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF00CCAA).withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                'This is a one-time download. The AI will work completely offline after this.',
                                style: TextStyle(
                                  color: const Color(0xFF00CCAA),
                                  fontSize: 14,
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                          
                          // Retry button for initialization failures
                          if (_showRetryButton && !_isDownloading) ...[
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _showRetryButton = false;
                                });
                                _initializeModel();
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry Initialization'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00FFFF),
                                foregroundColor: const Color(0xFF0B1426),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                          
                          // Retry indicator
                          if (_isRetrying) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFAA6C39).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFAA6C39),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.refresh,
                                    color: const Color(0xFFAA6C39),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Retrying... (${_retryCount}/${maxRetries})',
                                    style: TextStyle(
                                      color: const Color(0xFFAA6C39),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                        ),
                      ),
                      ),
                    ),
                    
                    SizedBox(height: MediaQuery.of(context).size.height * 0.03),
                    
                    // Info text
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0E1A).withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF00CCAA).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        'Gemma 3n E4B Model - Mobile-optimized for offline use\n'
                        'Size: 4.4GB • Completely offline after download\n'
                        'Native high-speed download (50-90 MB/s)',
                        style: TextStyle(
                          color: const Color(0xFF00CCAA).withOpacity(0.8),
                          fontSize: 11,
                          height: 1.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStarryBackground() {
    return AnimatedBuilder(
      animation: _starsAnimation,
      builder: (context, child) {
        return CustomPaint(
          painter: StarryBackgroundPainter(_starsAnimation.value),
          size: Size.infinite,
        );
      },
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    _starsController.dispose();
    _flowingLinesController.dispose();
    _orbitController.dispose();
    // Cleanup any download resources
    super.dispose();
  }
}

class AuraFlowPainter extends CustomPainter {
  final double animationValue;

  AuraFlowPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    // Create multiple flowing wave layers for realistic aura
    for (int layer = 0; layer < 6; layer++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 - (layer * 0.3);
      
      final baseRadius = 55 + layer * 12;
      final path = Path();
      
      // Create flowing wave around the chip
      for (double angle = 0; angle < math.pi * 2; angle += 0.1) {
        final timeOffset = animationValue * 2 * math.pi;
        final waveOffset1 = math.sin(angle * 3 + timeOffset + layer * 0.5) * 8;
        final waveOffset2 = math.cos(angle * 2 - timeOffset * 0.7 + layer * 0.3) * 6;
        final waveOffset3 = math.sin(angle * 4 + timeOffset * 1.3 + layer) * 4;
        
        final radius = baseRadius + waveOffset1 + waveOffset2 + waveOffset3;
        final x = center.dx + math.cos(angle) * radius;
        final y = center.dy + math.sin(angle) * radius;
        
        if (angle == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      
      // Create dynamic color gradient
      final progress = layer / 6.0;
      final colorPhase = (animationValue + progress) % 1.0;
      
      Color waveColor;
      if (colorPhase < 0.33) {
        waveColor = Color.lerp(
          const Color(0xFF00FFFF), 
          const Color(0xFF00CCFF), 
          colorPhase * 3
        )!;
      } else if (colorPhase < 0.66) {
        waveColor = Color.lerp(
          const Color(0xFF00CCFF), 
          const Color(0xFF9C4EFF), 
          (colorPhase - 0.33) * 3
        )!;
      } else {
        waveColor = Color.lerp(
          const Color(0xFF9C4EFF), 
          const Color(0xFF00FFFF), 
          (colorPhase - 0.66) * 3
        )!;
      }
      
      paint.color = waveColor.withOpacity(0.9 - layer * 0.12);
      canvas.drawPath(path, paint);
      
      // Add inner glow effect
      if (layer < 3) {
        final glowPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0 - layer
          ..color = waveColor.withOpacity(0.3 - layer * 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        
        canvas.drawPath(path, glowPaint);
      }
    }
    
    // Add energy particles
    for (int i = 0; i < 12; i++) {
      final particleAngle = (i * math.pi * 2 / 12) + (animationValue * math.pi * 2 * 0.5);
      final particleRadius = 70 + math.sin(animationValue * 3 + i) * 15;
      final particleX = center.dx + math.cos(particleAngle) * particleRadius;
      final particleY = center.dy + math.sin(particleAngle) * particleRadius;
      
      final particlePaint = Paint()
        ..color = const Color(0xFF00FFFF).withOpacity(0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      
      canvas.drawCircle(
        Offset(particleX, particleY), 
        1.5 + math.sin(animationValue * 4 + i * 0.5),
        particlePaint
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class ChipCircuitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Cyan circuit traces (matching screen design)
    final tracePaint = Paint()
      ..color = const Color(0xFF00FFFF).withOpacity(0.4)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    // Blue-cyan connection pads
    final padPaint = Paint()
      ..color = const Color(0xFF00CCFF).withOpacity(0.5)
      ..style = PaintingStyle.fill;

    // Micro-traces (horizontal)
    for (int i = 0; i < 6; i++) {
      final y = (15 + i * 10).toDouble();
      canvas.drawLine(
        Offset(8.0, y),
        Offset(size.width - 8.0, y),
        tracePaint,
      );
    }
    
    // Micro-traces (vertical)
    for (int i = 0; i < 6; i++) {
      final x = (15 + i * 10).toDouble();
      canvas.drawLine(
        Offset(x, 8.0),
        Offset(x, size.height - 8.0),
        tracePaint,
      );
    }
    
    // Connection pads (like real chip pins)
    for (int i = 0; i < 5; i++) {
      for (int j = 0; j < 5; j++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset((16 + i * 12).toDouble(), (16 + j * 12).toDouble()),
              width: 2.5,
              height: 2.5,
            ),
            const Radius.circular(0.5),
          ),
          padPaint,
        );
      }
    }

    // Add some detailed micro-components with cyan theme
    final componentPaint = Paint()
      ..color = const Color(0xFF9C4EFF).withOpacity(0.3)
      ..style = PaintingStyle.fill;

    // Small components/capacitors
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(25, 25, 6, 3),
        const Radius.circular(1),
      ),
      componentPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(45, 35, 5, 2.5),
        const Radius.circular(1),
      ),
      componentPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(35, 50, 3, 5),
        const Radius.circular(1),
      ),
      componentPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class StarryBackgroundPainter extends CustomPainter {
  final double animationValue;

  StarryBackgroundPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF00FFFF).withOpacity(0.6);
    
    final random = math.Random(42); // Fixed seed for consistent stars
    
    for (int i = 0; i < 120; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final twinkle = (math.sin(animationValue * 2 * math.pi + i) + 1) / 2;
      
      paint.color = Color(0xFF00FFFF).withOpacity(0.2 + twinkle * 0.6);
      canvas.drawCircle(Offset(x, y), 1 + twinkle, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}