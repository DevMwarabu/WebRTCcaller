class AppConfig {
  // Replace with your WebSocket signaling server URL
  static const String signalingServerUrl = 'ws://your-signaling-server.com';
  
  // You can add other configuration parameters here
  static const int callTimeoutSeconds = 30;
  static const bool enableLogging = true;
}
