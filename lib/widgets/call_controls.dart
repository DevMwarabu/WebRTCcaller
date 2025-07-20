import 'package:flutter/material.dart';

/// A widget that displays call control buttons based on the call state.
/// 
/// This widget shows different sets of buttons depending on whether the user
/// is in a call, receiving a call, or in a call setup state.
class CallControls extends StatelessWidget {
  /// Whether the user is currently in an outgoing call
  final bool isCalling;
  
  /// Whether the user is currently receiving an incoming call
  final bool isReceivingCall;
  
  /// Callback when the end call button is pressed
  final VoidCallback onEndCall;
  
  /// Callback when the accept call button is pressed
  final VoidCallback onAcceptCall;
  
  /// Callback when the reject call button is pressed
  final VoidCallback onRejectCall;

  /// Creates a call controls widget
  const CallControls({
    super.key,
    required this.isCalling,
    required this.isReceivingCall,
    required this.onEndCall,
    required this.onAcceptCall,
    required this.onRejectCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Active call controls (end call)
          if (isCalling && !isReceivingCall) ..._buildActiveCallControls(),
          
          // Incoming call controls (accept/reject)
          if (isReceivingCall) ..._buildIncomingCallControls(),
        ],
      ),
    );
  }
  
  /// Builds the controls shown during an active call
  List<Widget> _buildActiveCallControls() {
    return [
      _buildControlButton(
        icon: Icons.call_end,
        backgroundColor: Colors.red,
        onPressed: onEndCall,
        tooltip: 'End Call',
      ),
    ];
  }
  
  /// Builds the controls shown when receiving an incoming call
  List<Widget> _buildIncomingCallControls() {
    return [
      _buildControlButton(
        icon: Icons.call,
        backgroundColor: Colors.green,
        onPressed: onAcceptCall,
        tooltip: 'Accept',
      ),
      const SizedBox(width: 20),
      _buildControlButton(
        icon: Icons.call_end,
        backgroundColor: Colors.red,
        onPressed: onRejectCall,
        tooltip: 'Decline',
      ),
    ];
  }

  /// Builds a single control button with the specified parameters
  Widget _buildControlButton({
    required IconData icon,
    required Color backgroundColor,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    final button = Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 5,
            spreadRadius: 2,
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 28),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor,
          padding: const EdgeInsets.all(16),
        ),
      ),
    );
    
    return tooltip != null 
        ? Tooltip(
            message: tooltip,
            preferBelow: false,
            child: button,
          )
        : button;
  }
}
