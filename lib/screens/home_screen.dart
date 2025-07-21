import 'package:flutter/material.dart';
import 'package:webrtccaller/screens/rider_screen.dart';

import 'driver_screen.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Home')),
      body: Column(
        children: [
          Expanded(child: RiderScreen()),
          Expanded(child: DriverScreen()),
        ],
      ),
    );
  }
}
