# WebRTC Caller

A Flutter application that demonstrates WebRTC-based video calling functionality with WebSocket signaling.

## Features

- Video and audio calling using WebRTC
- WebSocket-based signaling server
- Cross-platform support (Android, iOS, Web)
- Responsive UI that works on different screen sizes
- Camera and microphone permissions handling

## Prerequisites

- Flutter SDK (3.8.1 or later)
- Dart SDK (3.8.1 or later)
- Android Studio / Xcode (for mobile development)
- Web browser (for web development)

## Setup

1. Clone the repository
   ```bash
   git clone https://github.com/yourusername/webrtc_caller.git
   cd webrtc_caller
   ```

2. Install dependencies
   ```bash
   flutter pub get
   ```

3. Configure the signaling server
   - Update the `signalingServerUrl` in `lib/config/config.dart` to point to your WebSocket signaling server

4. Run the app
   ```bash
   # For mobile
   flutter run
   
   # For web
   flutter run -d chrome --web-renderer html
   ```

## Project Structure

- `lib/`
  - `config/` - Configuration files
  - `models/` - Data models
  - `screens/` - App screens
  - `services/` - Business logic and services
  - `utils/` - Utility classes and helpers
  - `widgets/` - Reusable UI components

## Dependencies

- `flutter_webrtc`: WebRTC plugin for Flutter
- `provider`: State management
- `permission_handler`: Handle runtime permissions
- `web_socket_channel`: WebSocket communication
- `responsive_builder`: Responsive UI components

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
