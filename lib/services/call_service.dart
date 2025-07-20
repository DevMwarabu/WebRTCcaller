import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';

import 'firebase_signaling_service.dart';
import '../utils/app_permissions.dart';

// Call state enum
enum CallState {
  idle,
  calling,
  receivingCall,
  inCall,
  callEnded,
}

typedef OnLocalStream = void Function(MediaStream? stream);
typedef OnRemoteStream = void Function(MediaStream? stream);
typedef OnCallStateChanged = void Function(bool isInCall);

class CallService extends ChangeNotifier {
  // WebRTC components
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  // Context for showing dialogs
  BuildContext? _context;
  
  // Set the context when initializing the service
  void setContext(BuildContext context) {
    _context = context;
  }
  
  // Show a snackbar message
  void _showSnackBar(String message) {
    if (_context != null) {
      ScaffoldMessenger.of(_context!).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
  
  // Call state
  bool _isCalling = false;
  bool _isReceivingCall = false;
  String? _callerId;
  String? _calleeId;
  String? _localId;
  String? _remoteUserId;
  
  CallState _currentCallState = CallState.idle;
  
  // Firebase signaling service
  late final FirebaseSignalingService _signalingService;
  StreamSubscription? _offerSubscription;
  StreamSubscription? _answerSubscription;
  StreamSubscription? _candidateSubscription;
  // ignore: unused_field - Used in _setupSignalingHandlers
  StreamSubscription? _callSubscription;  // For call state changes
  Timer? _callTimeout;  // For call timeout handling
  
  // Getters
  String? get localId => _localId;
  String? get remoteUserId => _remoteUserId;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get isCalling => _isCalling;
  bool get isReceivingCall => _isReceivingCall;
  String? get callerId => _callerId;
  String? get calleeId => _calleeId;

  // Callbacks
  OnLocalStream? onLocalStream;
  OnRemoteStream? onRemoteStream;
  OnCallStateChanged? onCallStateChanged;

  CallService() {
    _signalingService = FirebaseSignalingService();
  }

  // Initialize the call service
  Future<void> initialize(String userId, {BuildContext? context}) async {
    _localId = userId;
    if (context != null) {
      _context = context;
    }
    
    // Initialize the Firebase signaling service
    await _signalingService.initialize(userId);
    
    // Set up signaling message handlers
    _setupSignalingHandlers();
  }

  // Set up signaling message handlers
  void _setupSignalingHandlers() {
    // Handle incoming offers
    _offerSubscription = _signalingService.onOffer.listen((description) async {
      if (_currentCallState != CallState.idle) {
        // If we're already in a call, reject the incoming call
        _signalingService.sendRejection(_remoteUserId ?? '', 'User is busy');
        return;
      }
      
      // The description is already an RTCSessionDescription from FirebaseSignalingService
      await _handleIncomingCall(_remoteUserId ?? 'unknown', description);
    });
    
    // Handle incoming answers
    _answerSubscription = _signalingService.onAnswer.listen((description) async {
      // The description is already an RTCSessionDescription from FirebaseSignalingService
      await _handleAnswer(description);
    });
    
    // Handle incoming ICE candidates
    _candidateSubscription = _signalingService.onCandidate.listen((candidate) async {
      // The candidate is already an RTCIceCandidate from FirebaseSignalingService
      await _addCandidate(candidate);
    });
    
    // Handle call state changes
    _callSubscription = _signalingService.onCall.listen((data) async {
      final type = data['type'] as String;
      final from = data['from'] as String?;
      
      if (type == 'rejected' && from == _remoteUserId) {
        _currentCallState = CallState.idle;
        _notifyStateChange();
        _showSnackBar('Call was rejected');
      } else if (type == 'ended' && from == _remoteUserId) {
        await endCall();
      }
    });
  }

  // Start a call to a remote peer
  Future<void> call(String calleeId, {BuildContext? context}) async {
    if (_isCalling || _isReceivingCall) {
      developer.log('Already in a call');
      return;
    }

    // Request permissions if not already granted
    final hasPermissions = await _requestPermissions(context);
    if (!hasPermissions) {
      developer.log('Camera/microphone permissions not granted');
      return;
    }

    _calleeId = calleeId;
    _isCalling = true;
    _notifyStateChange();

    try {
      // Get user media
      _localStream = await _getUserMedia();
      onLocalStream?.call(_localStream);

      // Create peer connection
      _peerConnection = await _createPeerConnection();

      // Add local stream to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Create offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Send offer through signaling
      await _signalingService.sendOffer(calleeId, offer);

      // Start call timeout
      _startCallTimeout();
    } catch (e) {
      developer.log('Error starting call: $e');
      _cleanUpCall();
      rethrow;
    }
  }

  // Handle incoming call
  Future<void> _handleIncomingCall(String from, RTCSessionDescription description) async {
    if (_isCalling || _isReceivingCall) {
      // Already in a call, reject
      await _signalingService.sendRejection(from, 'User is busy in another call');
      return;
    }

    _callerId = from;
    _isReceivingCall = true;
    _notifyStateChange();

    try {
      // Request permissions if not already granted
      final hasPermissions = await _requestPermissions(_context);
      if (!hasPermissions) {
        developer.log('Camera/microphone permissions not granted');
        await _signalingService.sendRejection(from, 'Required permissions not granted');
        _cleanUpCall();
        return;
      }

      // Create peer connection if not exists
      if (_peerConnection == null) {
        await _createPeerConnection();
      }

      // Set remote description
      await _peerConnection!.setRemoteDescription(description);

      // Create and set local description
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // Send answer back to caller
      await _signalingService.sendAnswer(from, answer);

      _isReceivingCall = false;
      _notifyStateChange();
    } catch (e) {
      developer.log('Error handling incoming call: $e');
      await _signalingService.sendRejection(from, 'Error handling call');
      _cleanUpCall();
      rethrow;
    }
  }

  // End the current call
  Future<void> endCall() async {
    if (!_isCalling && !_isReceivingCall) return;
    
    // Notify the other peer if we're the caller
    if (_isCalling && _calleeId != null) {
      // For Firebase, we don't need a separate end call message
      // The peer will detect the call ended when the peer connection is closed
    }
    
    _cleanUpCall();
  }

  // Clean up call resources
  Future<void> _cleanUpCall() async {
    _stopCallTimeout();
    
    // Close peer connection
    _peerConnection?.close();
    _peerConnection = null;
    
    // Stop all tracks in local stream
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      _localStream = null;
    }
    
    // Stop all tracks in remote stream
    if (_remoteStream != null) {
      for (final track in _remoteStream!.getTracks()) {
        await track.stop();
      }
      _remoteStream = null;
    }
    
    // Reset call state
    _isCalling = false;
    _isReceivingCall = false;
    _callerId = null;
    _calleeId = null;
    
    _notifyStateChange();
    
    // Notify listeners
    onCallStateChanged?.call(false);
  }
  
  // Notify listeners of state changes
  void _notifyStateChange() {
    notifyListeners();
  }

  // Handle answer from callee
  Future<void> _handleAnswer(RTCSessionDescription answer) async {
    if (!_isCalling) return;
    
    _stopCallTimeout();
    await _peerConnection!.setRemoteDescription(answer);
  }

  // Add ICE candidate
  Future<void> _addCandidate(RTCIceCandidate candidate) async {
    if (_peerConnection == null) return;
    await _peerConnection!.addCandidate(candidate);
  }

  // Create a peer connection
  Future<RTCPeerConnection> _createPeerConnection() async {
    final configuration = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        // Add TURN servers here if needed
      ],
    };

    final peerConnection = await createPeerConnection(configuration);
    
    // Set up ICE candidate handler
    peerConnection.onIceCandidate = (RTCIceCandidate candidate) {
      _handleIceCandidate(candidate);
    };

    // Set up track handler for remote stream
    peerConnection.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        onRemoteStream?.call(_remoteStream);
      }
    };
    
    // Set up ICE connection state handler
    peerConnection.onIceConnectionState = (RTCIceConnectionState state) {
      developer.log('ICE connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _cleanUpCall();
      }
    };

    // Set up track handler
    peerConnection.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream);
        notifyListeners();
      }
    };

    // Get local media stream
    _localStream = await _getUserMedia();
    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });
    
    onLocalStream?.call(_localStream);
    
    return peerConnection;
  }

  void _handleIceCandidate(RTCIceCandidate candidate) {
    if (_callerId != null) {
      _signalingService.sendIceCandidate(_callerId!, candidate);
    }
  }

  // Get user media (camera and microphone)
  Future<MediaStream> _getUserMedia() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': {
        'facingMode': 'user', // Use front camera by default
        'width': {'ideal': 640},
        'height': {'ideal': 480},
        'frameRate': {'ideal': 30},
      },
    };

    try {
      final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      return stream;
    } catch (e) {
      developer.log('Error getting user media: $e');
      rethrow;
    }
  }

  // Request permissions for camera and microphone
  Future<bool> _requestPermissions([BuildContext? buildContext]) async {
    // Use the provided buildContext or fall back to the stored _context
    final context = buildContext ?? _context;
    try {
      // First check if we already have permissions
      final hasPermissions = await AppPermissions.hasCameraAndMicPermissions;
      if (hasPermissions) {
        return true;
      }
      
      // Request permissions
      final status = await AppPermissions.requestCameraAndMicPermissions();
      
      if (!status) {
        // Check if permissions are permanently denied
        final cameraStatus = await Permission.camera.status;
        final micStatus = await Permission.microphone.status;
        final isPermanentlyDenied = 
            cameraStatus.isPermanentlyDenied || micStatus.isPermanentlyDenied;
        
        // Check if we have a valid context
        if (context == null || !context.mounted) {
          developer.log('No valid context available to show permission dialog');
          return false;
        }
        
        // Show dialog to explain why permissions are needed
        bool openSettings = false;
        try {
          final result = await showDialog<bool>(
            context: context,
            builder: (BuildContext dialogContext) => AlertDialog(
              title: const Text('Permissions Required'),
              content: Text(
                isPermanentlyDenied
                    ? 'Camera and microphone permissions are required to make and receive calls. '
                        'Please enable them in the app settings.'
                    : 'Camera and microphone permissions are required to make and receive calls.',
              ),
              actions: [
                if (!isPermanentlyDenied)
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Not Now'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
          openSettings = result ?? false;
        } catch (e) {
          developer.log('Error showing permission dialog: $e');
        }
        
        if (openSettings) {
          await openAppSettings();
        } else if (!isPermanentlyDenied) {
          // If not permanently denied, try requesting again after user acknowledges
          return await _requestPermissions(buildContext);
        }
        
        return false;
      }
      
      return true;
    } catch (e) {
      developer.log('Error requesting permissions: $e');
      final errorContext = buildContext ?? _context;
      if (errorContext != null && errorContext.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (errorContext.mounted) {
            try {
              ScaffoldMessenger.of(errorContext).showSnackBar(
                const SnackBar(content: Text('Failed to request permissions. Please try again.')),
              );
            } catch (e) {
              developer.log('Failed to show error snackbar: $e');
            }
          }
        });
      }
      return false;
    }
  }

  // Start call timeout
  void _startCallTimeout() {
    _callTimeout = Timer(const Duration(seconds: 30), () {
      if (_isCalling) {
        endCall();
        // Show timeout message to user
        if (_context != null && _context!.mounted) {
          ScaffoldMessenger.of(_context!).showSnackBar(
            const SnackBar(content: Text('Call timed out')),
          );
        }
      }
    });
  }

  // Stop call timeout
  void _stopCallTimeout() {
    _callTimeout?.cancel();
    _callTimeout = null;
  }

  @override
  void dispose() {
    _offerSubscription?.cancel();
    _answerSubscription?.cancel();
    _candidateSubscription?.cancel();
    _cleanUpCall();
    _signalingService.dispose();
    super.dispose();
  }
}
