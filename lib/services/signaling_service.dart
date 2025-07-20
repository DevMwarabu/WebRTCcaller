import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum SignalingState {
  connected,
  disconnected,
  error,
}

class SignalingMessage {
  final String type;
  final dynamic data;
  final String? from;
  final String? to;

  SignalingMessage({
    required this.type,
    this.data,
    this.from,
    this.to,
  });

  factory SignalingMessage.fromJson(Map<String, dynamic> json) {
    return SignalingMessage(
      type: json['type'],
      data: json['data'],
      from: json['from'],
      to: json['to'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'data': data,
      'from': from,
      'to': to,
    };
  }
}

class SignalingService {
  final String _serverUrl;
  final String _userId;
  WebSocketChannel? _channel;
  StreamController<SignalingState> _stateController = StreamController<SignalingState>.broadcast();
  StreamController<SignalingMessage> _messageController = StreamController<SignalingMessage>.broadcast();

  SignalingService({
    required String serverUrl,
    required String userId,
  })  : _serverUrl = serverUrl,
        _userId = userId {
    _connect();
  }

  Stream<SignalingState> get onStateChange => _stateController.stream;
  Stream<SignalingMessage> get onMessage => _messageController.stream;

  String get userId => _userId;

  bool get isConnected => _channel?.sink != null;

  void _connect() async {
    try {
      // Close existing connection if any
      await _channel?.sink.close();

      // Create new connection
      _channel = WebSocketChannel.connect(Uri.parse('$_serverUrl/ws?userId=$_userId'));
      _stateController.add(SignalingState.connected);

      // Listen for incoming messages
      _channel?.stream.listen(
        (message) {
          try {
            final msg = SignalingMessage.fromJson(json.decode(message));
            _messageController.add(msg);
          } catch (e) {
            print('Error parsing message: $e');
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          _stateController.add(SignalingState.error);
          _reconnect();
        },
        onDone: () {
          print('WebSocket connection closed');
          _stateController.add(SignalingState.disconnected);
          _reconnect();
        },
      );
    } catch (e) {
      print('Error connecting to signaling server: $e');
      _stateController.add(SignalingState.error);
      _reconnect();
    }
  }

  void _reconnect() {
    Future.delayed(Duration(seconds: 2), _connect);
  }

  void sendMessage(SignalingMessage message) {
    _channel?.sink.add(json.encode(message.toJson()));
  }

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

  void sendCallRequest(String to) {
    sendMessage(
      SignalingMessage(
        type: 'call-request',
        from: _userId,
        to: to,
      ),
    );
  }

  void sendCallAccepted(String to) {
    sendMessage(
      SignalingMessage(
        type: 'call-accepted',
        from: _userId,
        to: to,
      ),
    );
  }

  void sendCallRejected(String to) {
    sendMessage(
      SignalingMessage(
        type: 'call-rejected',
        from: _userId,
        to: to,
      ),
    );
  }

  void sendEndCall(String to) {
    sendMessage(
      SignalingMessage(
        type: 'end-call',
        from: _userId,
        to: to,
      ),
    );
  }

  Future<void> dispose() async {
    await _channel?.sink.close();
    await _stateController.close();
    await _messageController.close();
  }
}
