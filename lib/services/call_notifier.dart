import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class CallNotifier extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRinging = false;
  String? _currentCallId;
  String? _callerId;

  bool get isRinging => _isRinging;
  String? get currentCallId => _currentCallId;
  String? get callerId => _callerId;

  // Start ringing for an incoming call
  Future<void> startRinging({required String callId, required String callerId}) async {
    if (_isRinging) return;
    
    _currentCallId = callId;
    _callerId = callerId;
    _isRinging = true;
    
    // Play ringtone (loop until stopped)
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sounds/call_ringtone.mp3'));
    
    notifyListeners();
  }

  // Stop ringing (when call is answered or declined)
  Future<void> stopRinging() async {
    if (!_isRinging) return;
    
    await _audioPlayer.stop();
    _isRinging = false;
    _currentCallId = null;
    _callerId = null;
    
    notifyListeners();
  }

  // Clean up resources
  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
