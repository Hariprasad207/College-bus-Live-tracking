import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DriverLiveTracker extends StatefulWidget {
  final String driverEmail; // example: 'hari@gmail.com'
  final String busRoute; // example: 'R_01'

  const DriverLiveTracker({
    super.key,
    required this.driverEmail,
    required this.busRoute,
  });

  @override
  State<DriverLiveTracker> createState() => _DriverLiveTrackerState();
}

class _DriverLiveTrackerState extends State<DriverLiveTracker> {
  StreamSubscription<Position>? positionStream;
  Timer? firebaseTimer;
  Position? latestPosition;

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  Future<void> _startTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );

    positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position? pos) {
      if (pos != null) {
        setState(() => latestPosition = pos);
      }
    });

    firebaseTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (latestPosition != null) {
        _updateFirestore(latestPosition!);
      }
    });
  }

  Future<void> _updateFirestore(Position pos) async {
    try {
      await FirebaseFirestore.instance
          .collection('bus_locations')
          .doc(widget.busRoute)
          .set({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'driverEmail': widget.driverEmail,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint("✅ Location updated: ${pos.latitude}, ${pos.longitude}");
    } catch (e) {
      debugPrint("❌ Firestore update failed: $e");
    }
  }

  @override
  void dispose() {
    positionStream?.cancel();
    firebaseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Driver Live Tracker")),
      body: Center(
        child: latestPosition == null
            ? const Text("Fetching location...")
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Latitude: ${latestPosition!.latitude}"),
                  Text("Longitude: ${latestPosition!.longitude}"),
                  const SizedBox(height: 20),
                  const Text("Auto-updating every 30 seconds 🔄"),
                ],
              ),
      ),
    );
  }
}
