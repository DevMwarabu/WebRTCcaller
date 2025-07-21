import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/db_service.dart';
import '../services/ride_request.dart';
import '../services/call_service.dart';
import 'call_screen.dart';

class DriverScreen extends StatefulWidget {
  @override
  _DriverScreenState createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  final CallService _callService = CallService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RideRequest>>(
      stream: DBService().rideRequestStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        final requests = snapshot.data ?? [];
        return ListView.builder(
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final req = requests[index];
            return ListTile(
              title: Text("Request from ${req.riderId}"),
              subtitle: Text("Lat: ${req.lat}, Lng: ${req.lng}"),
              onTap: () async {
                final currentUser = FirebaseAuth.instance.currentUser;
                if (currentUser == null) return;

                try {
                  // Assign this driver to the request
                  await FirebaseDatabase.instance
                      .ref('ride_requests/${req.id}/driverId')
                      .set(currentUser.uid);

                  // Initialize local stream and join the call
                  await _callService.initializeLocalStream(_localRenderer);
                  
                  // Join the call with the ride request ID as the call ID
                  final result = await _callService.joinCall(
                    callId: req.id,
                    localUserId: currentUser.uid,
                    localRenderer: _localRenderer,
                    remoteRenderer: _remoteRenderer,
                  );

                  if (result != null) {
                    if (!mounted) return;
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CallScreen(
                          isCaller: false,
                          callId: req.id,
                          localUserId: currentUser.uid,
                          remoteUserId: req.riderId,
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error joining call: ${e.toString()}')),
                  );
                }
              },
              trailing: Icon(Icons.video_call),
            );
          },
        );
      },
    );
  }
}
