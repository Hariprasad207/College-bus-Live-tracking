import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class UserMapScreen extends StatefulWidget {
  const UserMapScreen({super.key});

  @override
  State<UserMapScreen> createState() => _UserMapScreenState();
}

class _UserMapScreenState extends State<UserMapScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _orsApiKey =
      'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjNlMWU2MjQ5YTMxMzRjNzNiMjg4ZjUyOTNiN2VmY2Q5IiwiaCI6Im11cm11cjY0In0=';

  GoogleMapController? _mapController;
  StreamSubscription<QuerySnapshot>? _busSub;

  /// MAP DATA
  final Map<String, Marker> _busMarkers = {};
  final Set<Marker> _stopMarkers = {};
  final Set<Polyline> _polylines = {};

  /// BUS DATA
  final List<Map<String, dynamic>> _inactiveBuses = [];
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _allBuses = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _orderedStops = [];

  QueryDocumentSnapshot<Map<String, dynamic>>? _selectedBus;
  String _nextStop = '-';
  String _etaNext = '-';

  DateTime? _lastEtaUpdate;
  static const int _etaInterval = 6;

  static const LatLng _chennai = LatLng(13.0827, 80.2707);

  @override
  void initState() {
    super.initState();
    _listenBuses();
  }

  // ================= BUS STREAM =================
  void _listenBuses() {
    _busSub?.cancel();
    _busSub = _firestore.collection('buses').snapshots().listen((snap) {
      _inactiveBuses.clear();
      _allBuses.clear();

      for (final doc in snap.docs) {
        _allBuses.add(doc);

        final d = doc.data();
        final isActive = d['active'] ?? true;

        if (!isActive) {
          _inactiveBuses.add({'id': doc.id});
        }

        if (d['latitude'] == null || d['longitude'] == null) continue;

        final pos = LatLng(
          (d['latitude'] as num).toDouble(),
          (d['longitude'] as num).toDouble(),
        );

        _busMarkers[doc.id] = Marker(
          markerId: MarkerId(doc.id),
          position: pos,
          zIndex: 10,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isActive ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange,
          ),
          onTap: isActive ? () => _selectBus(doc) : null,
        );

        if (_selectedBus?.id == doc.id && isActive) {
          _selectedBus = doc;
          _updateEta();
        }
      }

      if (mounted) setState(() {});
    });
  }

  // ================= SELECT BUS =================
  Future<void> _selectBus(
    QueryDocumentSnapshot<Map<String, dynamic>> bus,
  ) async {
    _selectedBus = bus;

    final d = bus.data();
    final pos = LatLng(
      (d['latitude'] as num).toDouble(),
      (d['longitude'] as num).toDouble(),
    );

    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 14));

    await _loadStops(bus.id);
    await _updateEta();

    if (mounted) setState(() {});
  }

  // ================= LOAD STOPS =================
  Future<void> _loadStops(String busId) async {
    final snap = await _firestore
        .collection('buses')
        .doc(busId)
        .collection('stops')
        .orderBy('stop_order')
        .get();

    _orderedStops = snap.docs;
    _stopMarkers.clear();

    final List<LatLng> pts = [];

    for (final s in snap.docs) {
      final p = LatLng(
        (s['latitude'] as num).toDouble(),
        (s['longitude'] as num).toDouble(),
      );
      pts.add(p);

      _stopMarkers.add(
        Marker(
          markerId: MarkerId('${busId}_${s.id}'),
          position: p,
          zIndex: 1,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    final route = await _buildRoute(pts);
    _polylines
      ..clear()
      ..add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: route,
          width: 5,
          color: Colors.blueAccent,
        ),
      );
  }

  // ================= ETA (NEXT STOP ONLY) =================
  Future<void> _updateEta() async {
    final now = DateTime.now();
    if (_lastEtaUpdate != null &&
        now.difference(_lastEtaUpdate!).inSeconds < _etaInterval) {
      return;
    }
    _lastEtaUpdate = now;

    if (_selectedBus == null || _orderedStops.isEmpty) return;

    final d = _selectedBus!.data();
    final busPos = LatLng(
      (d['latitude'] as num).toDouble(),
      (d['longitude'] as num).toDouble(),
    );

    int nearest = 0;
    double minD = double.infinity;

    for (int i = 0; i < _orderedStops.length; i++) {
      final p = LatLng(
        (_orderedStops[i]['latitude'] as num).toDouble(),
        (_orderedStops[i]['longitude'] as num).toDouble(),
      );
      final dist = _distance(busPos, p);
      if (dist < minD) {
        minD = dist;
        nearest = i;
      }
    }

    final nextIndex = nearest < _orderedStops.length - 1
        ? nearest + 1
        : nearest;

    final nextStop = _orderedStops[nextIndex];
    final etaN = await _fetchEta(busPos, _latLng(nextStop));

    if (!mounted) return;
    setState(() {
      _nextStop = nextStop['stopname'];
      _etaNext = '${etaN ?? '-'} min';
    });
  }

  // ================= HELPERS =================
  LatLng _latLng(QueryDocumentSnapshot<Map<String, dynamic>> d) => LatLng(
    (d['latitude'] as num).toDouble(),
    (d['longitude'] as num).toDouble(),
  );

  Future<int?> _fetchEta(LatLng s, LatLng e) async {
    final r = await http.post(
      Uri.parse('https://api.openrouteservice.org/v2/directions/driving-car'),
      headers: {
        'Authorization': _orsApiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'coordinates': [
          [s.longitude, s.latitude],
          [e.longitude, e.latitude],
        ],
      }),
    );

    if (r.statusCode != 200) return null;
    final d = jsonDecode(r.body);
    return (d['routes'][0]['summary']['duration'] / 60).round();
  }

  double _distance(LatLng a, LatLng b) {
    const r = 6371000;
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final x =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(a.latitude)) *
            cos(_rad(b.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(x), sqrt(1 - x));
  }

  double _rad(double d) => d * pi / 180;

  Future<List<LatLng>> _buildRoute(List<LatLng> pts) async {
    final res = <LatLng>[];
    for (int i = 0; i < pts.length - 1; i++) {
      res.addAll(await _segment(pts[i], pts[i + 1]));
    }
    return res;
  }

  Future<List<LatLng>> _segment(LatLng s, LatLng e) async {
    final r = await http.post(
      Uri.parse('https://api.openrouteservice.org/v2/directions/driving-car'),
      headers: {
        'Authorization': _orsApiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'coordinates': [
          [s.longitude, s.latitude],
          [e.longitude, e.latitude],
        ],
      }),
    );

    if (r.statusCode != 200) return [];
    return _decode(jsonDecode(r.body)['routes'][0]['geometry']);
  }

  List<LatLng> _decode(String encoded) {
    final pts = <LatLng>[];
    int i = 0, lat = 0, lng = 0;
    while (i < encoded.length) {
      int b, s = 0, r = 0;
      do {
        b = encoded.codeUnitAt(i++) - 63;
        r |= (b & 0x1f) << s;
        s += 5;
      } while (b >= 0x20);
      lat += (r & 1) != 0 ? ~(r >> 1) : (r >> 1);
      s = 0;
      r = 0;
      do {
        b = encoded.codeUnitAt(i++) - 63;
        r |= (b & 0x1f) << s;
        s += 5;
      } while (b >= 0x20);
      lng += (r & 1) != 0 ? ~(r >> 1) : (r >> 1);
      pts.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return pts;
  }

  @override
  void dispose() {
    _busSub?.cancel();
    super.dispose();
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live bus tracker')),
      body: SafeArea(
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _chennai,
                zoom: 12,
              ),
              onMapCreated: (c) => _mapController = c,
              markers: {..._busMarkers.values, ..._stopMarkers},
              polylines: _polylines,
              zoomControlsEnabled: false,
            ),

            /// 📢 NOTICE BOARD
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                color: Colors.amber.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Notice Board – Inactive Buses',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (_inactiveBuses.isEmpty)
                        const Text('All buses are active'),
                      if (_inactiveBuses.isNotEmpty)
                        SizedBox(
                          height: 40,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: _inactiveBuses
                                .map(
                                  (b) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Chip(
                                      label: Text(b['id']),
                                      backgroundColor: Colors.orange.shade200,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            /// 🔍 SEARCH BAR
            Positioned(
              top: 90,
              left: 12,
              right: 12,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child:
                    Autocomplete<QueryDocumentSnapshot<Map<String, dynamic>>>(
                      optionsBuilder: (t) => _allBuses
                          .where(
                            (b) => b.id.toLowerCase().contains(
                              t.text.toLowerCase(),
                            ),
                          )
                          .toList(),
                      displayStringForOption: (b) => b.id,
                      onSelected: _selectBus,
                      fieldViewBuilder: (_, c, f, __) => TextField(
                        controller: c,
                        focusNode: f,
                        decoration: const InputDecoration(
                          hintText: 'Search Bus (R01)',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(12),
                        ),
                      ),
                    ),
              ),
            ),

            /// 📍 BOTTOM INFO PANEL (ONLY WHEN BUS SELECTED)
            if (_selectedBus != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Next Stop: $_nextStop • ETA: $_etaNext',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Driver: ${_selectedBus!.data()['driverName'] ?? '-'}',
                        ),
                        Text(
                          'Phone: ${_selectedBus!.data()['driverPhone'] ?? '-'}',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
