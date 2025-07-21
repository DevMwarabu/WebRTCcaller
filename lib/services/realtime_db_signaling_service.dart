import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling_service.dart';

// Constants for Realtime Database paths
const String callsPath = 'calls';

class RealtimeDbSignalingService implements SignalingService {
  final String _userId;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  bool _isInitialized = false;
  
  // Stream controllers
  final StreamController<SignalingState> _stateController = 
      StreamController<SignalingState>.broadcast();
  final StreamController<SignalingMessage> _messageController = 
      StreamController<SignalingMessage>.broadcast();
  
  // Getters for streams
  @override
  Stream<SignalingState> get onStateChange => _stateController.stream;
  @override
  Stream<SignalingMessage> get onMessage => _messageController.stream;
  
  @override
  String get userId => _userId;
  
  @override
  bool get isConnected => _isInitialized;
  
  // Helper getters for specific message types
  Stream<SignalingMessage> get onOffer => _messageController.stream
      .where((message) => message.type == 'offer');
      
  Stream<SignalingMessage> get onAnswer => _messageController.stream
      .where((message) => message.type == 'answer');
      
  Stream<SignalingMessage> get onCandidate => _messageController.stream
      .where((message) => message.type == 'candidate');
      
  Stream<SignalingMessage> get onCall => _messageController.stream
      .where((message) => ['call-request', 'call-accepted', 'call-rejected', 'end-call'].contains(message.type));

  RealtimeDbSignalingService({
    required String userId,
  }) : _userId = userId {
    _connect();
  }
  
  void _connect() async {
    try {
      // Initialize the service
      await initialize(_userId);
      _stateController.add(SignalingState.connected);
    } catch (e) {
      _stateController.add(SignalingState.error);
      _reconnect();
    }
  }
  
  void _reconnect() {
    Future.delayed(Duration(seconds: 2), _connect);
  }
  
  // Initialize the service
  Future<void> initialize(String userId) async {
    if (_isInitialized) return;
    
    try {
      // Sign in anonymously if not already authenticated
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      
      // Set up listener for incoming messages
      _setupMessageListener();
      
      _isInitialized = true;
      _stateController.add(SignalingState.connected);
    } catch (e) {
      _stateController.add(SignalingState.error);
      rethrow;
    }
  }
  
  void _setupMessageListener() {
    print('Setting up message listener for user: $_userId');
    _database
        .child('$callsPath/$_userId/incoming')
        .onChildAdded
        .listen((event) async {
      print('New message received: ${event.snapshot.value}');
      if (event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        final message = SignalingMessage(
          type: data['type'],
          data: data['data'] ?? {},
          from: data['from'],
          to: data['to'],
        );
        
        // Forward the message to listeners
        _messageController.add(message);
        
        // Remove the message after processing
        await event.snapshot.ref.remove();
      }
    });
  }
  
  Future<void> _sendMessage(String type, dynamic data, String to) async {
    try {
      print('Sending message - type: $type, to: $to, data: $data');
      
      // Verify database reference
      final messagesRef = _database.child('$callsPath/$to/incoming');
      print('Database reference path: ${messagesRef.path}');
      
      // Check if we can write to the database
      try {
        final testRef = messagesRef.push();
        final testData = {'test': 'test', 'timestamp': ServerValue.timestamp};
        print('Testing database write access...');
        await testRef.set(testData);
        print('Database write test successful');
        await testRef.remove();
      } catch (e) {
        print('ERROR: Database write test failed: $e');
        throw Exception('Cannot write to database: $e');
      }
      
      // Send the actual message
      final messageRef = messagesRef.push();
      final messageData = {
        'type': type,
        'data': data,
        'from': _userId,
        'to': to,
        'timestamp': ServerValue.timestamp,
      };
      
      print('Sending message data: $messageData');
      await messageRef.set(messageData);
      print('Message sent successfully with key: ${messageRef.key}');
      
      // Verify the message was written
      final snapshot = await messageRef.get();
      if (snapshot.exists) {
        print('Message verified in database');
      } else {
        print('WARNING: Message not found in database after sending');
      }
    } catch (e, stack) {
      print('ERROR in _sendMessage:');
      print('Type: $e');
      print('Message: ${e.toString()}');
      print('Stack trace: $stack');
      rethrow;
    }
  }
  
  @override
  Future<void> sendMessage(SignalingMessage message) async {
    await _sendMessage(message.type, message.data, message.to!);
  }
  
  @override
  Future<void> sendOffer(RTCSessionDescription offer, String to) async {
    await _sendMessage('offer', {
      'sdp': offer.sdp,
      'type': offer.type.toString().split('.').last,
    }, to);
  }
  
  @override
  Future<void> sendAnswer(RTCSessionDescription answer, String to) async {
    await _sendMessage('answer', {
      'sdp': answer.sdp,
      'type': answer.type.toString().split('.').last,
    }, to);
  }
  
  @override
  Future<void> sendIceCandidate(RTCIceCandidate candidate, String to) async {
    await _sendMessage('candidate', {
      'candidate': candidate.candidate,
      'sdpMid': candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    }, to);
  }
  
  @override
  Future<void> sendCallRequest(String to) async {
    await _sendMessage('call-request', null, to);
  }
  
  @override
  Future<void> sendCallAccepted(String to) async {
    await _sendMessage('call-accepted', null, to);
  }
  
  @override
  Future<void> sendCallRejected(String to) async {
    await _sendMessage('call-rejected', null, to);
  }

  @override
  Future<void> sendEndCall(String to) async {
    await _sendMessage('end-call', null, to);
  }
  

  


  @override
  Future<void> dispose() async {
    try {
      // Close all stream controllers
      await _stateController.close();
      await _messageController.close();
      
      // Reset initialization state
      _isInitialized = false;
    } catch (e) {
      // Log any errors during disposal
      print('Error disposing RealtimeDbSignalingService: $e');
      rethrow;
    }
  }
}
