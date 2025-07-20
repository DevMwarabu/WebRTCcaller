import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'services/call_service.dart';
import 'config/config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // Initialize services
    final callService = CallService();
    
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => callService),
        ],
        child: const MyApp(),
      ),
    );
  } catch (e) {
    print('Error initializing Firebase: $e');
    // Run the app in offline mode or show error UI
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Error initializing app: $e'),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebRTC Caller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
        ),
      ),
      // Wrap HomeScreen with a FutureBuilder to ensure proper initialization
      home: FutureBuilder(
        future: _initializeApp(context),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasError) {
            final error = snapshot.error.toString();
            final isPermissionError = error.contains('permission', 1) || 
                                   error.contains('Permission', 1);
            
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isPermissionError ? Icons.videocam_off : Icons.error_outline,
                        size: 64,
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        isPermissionError 
                            ? 'Permissions Required'
                            : 'Initialization Error',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isPermissionError
                            ? 'Camera and microphone permissions are required to make video calls.'
                            : 'Error: ${snapshot.error}',
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (isPermissionError) ...[
                        ElevatedButton.icon(
                          icon: const Icon(Icons.settings),
                          label: const Text('Open Settings'),
                          onPressed: () async {
                            await openAppSettings();
                            // After returning from settings, try initializing again
                            if (context.mounted) {
                              await _initializeApp(context);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () async {
                            // Try initializing again
                            await _initializeApp(context);
                          },
                          child: const Text('Retry'),
                        ),
                      ] else ...[
                        ElevatedButton(
                          onPressed: () async {
                            // Try initializing again
                            await _initializeApp(context);
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }
            return const HomeScreen();
          }
          // Show a loading indicator while initializing
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        },
      ),
    );
  }
  
  // Initialize app services
  static Future<void> _initializeApp(BuildContext context) async {
    try {
      print('Initializing app...');
      final callService = context.read<CallService>();
      
      // Generate a user ID for this session
      final userId = 'user_${DateTime.now().millisecondsSinceEpoch % 10000}';
      print('Initializing CallService with user ID: $userId');
      
      // Initialize the call service with the signaling server URL
      if (AppConfig.signalingServerUrl.isEmpty) {
        throw Exception('Signaling server URL is not configured');
      }
      
      print('Initializing CallService for user: $userId');
      await callService.initialize(userId);
      
      // Set the context for showing dialogs
      callService.setContext(context);
      
      print('App initialization complete');
    } on PlatformException catch (e) {
      print('Platform error initializing app: ${e.message}');
      rethrow;
    } catch (e, stackTrace) {
      print('Error initializing app: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
}
