import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' hide openAppSettings;
import 'package:permission_handler/permission_handler.dart' as permission_handler;

class AppPermissions {
  // Request camera and microphone permissions with proper iOS handling
  static Future<bool> requestCameraAndMicPermissions() async {
    try {
      debugPrint('AppPermissions: Requesting camera and microphone permissions...');
      
      // Request permissions one by one to handle each case properly
      final cameraStatus = await Permission.camera.request();
      debugPrint('AppPermissions: Camera permission status: $cameraStatus');
      
      // If camera was permanently denied, we should show a dialog
      if (cameraStatus.isPermanentlyDenied) {
        debugPrint('AppPermissions: Camera permission permanently denied');
        return false;
      }
      
      // Only request microphone if camera was not permanently denied
      final micStatus = await Permission.microphone.request();
      debugPrint('AppPermissions: Microphone permission status: $micStatus');
      
      // Check if we need to show the permission rationale
      if (cameraStatus.isDenied || micStatus.isDenied) {
        debugPrint('AppPermissions: Some permissions were denied');
        return false;
      }
      
      if (cameraStatus.isPermanentlyDenied || micStatus.isPermanentlyDenied) {
        debugPrint('AppPermissions: Some permissions were permanently denied');
        return false;
      }
      
      // Final check if all permissions are granted
      final allGranted = cameraStatus.isGranted && micStatus.isGranted;
      debugPrint('AppPermissions: All permissions granted: $allGranted');
      
      return allGranted;
    } catch (e) {
      debugPrint('AppPermissions: Error requesting permissions: $e');
      rethrow;
    }
  }

  // Check if camera and microphone permissions are granted
  static Future<bool> get hasCameraAndMicPermissions async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // On iOS, we need to check both status and request if needed
        final cameraStatus = await Permission.camera.status;
        final micStatus = await Permission.microphone.status;
        
        debugPrint('AppPermissions: Current camera permission: $cameraStatus');
        debugPrint('AppPermissions: Current microphone permission: $micStatus');
        
        // If either is permanently denied, we need to show settings
        if (cameraStatus.isPermanentlyDenied || micStatus.isPermanentlyDenied) {
          debugPrint('AppPermissions: Some permissions are permanently denied');
          return false;
        }
        
        return cameraStatus.isGranted && micStatus.isGranted;
      } else {
        // For other platforms, just check the status
        final cameraStatus = await Permission.camera.status;
        final micStatus = await Permission.microphone.status;
        
        debugPrint('AppPermissions: Current camera permission: $cameraStatus');
        debugPrint('AppPermissions: Current microphone permission: $micStatus');
        
        return cameraStatus.isGranted && micStatus.isGranted;
      }
    } catch (e) {
      debugPrint('AppPermissions: Error checking permissions: $e');
      return false;
    }
  }

  // Open app settings to allow users to enable permissions
  static Future<void> openAppSettings() async {
    print('Opening app settings...');
    await permission_handler.openAppSettings();
  }

  // Check if permissions are permanently denied
  static Future<bool> get arePermissionsPermanentlyDenied async {
    try {
      final cameraStatus = await Permission.camera.status;
      final micStatus = await Permission.microphone.status;
      
      print('Camera permanently denied: ${cameraStatus.isPermanentlyDenied}');
      print('Microphone permanently denied: ${micStatus.isPermanentlyDenied}');
      
      return (cameraStatus.isPermanentlyDenied || 
              micStatus.isPermanentlyDenied);
    } catch (e) {
      print('Error checking permanent denial: $e');
      return false;
    }
  }
}
