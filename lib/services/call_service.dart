import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';

import 'realtime_db_signaling_service.dart';
import '../utils/app_permissions.dart';

// Call state enum
enum CallState { idle, calling, receivingCall, inCall, callEnded }

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
      ScaffoldMessenger.of(
        _context!,
      ).showSnackBar(SnackBar(content: Text(message)));
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

  // Firebase Realtime Database signaling service
  late final RealtimeDbSignalingService _signalingService;
  StreamSubscription? _offerSubscription;
  StreamSubscription? _answerSubscription;
  StreamSubscription? _candidateSubscription;
  // ignore: unused_field - Used in _setupSignalingHandlers
  StreamSubscription? _callSubscription; // For call state changes
  Timer? _callTimeout; // For call timeout handling

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
    _signalingService = RealtimeDbSignalingService(
      userId: 'temporary_id', // This will be updated in initialize()
    );
  }

  // Initialize the call service
  Future<void> initialize(String userId, {BuildContext? context}) async {
    _localId = userId;
    if (context != null) {
      _context = context;
    }

    // Reinitialize the signaling service with the correct user ID
    _signalingService = RealtimeDbSignalingService(
      userId: userId,
    );

    // Initialize the Firebase Realtime Database signaling service
    await _signalingService.initialize(userId);

    // Set up signaling message handlers
    _setupSignalingHandlers();
  }

  // Set up signaling message handlers
  void _setupSignalingHandlers() {
    // Handle incoming offers
    _offerSubscription = _signalingService.onOffer.listen((message) {
      Future(() async {
        if (_currentCallState != CallState.idle) {
          // If we're already in a call, reject the incoming call
          try {
            await _signalingService.sendCallRejected(message.from!);
          } catch (error) {
            developer.log('Error rejecting call: $error');
          }
          return;
        }

        try {
          final description = RTCSessionDescription(
            message.data['sdp'],
            message.data['type'],
          );

          _remoteUserId = message.from;
          await _handleIncomingCall(message.from!, description);
        } catch (error) {
          developer.log('Error handling incoming call: $error');
        }
      }).catchError((error) {
        developer.log('Error in offer handler: $error');
      });
    });

    // Handle incoming answers
    _answerSubscription = _signalingService.onAnswer.listen((message) {
      Future(() async {
        try {
          final description = RTCSessionDescription(
            message.data['sdp'],
            message.data['type'],
          );
          await _handleAnswer(description);
        } catch (error) {
          developer.log('Error handling answer: $error');
        }
      }).catchError((error) {
        developer.log('Error in answer handler: $error');
      });
    });

    // Handle incoming ICE candidates
    _candidateSubscription = _signalingService.onCandidate.listen((message) {
      Future(() async {
        try {
          final candidate = RTCIceCandidate(
            message.data['candidate'],
            message.data['sdpMid'],
            message.data['sdpMLineIndex'],
          );
          await _addCandidate(candidate);
        } catch (e) {
          developer.log('Error handling ICE candidate: $e');
        }
      }).catchError((error) {
        developer.log('Error in candidate handler: $error');
      });
    });

    // Handle call state changes
    _callSubscription = _signalingService.onCall.listen((message) {
      final type = message.type;
      final from = message.from;

      if (type == 'call-rejected' && from == _remoteUserId) {
        _currentCallState = CallState.idle;
        _notifyStateChange();
        _showSnackBar('Call was rejected');
      } else if (type == 'end-call' && from == _remoteUserId) {
        endCall().catchError((error) {
          developer.log('Error ending call: $error');
        });
      } else if (type == 'call-request' && from != null) {
        // Handle incoming call request
        _remoteUserId = from;
        _callerId = from;
        _isReceivingCall = true;
        _notifyStateChange();
      } else if (type == 'call-accepted' && from == _remoteUserId) {
        // Handle call accepted
        _isCalling = false;
        _currentCallState = CallState.inCall;
        _notifyStateChange();
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
      for (final track in _localStream!.getTracks()) {
        _peerConnection!.addTrack(track, _localStream!);
      }

      // Create offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Send offer through signaling
      await _signalingService.sendOffer(offer, calleeId);

      // Start call timeout
      _startCallTimeout();
    } catch (e) {
      developer.log('Error starting call: $e');
      _cleanUpCall();
      rethrow;
    }
  }

  // Handle incoming call
  Future<void> _handleIncomingCall(
    String from,
    RTCSessionDescription description,
  ) async {
    if (_isCalling || _isReceivingCall) {
      // Already in a call, reject
      try {
        await _signalingService.sendCallRejected(from);
      } catch (e) {
        developer.log('Error rejecting call: $e');
      }
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
        try {
          await _signalingService.sendCallRejected(from);
        } catch (e) {
          developer.log('Error rejecting call: $e');
        }
        await _cleanUpCall();
        return;
      }

      // Create peer connection if not exists
      if (_peerConnection == null) {
        _peerConnection = await _createPeerConnection();
      }

      // Set remote description
      await _peerConnection!.setRemoteDescription(description);

      // Create and set local description
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // Send answer back to caller
      await _signalingService.sendAnswer(answer, from);

      _isReceivingCall = false;
      _notifyStateChange();
    } catch (e) {
      developer.log('Error handling incoming call: $e');
      try {
        await _signalingService.sendCallRejected(from);
      } catch (e) {
        developer.log('Error rejecting call: $e');
      }
      await _cleanUpCall();
      rethrow;
    }
  }

  /// Handles call acceptance by creating an answer and sending it to the caller
  Future<void> acceptCall() async {
    if (_callerId == null) return;

    _isReceivingCall = false;
    _currentCallState = CallState.inCall;
    _notifyStateChange();

    try {
      // Create answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // Send answer to caller
      await _signalingService.sendAnswer(answer, _callerId!);
    } catch (e) {
      developer.log('Error accepting call: $e');
      try {
        await _signalingService.sendCallRejected(_callerId!);
      } catch (e) {
        developer.log('Error sending call rejection: $e');
      }
      await _cleanUpCall();
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

    await _cleanUpCall();
  }

  // Clean up call resources
  Future<void> _cleanUpCall() async {
    _stopCallTimeout();

    // Close peer connection
    await _peerConnection?.close();
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
    peerConnection.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate != null) {
        _handleIceCandidate(candidate).catchError((error) {
          developer.log('Error handling ICE candidate: $error');
        });
      }
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
        _cleanUpCall().catchError((error) {
          developer.log('Error cleaning up call: $error');
        });
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
    for (final track in _localStream!.getTracks()) {
      _peerConnection!.addTrack(track, _localStream!);
    }

    onLocalStream?.call(_localStream);

    return peerConnection;
  }

  Future<void> _handleIceCandidate(RTCIceCandidate candidate) async {
    if (_remoteUserId != null) {
      await _signalingService.sendIceCandidate(candidate, _remoteUserId!);
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
      final stream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );
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
          return false;
        }

        if (!isPermanentlyDenied) {
          // If not permanently denied, try requesting again after user acknowledges
          return _requestPermissions(buildContext);
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
                const SnackBar(
                  content: Text(
                    'Failed to request permissions. Please try again.',
                  ),
                ),
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
        // Use then() to handle the Future returned by endCall()
        endCall().then((_) {
          // Show timeout message to user
          if (_context != null && _context!.mounted) {
            try {
              ScaffoldMessenger.of(_context!).showSnackBar(
                const SnackBar(content: Text('Call timed out')),
              );
            } catch (e) {
              developer.log('Error showing timeout message: $e');
            }
          }
        }).catchError((error) {
          developer.log('Error during call timeout handling: $error');
        });
      }
    });
  }

  // Stop call timeout
  void _stopCallTimeout() {
    _callTimeout?.cancel();
    _callTimeout = null;
  }

  @override
  Future<void> dispose() async {
    _offerSubscription?.cancel();
    _answerSubscription?.cancel();
    _candidateSubscription?.cancel();
    await _cleanUpCall();
    _signalingService.dispose();
    super.dispose();
  }
}
