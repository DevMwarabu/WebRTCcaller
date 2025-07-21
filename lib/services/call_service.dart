import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';

import 'call_notifier.dart';

class CallService with ChangeNotifier {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };
  
  MediaStreamTrack? _audioTrack;
  MediaStreamTrack? _videoTrack;
  bool _isMuted = false;
  bool _isVideoOn = true;
  String _cameraDeviceId = '';

  /// Initializes the local media stream and sets it to the provided renderer
  Future<void> initializeLocalStream(RTCVideoRenderer localRenderer) async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
      },
    });
    
    _localStream = stream;
    _audioTrack = _localStream?.getAudioTracks().first;
    _videoTrack = _localStream?.getVideoTracks().first;
    localRenderer.srcObject = _localStream;
    
    // Store the current camera device ID
    if (_videoTrack != null) {
      final settings = _videoTrack!.getSettings();
      if (settings['deviceId'] != null) {
        _cameraDeviceId = settings['deviceId']!;
      }
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(
    RTCVideoRenderer remoteRenderer,
  ) async {
    final pc = await createPeerConnection(_iceServers);

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
      }
    };

    return pc;
  }

  void _addLocalTracks() {
    if (_localStream == null || _peerConnection == null) return;
    
    // Add audio track if available
    if (_audioTrack != null) {
      _peerConnection!.addTrack(_audioTrack!, _localStream!);
    }
    
    // Add video track if available and not muted
    if (_videoTrack != null && _isVideoOn) {
      _peerConnection!.addTrack(_videoTrack!, _localStream!);
    }
  }

  Future<Map<String, String>?> startCall({
    required String localUserId,
    required RTCVideoRenderer localRenderer,
    required RTCVideoRenderer remoteRenderer,
  }) async {
    final callId = _db.ref().child('calls').push().key!;
    final callRef = _db.ref('calls/$callId');

    await initializeLocalStream(localRenderer);
    _peerConnection = await _createPeerConnection(remoteRenderer);
    _addLocalTracks();

    // ICE candidate sender
    _peerConnection!.onIceCandidate = (candidate) {
      _db.ref('calls/$callId/ice/$localUserId').push().set({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // Create offer
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await callRef.set({
      'caller': localUserId,
      'receiver': '',
      'offer': offer.toMap(),
    });

    _listenForAnswer(callId);
    _listenForRemoteIce(callId, localUserId);

    return {'callId': callId, 'remoteUserId': ''};
  }

  /// Joins an existing call with the specified call ID
  /// 
  /// Throws [Exception] with a descriptive message if the call cannot be joined
  Future<Map<String, String>> joinCall({
    required String callId,
    required String localUserId,
    required RTCVideoRenderer localRenderer,
    required RTCVideoRenderer remoteRenderer,
  }) async {
    // Validate call ID format
    if (callId.isEmpty) {
      throw Exception('Call ID cannot be empty');
    }
    
    final callRef = _db.ref('calls/$callId');
    final snapshot = await callRef.get().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw Exception('Connection timeout. Please check your internet connection and try again.');
      },
    );

    if (!snapshot.exists) {
      throw Exception('Call not found. The call may have ended or the ID is incorrect.');
    }

    final callData = Map<String, dynamic>.from(snapshot.value as Map);
    final callerId = callData['caller'] as String? ?? '';
    
    if (callerId.isEmpty) {
      throw Exception('Invalid call data: No caller ID found');
    }

    await callRef.update({'receiver': localUserId});

    await initializeLocalStream(localRenderer);
    _peerConnection = await _createPeerConnection(remoteRenderer);
    _addLocalTracks();

    // ICE candidate sender
    _peerConnection!.onIceCandidate = (candidate) {
      _db.ref('calls/$callId/ice/$localUserId').push().set({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // Get offer from caller
    final offerMap = Map<String, dynamic>.from(callData['offer']);
    final offer = RTCSessionDescription(offerMap['sdp'], offerMap['type']);
    await _peerConnection!.setRemoteDescription(offer);

    // Create and send answer
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    await callRef.child('answer').set(answer.toMap());

    _listenForRemoteIce(callId, localUserId);

    return {'callId': callId, 'remoteUserId': callerId};
  }

  void _listenForAnswer(String callId) {
    _db.ref('calls/$callId/answer').onValue.listen((event) {
      if (event.snapshot.value != null && _peerConnection != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        final answer = RTCSessionDescription(data['sdp'], data['type']);
        _peerConnection!.setRemoteDescription(answer);
      }
    });
  }

  void _listenForRemoteIce(String callId, String selfId) {
    final otherUserId = selfId == 'caller' ? 'receiver' : 'caller';
    _db.ref('calls/$callId/ice').onChildAdded.listen((event) {
      final userId = event.snapshot.key;
      if (userId == selfId) return; // skip own candidates

      _db.ref('calls/$callId/ice/$userId').onChildAdded.listen((iceEvent) {
        final data = Map<String, dynamic>.from(iceEvent.snapshot.value as Map);
        final candidate = RTCIceCandidate(
          data['candidate'],
          data['sdpMid'],
          data['sdpMLineIndex'],
        );
        _peerConnection?.addCandidate(candidate);
      });
    });
  }

  /// Toggle mute state of the microphone
  Future<void> toggleMute(bool isMuted) async {
    if (_audioTrack != null) {
      _audioTrack!.enabled = !isMuted;
      _isMuted = isMuted;
      
      // Notify remote peer about mute state change
      if (_peerConnection != null) {
        final senders = await _peerConnection!.getSenders();
        final audioSender = senders.firstWhere(
          (s) => s.track?.kind == 'audio',
          orElse: () => null as RTCRtpSender,
        );
        
        if (audioSender != null) {
          await audioSender.replaceTrack(_audioTrack);
        }
      }
    }
  }

  /// Toggle video on/off
  Future<void> toggleVideo(bool isVideoOn) async {
    if (_videoTrack != null) {
      _videoTrack!.enabled = isVideoOn;
      _isVideoOn = isVideoOn;
      
      // If we're turning video back on, we need to renegotiate the connection
      if (isVideoOn && _peerConnection != null) {
        // Remove and re-add the video track to trigger renegotiation
        final senders = await _peerConnection!.getSenders();
        final videoSenders = senders.where((s) => s.track?.kind == 'video').toList();
        final sender = videoSenders.isNotEmpty ? videoSenders.first : null;
        
        if (sender != null) {
          await sender.replaceTrack(_videoTrack);
        } else if (_localStream != null) {
          _peerConnection!.addTrack(_videoTrack!, _localStream!);
        }
      }
    }
  }

  /// Switch between front and back camera
  Future<void> switchCamera(bool isFront) async {
    if (_videoTrack == null) return;
    
    try {
      // Get all video devices
      final devices = await navigator.mediaDevices.enumerateDevices();
      final videoDevices = devices.where((device) => device.kind == 'videoinput').toList();
      
      if (videoDevices.length < 2) return; // Need at least 2 cameras to switch
      
      // Find the other camera
      MediaDeviceInfo newDevice;
      try {
        newDevice = videoDevices.firstWhere(
          (device) => device.deviceId != _cameraDeviceId,
        );
      } catch (e) {
        newDevice = videoDevices.first;
      }
      
      // Stop the current track
      _videoTrack!.stop();
      
      // Get new stream with the other camera
      final stream = await navigator.mediaDevices.getUserMedia({
        'video': {
          'deviceId': {'exact': newDevice.deviceId},
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      });
      
      // Replace the video track
      final newVideoTrack = stream.getVideoTracks().first;
      _videoTrack = newVideoTrack;
      _cameraDeviceId = newDevice.deviceId;
      
      // Get all senders
      if (_peerConnection != null) {
        final senders = await _peerConnection!.getSenders();
        final videoSenders = senders.where((s) => s.track?.kind == 'video').toList();
        final videoSender = videoSenders.isNotEmpty ? videoSenders.first : null;
        
        // Replace the track in the peer connection
        if (videoSender != null) {
          await videoSender.replaceTrack(newVideoTrack);
        }
      }
      
      // Update the local stream
      if (_localStream != null) {
        // Remove old video tracks
        final videoTracks = _localStream!.getVideoTracks();
        for (var track in videoTracks) {
          _localStream!.removeTrack(track);
          await track.stop();
        }
        
        // Add new video track
        _localStream!.addTrack(newVideoTrack);
      }
      
      // Close the old stream
      await stream.dispose();
      
    } catch (e) {
      print('Error switching camera: $e');
      // Re-throw the error to be handled by the UI
      rethrow;
    }
  }

  /// End the current call and clean up resources
  Future<void> endCall(String callId) async {
    await _db.ref('calls/$callId').remove();
    
    // Close the peer connection
    if (_peerConnection != null) {
      await _peerConnection!.close();
      _peerConnection = null;
    }
    
    // Stop all tracks in the local stream
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }
    
    // Reset states
    _isMuted = false;
    _isVideoOn = true;
    _cameraDeviceId = '';
  }
}

extension on RTCSessionDescription {
  Map<String, dynamic> toMap() => {'sdp': sdp, 'type': type};
}
