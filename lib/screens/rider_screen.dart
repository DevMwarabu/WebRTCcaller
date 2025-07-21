import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_service.dart';
import '../services/call_notifier.dart';
import 'call_screen.dart';

class RiderScreen extends StatefulWidget {
  const RiderScreen({super.key});

  @override
  _RiderScreenState createState() => _RiderScreenState();
}

class _RiderScreenState extends State<RiderScreen> {
  final CallService _callService = CallService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _initRenderers();
    
    // Listen for incoming calls
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final callNotifier = context.read<CallNotifier>();
      callNotifier.addListener(() {
        if (callNotifier.isRinging) {
          _showIncomingCallDialog(callNotifier);
        }
      });
    });
  }

  @override
  void dispose() {
    _callIdController.dispose();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _requestRide() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final database = FirebaseDatabase.instance;
    final newRef = database.ref('ride_requests').push();
    
    final request = <String, dynamic>{
      'id': newRef.key!,
      'userId': user.uid,
      'userName': user.displayName ?? 'User',
      'status': 'pending',
      'timestamp': ServerValue.timestamp,
    };
    
    await newRef.set(request);
  }

  Future<void> _initCall() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Initialize local renderers
      await _initRenderers();
      
      // Initialize local stream and get it ready for the call
      await _callService.initializeLocalStream(_localRenderer);
      
      // Generate a unique call ID
      final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';
      
      // Start ringing
      final callNotifier = context.read<CallNotifier>();
      
      // Start ringing for the caller
      await callNotifier.startRinging(
        callId: callId,
        callerId: user.uid,
      );
      
      if (!mounted) return;
      
      // Show calling screen
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            isCaller: true,
            callId: callId,
            localUserId: user.uid,
            remoteUserId: 'driver_${DateTime.now().millisecondsSinceEpoch}',
          ),
        ),
      );
      
      // Stop ringing when call screen is popped
      if (result == true) {
        callNotifier.stopRinging();
      }
    } catch (e) {
      print("Error starting call: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start call: ${e.toString()}')),
        );
      }
    }
  }
  
  void _showIncomingCallDialog(CallNotifier callNotifier) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Incoming Call'),
        content: Text('Call from: ${callNotifier.callerId}'),
        actions: [
          TextButton(
            onPressed: () {
              callNotifier.stopRinging();
              Navigator.pop(context);
              // Navigate to call screen with answer mode
              _answerCall(callNotifier);
            },
            child: const Text('Answer'),
          ),
          TextButton(
            onPressed: () {
              callNotifier.stopRinging();
              Navigator.pop(context);
              _declineCall(callNotifier);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _answerCall(CallNotifier callNotifier) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      await _initRenderers();
      await _callService.initializeLocalStream(_localRenderer);
      
      if (!mounted) return;
      
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            isCaller: false,
            callId: callNotifier.currentCallId!,
            localUserId: user.uid,
            remoteUserId: callNotifier.callerId ?? 'unknown',
          ),
        ),
      );
    } catch (e) {
      print('Error answering call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to answer call')),
        );
      }
    }
  }
  
  Future<void> _declineCall(CallNotifier callNotifier) async {
    // TODO: Implement call decline logic
    print('Call declined');
  }

  Future<void> _joinCall(BuildContext context, String callId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to join a call')),
      );
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Initialize local stream before joining the call
      await _callService.initializeLocalStream(_localRenderer);
      
      // Join the call
      final result = await _callService.joinCall(
        callId: callId.trim(),
        localUserId: user.uid,
        localRenderer: _localRenderer,
        remoteRenderer: _remoteRenderer,
      );

      // Dismiss loading indicator
      if (!mounted) return;
      Navigator.of(context).pop();

      // Navigate to call screen
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(
            isCaller: false,
            callId: callId,
            localUserId: user.uid,
            remoteUserId: result['remoteUserId'] ?? 'unknown',
          ),
        ),
      );
    } catch (e) {
      // Dismiss loading indicator
      if (mounted) {
        Navigator.of(context).pop();
        // Show error message to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join call: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print("Error joining call: $e");
    }
  }

  final TextEditingController _callIdController = TextEditingController();
  String? _currentCallId;

  Future<void> _promptForCallId(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Join Call'),
        content: TextField(
          controller: _callIdController,
          decoration: InputDecoration(hintText: 'Enter Call ID'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (_callIdController.text.isNotEmpty) {
                Navigator.pop(context);
                _joinCall(context, _callIdController.text);
              }
            },
            child: Text('Join'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: _requestRide,
            child: Text('Request Ride'),
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => _initCall(),
            child: Text('Start Call'),
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => _promptForCallId(context),
            child: Text('Join Call'),
          ),
          if (_currentCallId != null) ...[
            SizedBox(height: 20),
            Text('Current Call ID: $_currentCallId'),
          ],
        ],
      ),
    );
  }
}
