import 'dart:async';
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'signaling_service.dart';

// Constants for Realtime Database paths
const String callsPath = 'calls';
const String incomingPath = 'incoming';

class RealtimeDbSignalingService implements SignalingService {
  // Server URL is kept for future use if needed
  @override
  final String _serverUrl;
  final String _userId;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Stream controllers
  final StreamController<SignalingState> _stateController = 
      StreamController<SignalingState>.broadcast();
  final StreamController<SignalingMessage> _messageController = 
      StreamController<SignalingMessage>.broadcast();
  
  DatabaseReference? _userIncomingRef;
  StreamSubscription<DatabaseEvent>? _callSubscription;
  bool _isInitialized = false;
  @override
  Stream<SignalingState> get onStateChange => _stateController.stream;
  
  @override
  Stream<SignalingMessage> get onMessage => _messageController.stream;
  
  @override
  String get userId => _userId;
  
  @override
  bool get isConnected => _isInitialized;

  RealtimeDbSignalingService({
    required String serverUrl,
    required String userId,
  })  : _serverUrl = serverUrl,
        _userId = userId {
    _connect();
  }

  void _connect() async {
    try {
      // Sign in anonymously if not already authenticated
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
      }
      
      // Set up listener for incoming messages
      _userIncomingRef = _database.child('$callsPath/$_userId/$incomingPath');
      _callSubscription = _userIncomingRef!.onChildAdded.listen((event) async {
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        if (data != null) {
          final message = SignalingMessage.fromJson(Map<String, dynamic>.from(data));
          _messageController.add(message);
          // Remove the message after processing
          await event.snapshot.ref.remove();
        }
      });
      
      _stateController.add(SignalingState.connected);
      _isInitialized = true;
    } catch (e) {
      print('Error connecting to Firebase Realtime Database: $e');
      _stateController.add(SignalingState.error);
      _reconnect();
    }
  }
  
  void _reconnect() {
    Future.delayed(Duration(seconds: 2), _connect);
  }

  @override
  void sendMessage(SignalingMessage message) {
    if (!_isInitialized) return;
    
    final messageRef = _database
        .child('$callsPath/${message.to}/$incomingPath')
        .push();
    
    messageRef.set({
      'type': message.type,
      'data': message.data,
      'from': message.from,
      'to': message.to,
      'timestamp': ServerValue.timestamp,
    });
  }

  @override
  void sendOffer(RTCSessionDescription offer, String to) {
    sendMessage(
      SignalingMessage(
        type: 'offer',
        data: {
          'sdp': offer.sdp,
          'type': offer.type.toString().split('.').last,
        },
        from: _userId,
        to: to,
      ),
    );
  }

  @override
  void sendAnswer(RTCSessionDescription answer, String to) {
    sendMessage(
      SignalingMessage(
        type: 'answer',
        data: {
          'sdp': answer.sdp,
          'type': answer.type.toString().split('.').last,
        },
        from: _userId,
        to: to,
      ),
    );
  }

  @override
  void sendIceCandidate(RTCIceCandidate candidate, String to) {
    sendMessage(
      SignalingMessage(
        type: 'candidate',
        data: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
        from: _userId,
        to: to,
      ),
    );
  }

  @override
  void sendCallRequest(String to) {
    sendMessage(
      SignalingMessage(
        type: 'call-request',
        from: _userId,
        to: to,
      ),
    );
  }

  @override
  void sendCallAccepted(String to) {
    sendMessage(
      SignalingMessage(
        type: 'call-accepted',
        from: _userId,
        to: to,
      ),
    );
  }

  @override
  void sendCallRejected(String to) {
    sendMessage(
      SignalingMessage(
        type: 'call-rejected',
        from: _userId,
        to: to,
      ),
    );
  }

  @override
  void sendEndCall(String to) {
    sendMessage(
      SignalingMessage(
        type: 'end-call',
        from: _userId,
        to: to,
      ),
    );
  }
  

  


  @override
  Future<void> dispose() async {
    await _callSubscription?.cancel();
    await _stateController.close();
    await _messageController.close();
    _isInitialized = false;
  }
}
