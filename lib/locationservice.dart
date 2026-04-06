import 'package:geolocator/geolocator.dart';

class GeoLocationService {
  Future<bool> requestPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  // 🔥 more accurate & frequent updates
  Stream<Position> getPositionStream() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation, // highest GPS accuracy
      distanceFilter: 5, // update if bus moves 5 meters
    );
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}
