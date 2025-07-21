class RideRequest {
  final String id;
  final String riderId;
  final double lat;
  final double lng;
  final String? driverId;

  RideRequest({
    required this.id,
    required this.riderId,
    required this.lat,
    required this.lng,
    this.driverId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'riderId': riderId,
      'lat': lat,
      'lng': lng,
      'driverId': driverId,
    };
  }

  static RideRequest fromMap(Map map) {
    return RideRequest(
      id: map['id'],
      riderId: map['riderId'],
      lat: map['lat'],
      lng: map['lng'],
      driverId: map['driverId'],
    );
  }
}