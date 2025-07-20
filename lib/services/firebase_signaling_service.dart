import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

// Constants for Firestore collections
const String callsCollection = 'calls';
const String incomingCollection = 'incoming';

enum SignalingMessageType {
  offer,
  answer,
  candidate,
  rejection,
}

abstract class SignalingService {
  Future<void> initialize(String userId);
  Future<void> sendOffer(String to, RTCSessionDescription description);
  Future<void> sendAnswer(String to, RTCSessionDescription description);
  Future<void> sendIceCandidate(String to, RTCIceCandidate candidate);
  Future<void> sendRejection(String to, String reason);
  Future<void> dispose();
  Stream<Map<String, dynamic>> get onCall;
}

class FirebaseSignalingService implements SignalingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Stream controllers
  final StreamController<Map<String, dynamic>> _callController = 
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<RTCSessionDescription> _offerController = 
      StreamController<RTCSessionDescription>.broadcast();
  final StreamController<RTCSessionDescription> _answerController = 
      StreamController<RTCSessionDescription>.broadcast();
  final StreamController<RTCIceCandidate> _candidateController = 
      StreamController<RTCIceCandidate>.broadcast();
  
  StreamSubscription? _callSubscription;
  String? _currentUserId;
  bool _isInitialized = false;
  
  // Getters for streams
  Stream<RTCSessionDescription> get onOffer => _offerController.stream;
  Stream<RTCSessionDescription> get onAnswer => _answerController.stream;
  Stream<RTCIceCandidate> get onCandidate => _candidateController.stream;
  
  @override
  Stream<Map<String, dynamic>> get onCall => _callController.stream;

  @override
  Future<void> initialize(String userId) async {
    if (_isInitialized) return;
    
    _currentUserId = userId;
    
    // Sign in anonymously if not already authenticated
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
    
    // Listen for incoming signaling messages
    _callSubscription = _firestore
        .collection(callsCollection)
        .doc(userId)
        .collection(incomingCollection)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) async {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          await _handleIncomingMessage(data);
        }
      }
    });
    
    _isInitialized = true;
  }

  @override
  Future<void> sendOffer(String to, RTCSessionDescription description) async {
    if (_currentUserId == null) return;
    
    await _sendMessage(
      to: to,
      type: SignalingMessageType.offer,
      data: {
        'sdp': description.sdp,
        'type': description.type,
      },
    );
  }

  @override
  Future<void> sendAnswer(String to, RTCSessionDescription description) async {
    if (_currentUserId == null) return;
    
    await _sendMessage(
      to: to,
      type: SignalingMessageType.answer,
      data: {
        'sdp': description.sdp,
        'type': description.type,
      },
    );
  }

  @override
  Future<void> sendIceCandidate(String to, RTCIceCandidate candidate) async {
    if (_currentUserId == null) return;
    
    await _sendMessage(
      to: to,
      type: SignalingMessageType.candidate,
      data: {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    );
  }

  @override
  Future<void> sendRejection(String to, String reason) async {
    if (_currentUserId == null) return;
    
    await _sendMessage(
      to: to,
      type: SignalingMessageType.rejection,
      data: {'reason': reason},
    );
  }
  
  Future<void> _sendMessage({
    required String to,
    required SignalingMessageType type,
    required Map<String, dynamic> data,
  }) async {
    if (_currentUserId == null) return;
    
    await _firestore
        .collection(callsCollection)
        .doc(to)
        .collection(incomingCollection)
        .add({
      'type': type.toString().split('.').last,
      'from': _currentUserId,
      'data': data,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
  
  Future<void> _handleIncomingMessage(Map<String, dynamic> data) async {
    final from = data['from'] as String?;
    final type = data['type'] as String?;
    final messageData = data['data'] as Map<String, dynamic>?;
    
    if (from == null || type == null || messageData == null) return;
    
    switch (type) {
      case 'offer':
        final sdp = messageData['sdp'] as String?;
        final sdpType = messageData['type'] as String?;
        if (sdp != null && sdpType != null) {
          _offerController.add(RTCSessionDescription(sdp, sdpType));
        }
        break;
        
      case 'answer':
        final sdp = messageData['sdp'] as String?;
        final sdpType = messageData['type'] as String?;
        if (sdp != null && sdpType != null) {
          _answerController.add(RTCSessionDescription(sdp, sdpType));
        }
        break;
        
      case 'candidate':
        final candidate = messageData['candidate'] as String?;
        final sdpMid = messageData['sdpMid'] as String?;
        final sdpMLineIndex = messageData['sdpMLineIndex'] as int?;
        
        if (candidate != null && sdpMid != null && sdpMLineIndex != null) {
          _candidateController.add(RTCIceCandidate(
            candidate,
            sdpMid,
            sdpMLineIndex,
          ));
        }
        break;
        
      case 'rejection':
        final reason = messageData['reason'] as String?;
        _callController.add({
          'type': 'rejected',
          'from': from,
          'reason': reason ?? 'Call rejected',
        });
        break;
    }
    
    _callController.add({
      'type': type,
      'from': from,
      'data': messageData,
    });
  }
  
  @override
  Future<void> dispose() async {
    await _callSubscription?.cancel();
    await _callController.close();
    await _offerController.close();
    await _answerController.close();
    await _candidateController.close();
    _isInitialized = false;
  }
}
