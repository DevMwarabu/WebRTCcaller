import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/call_service.dart';
import 'package:firebase_database/firebase_database.dart';

class CallScreen extends StatefulWidget {
  final String callId;
  final bool isCaller;
  final String localUserId;
  final String remoteUserId;

  const CallScreen({
    required this.callId,
    required this.isCaller,
    required this.localUserId,
    required this.remoteUserId,
    super.key,
  });

  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  final CallService _callService = CallService();
  
  bool _isMuted = false;
  bool _isVideoOn = true;
  bool _isFrontCamera = true;
  bool _isCallActive = false;
  String _callStatus = 'Connecting...';
  DatabaseReference? _callRef;

  @override
  void initState() {
    super.initState();
    _initializeCall();
  }

  Future<void> _initializeCall() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      if (widget.isCaller) {
        // Start a new call
        final result = await _callService.startCall(
          localUserId: widget.localUserId,
          localRenderer: _localRenderer,
          remoteRenderer: _remoteRenderer,
        );

        if (result != null) {
          _callRef = FirebaseDatabase.instance.ref('calls/${widget.callId}');
          _setupCallStateListener();
          setState(() {
            _isCallActive = true;
            _callStatus = 'Calling...';
          });
        }
      } else {
        // Join an existing call
        final result = await _callService.joinCall(
          callId: widget.callId,
          localUserId: widget.localUserId,
          localRenderer: _localRenderer,
          remoteRenderer: _remoteRenderer,
        );

        if (result != null) {
          _callRef = FirebaseDatabase.instance.ref('calls/${widget.callId}');
          _setupCallStateListener();
          setState(() {
            _isCallActive = true;
            _callStatus = 'In Call';
          });
        }
      }
    } catch (e) {
      setState(() => _callStatus = 'Error: ${e.toString()}');
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  void _setupCallStateListener() {
    _callRef?.onValue.listen((event) {
      if (event.snapshot.value == null) {
        // Call was ended
        if (mounted) {
          Navigator.pop(context);
        }
      }
    });
  }

  Future<void> _endCall() async {
    try {
      await _callService.endCall(widget.callId);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error ending call: $e')),
        );
      }
    }
  }

  Future<void> _toggleMute() async {
    setState(() => _isMuted = !_isMuted);
    await _callService.toggleMute(_isMuted);
  }

  Future<void> _toggleVideo() async {
    setState(() => _isVideoOn = !_isVideoOn);
    await _callService.toggleVideo(_isVideoOn);
  }

  Future<void> _switchCamera() async {
    setState(() => _isFrontCamera = !_isFrontCamera);
    await _callService.switchCamera(_isFrontCamera);
  }

  @override
  void dispose() {
    _callRef?.onValue.drain();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_callStatus),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: _endCall,
        ),
      ),
      body: Stack(
        children: [
          // Remote video
          Positioned.fill(
            child: _isCallActive
                ? RTCVideoView(_remoteRenderer)
                : Center(child: CircularProgressIndicator()),
          ),
          
          // Local video preview
          Positioned(
            right: 20,
            top: 40,
            width: 120,
            height: 200,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: _isVideoOn
                  ? RTCVideoView(_localRenderer, mirror: _isFrontCamera)
                  : Center(child: Icon(Icons.videocam_off, color: Colors.white)),
            ),
          ),
          
          // Call controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Mute button
                _buildCallControl(
                  icon: _isMuted ? Icons.mic_off : Icons.mic,
                  onPressed: _toggleMute,
                  backgroundColor: _isMuted ? Colors.red : Colors.white24,
                ),
                
                // End call button
                _buildCallControl(
                  icon: Icons.call_end,
                  onPressed: _endCall,
                  backgroundColor: Colors.red,
                  iconColor: Colors.white,
                ),
                
                // Toggle video button
                _buildCallControl(
                  icon: _isVideoOn ? Icons.videocam : Icons.videocam_off,
                  onPressed: _toggleVideo,
                  backgroundColor: _isVideoOn ? Colors.white24 : Colors.red,
                ),
                
                // Switch camera button
                _buildCallControl(
                  icon: Icons.switch_video,
                  onPressed: _switchCamera,
                  backgroundColor: Colors.white24,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCallControl({
    required IconData icon,
    required VoidCallback onPressed,
    required Color backgroundColor,
    Color iconColor = Colors.white,
  }) {
    return CircleAvatar(
      radius: 28,
      backgroundColor: backgroundColor,
      child: IconButton(
        icon: Icon(icon, color: iconColor, size: 28),
        onPressed: onPressed,
      ),
    );
  }
}
