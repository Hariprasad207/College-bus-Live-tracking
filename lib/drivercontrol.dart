import 'package:driver_side/locationservice.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class DriverControlScreen extends StatefulWidget {
  const DriverControlScreen({super.key});

  @override
  State<DriverControlScreen> createState() => _DriverControlScreenState();
}

class _DriverControlScreenState extends State<DriverControlScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GeoLocationService _geoService = GeoLocationService();

  bool _isTracking = false;
  Position? _currentPosition;

  // Map driver email → bus ID
  final Map<String, String> driverBusMap = {
    "hari@gmail.com": "R01", //lokesh side
    "raghul@gmail.com": "R02", //bhuvi side
    "sita@gmail.com": "R03", //hari side
  };

  void startTracking() async {
    final user = _auth.currentUser;

    if (user == null || user.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User not logged in or email missing")),
      );
      return;
    }

    final busId = driverBusMap[user.email!];
    if (busId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No bus assigned")));
      return;
    }

    bool granted = await _geoService.requestPermission();
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location permission denied")),
      );
      return;
    }

    setState(() => _isTracking = true);

    _geoService.getPositionStream().listen((Position position) async {
      _currentPosition = position;

      await _firestore.collection('buses').doc(busId).set({
        'driverEmail': user.email,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'updatedAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));

      setState(() {});
    });
  }

  void stopTracking() {
    setState(() => _isTracking = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Location sharing stopped")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Driver Control")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _isTracking ? null : startTracking,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(220, 60),
              ),
              child: const Text(
                "Start Sharing Location",
                style: TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isTracking ? stopTracking : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                minimumSize: const Size(220, 60),
              ),
              child: const Text(
                "Stop Sharing Location",
                style: TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(height: 30),
            _currentPosition != null
                ? Text(
                    "Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}, "
                    "Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}",
                    style: const TextStyle(fontSize: 16),
                  )
                : const Text(
                    "Waiting for location...",
                    style: TextStyle(fontSize: 16),
                  ),
          ],
        ),
      ),
    );
  }
}
