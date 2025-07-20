import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/call_service.dart';
import '../services/auth_service.dart';
import '../widgets/call_controls.dart';
import '../widgets/video_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _peerIdController = TextEditingController();
  bool _isInitialized = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCallService();
    });
  }

  Future<void> _initializeCallService() async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Request camera and microphone permissions
      final cameraStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();
      
      if (!cameraStatus.isGranted || !micStatus.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera and microphone permissions are required'),
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }
      
      // Initialize call service with a random user ID
      final callService = context.read<CallService>();
      final userId = 'user_${DateTime.now().millisecondsSinceEpoch % 10000}';
      await callService.initialize(userId);
      
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _startCall(CallService callService) async {
    final peerId = _peerIdController.text.trim();
    if (peerId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a peer ID')),
        );
      }
      return;
    }

    if (peerId == callService.localId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot call yourself')),
        );
      }
      return;
    }

    try {
      await callService.call(peerId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start call: ${e.toString()}')),
        );
      }
    }
  }
  
  Future<void> _acceptCall() async {
    // In our Firebase signaling flow, the call is automatically accepted
    // when the offer is processed in the CallService
  }
  
  Future<void> _rejectCall() async {
    final callService = context.read<CallService>();
    try {
      await callService.endCall();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to reject call')),
        );
      }
    }
  }

  @override
  void dispose() {
    _peerIdController.dispose();
    super.dispose();
  }

  Widget _buildVideoViews(CallService callService) {
    return Stack(
      children: [
        // Remote video (full screen)
        if (callService.remoteStream != null)
          VideoView(stream: callService.remoteStream!, isLocal: false),

        // Local video (picture-in-picture)
        if (callService.localStream != null)
          Positioned(
            right: 20,
            top: 20,
            width: 120,
            height: 200,
            child: VideoView(
              stream: callService.localStream!,
              isLocal: true,
            ),
          ),

        // Call controls overlay
        if (callService.isCalling || callService.isReceivingCall)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CallControls(
              isCalling: callService.isCalling,
              isReceivingCall: callService.isReceivingCall,
              onEndCall: callService.endCall,
              onAcceptCall: _acceptCall,
              onRejectCall: _rejectCall,
            ),
          ),
      ],
    );
  }

  Widget _buildCallControls(CallService callService) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: _peerIdController,
            decoration: const InputDecoration(
              labelText: 'Peer ID',
              border: OutlineInputBorder(),
              hintText: 'Enter peer ID to call',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : () => _startCall(callService),
              child: const Text('Start Call'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your ID: ${callService.localId ?? '...'}',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final callService = context.watch<CallService>();
    final authService = context.read<AuthService>();
    final currentUser = authService.currentUser;

    // Show loading indicator if not initialized
    if (_isLoading || !_isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('WebRTC Caller'),
        centerTitle: true,
        actions: [
          if (currentUser != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        currentUser.email ?? 'User',
                        style: const TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                      if (callService.localId != null && callService.localId!.isNotEmpty)
                        Text(
                          'ID: ${callService.localId}',
                          style: const TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white70),
                    tooltip: 'Logout',
                    onPressed: () async {
                      try {
                        await authService.signOut();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error signing out: $e')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Video views
          Expanded(child: _buildVideoViews(callService)),
          
          // Call input and controls
          if (!callService.isCalling && !callService.isReceivingCall)
            _buildCallControls(callService),
        ],
      ),
    );
  }
}
