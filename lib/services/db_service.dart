import 'package:firebase_database/firebase_database.dart';
import 'package:webrtccaller/services/ride_request.dart';

class DBService {
  Stream<List<RideRequest>> rideRequestStream() {
    return FirebaseDatabase.instance.ref('ride_requests').onValue.map((event) {
      final data = event.snapshot.value;
      if (data is! Map) return [];
      return (data as Map).values.map((e) => RideRequest.fromMap(Map<String, dynamic>.from(e))).toList();
    });
  }
}