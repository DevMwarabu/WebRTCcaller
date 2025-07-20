import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

/// A utility class for handling app permissions in a centralized way.
class AppPermissions {
  /// Checks if both camera and microphone permissions are granted.
  static Future<bool> get hasCameraAndMicPermissions async {
    final cameraStatus = await Permission.camera.status;
    final micStatus = await Permission.microphone.status;
    
    return cameraStatus.isGranted && micStatus.isGranted;
  }

  /// Requests camera and microphone permissions.
  /// Returns true if both permissions are granted, false otherwise.
  static Future<bool> requestCameraAndMicPermissions() async {
    try {
      // Request both permissions in parallel
      final statuses = await [
        Permission.camera.request(),
        Permission.microphone.request(),
      ].wait;

      // Check if all permissions were granted
      final allGranted = statuses.every((status) => status.isGranted);
      
      if (!allGranted) {
        // If permissions are permanently denied, open app settings
        final cameraStatus = await Permission.camera.status;
        final micStatus = await Permission.microphone.status;
        
        if (cameraStatus.isPermanentlyDenied || 
            micStatus.isPermanentlyDenied) {
          openAppSettings();
        }
      }
      
      return allGranted;
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      return false;
    }
  }

  /// Shows a dialog explaining why permissions are needed.
  /// Returns true if user wants to proceed with permission request.
  static Future<bool> showPermissionRationaleDialog(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text(
          'This app needs camera and microphone permissions to make video calls.\n\n'
          'Please grant these permissions in the next screen.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ?? false;
  }

  /// Shows a dialog when permissions are permanently denied.
  static Future<void> showPermissionDeniedDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text(
          'Camera and microphone permissions are required for video calls.\n\n'
          'Please enable them in the app settings to continue.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
