import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// A widget that displays a video stream with proper aspect ratio and controls.
/// 
/// This widget handles both local and remote video streams, with appropriate
/// mirroring for the local camera feed and error handling for missing streams.
class VideoView extends StatefulWidget {
  /// The media stream to display
  final MediaStream? stream;
  
  /// Whether this is the local user's video (affects mirroring and UI)
  final bool isLocal;
  
  /// Whether to mirror the video (typically true for local camera)
  final bool mirror;
  
  /// Callback when the video track is initialized
  final Function(RTCVideoRenderer)? onRendererCreated;

  const VideoView({
    super.key,
    required this.stream,
    this.isLocal = false,
    this.mirror = false,
    this.onRendererCreated,
  });

  @override
  State<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<VideoView> {
  late final RTCVideoRenderer _renderer;
  bool _isInitialized = false;
  bool _hasError = false;
  StreamSubscription<dynamic>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _renderer = RTCVideoRenderer();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    try {
      await _renderer.initialize();
      
      // Notify parent that renderer is ready
      widget.onRendererCreated?.call(_renderer);
      
      if (widget.stream != null) {
        _setupStreamListeners();
        _updateVideoTrack();
      }
      
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint('Failed to initialize video renderer: $e');
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }
  
  void _setupStreamListeners() {
    if (widget.stream == null) return;
    
    try {
      // Update video track immediately if available
      _updateVideoTrack();
      
      // Use a timer to periodically check for track changes
      // This is a workaround for the lack of proper stream change events
      _streamSubscription = Stream.periodic(const Duration(milliseconds: 500)).listen((_) {
        if (mounted) {
          _updateVideoTrack();
        }
      });
    } catch (e) {
      debugPrint('Error setting up stream listener: $e');
    }
  }
  
  void _updateVideoTrack() {
    if (widget.stream == null) return;
    
    final videoTracks = widget.stream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      _renderer.srcObject = widget.stream;
      if (mounted) {
        setState(() => _hasError = false);
      }
    } else if (mounted) {
      setState(() => _hasError = true);
    }
  }

  @override
  void didUpdateWidget(VideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Handle stream changes
    if (oldWidget.stream?.id != widget.stream?.id) {
      _updateVideoTrack();
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _renderer.srcObject = null;
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return _buildLoadingView();
    }
    
    if (_hasError || widget.stream == null) {
      return _buildErrorView();
    }

    return AspectRatio(
      aspectRatio: _getAspectRatio(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.isLocal ? 8.0 : 0.0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video stream
            RTCVideoView(
              _renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              mirror: widget.isLocal ? widget.mirror : false,
            ),
            
            // Semi-transparent overlay for local view
            if (widget.isLocal)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).primaryColor,
                    width: 2.0,
                  ),
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
                
            // User info overlay
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.isLocal ? 'You' : 'Remote',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            widget.isLocal ? 'Starting camera...' : 'Connecting...',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
  
  Widget _buildErrorView() {
    return Container(
      color: Colors.black12,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              widget.isLocal ? 'Camera not available' : 'No video stream',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  double _getAspectRatio() {
    try {
      // Try to get the aspect ratio from the video track
      final videoTrack = widget.stream?.getVideoTracks().firstOrNull;
      if (videoTrack != null) {
        final settings = videoTrack.getSettings();
        if (settings['aspectRatio'] != null) {
          return (settings['aspectRatio'] as num).toDouble();
        }
        
        // Fallback: calculate from width/height if available
        if (settings['width'] != null && settings['height'] != null) {
          final width = (settings['width'] as num).toDouble();
          final height = (settings['height'] as num).toDouble();
          if (width > 0 && height > 0) {
            return width / height;
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting aspect ratio: $e');
    }
    
    // Default to 16:9 if we can't determine the aspect ratio
    return 16 / 9;
  }
}
