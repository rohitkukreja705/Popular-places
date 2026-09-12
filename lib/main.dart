import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const BhopalFoodMapApp());
}

class BhopalFoodMapApp extends StatelessWidget {
  const BhopalFoodMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bhopal Food Map',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFD9663B),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

// ---------------------------------------------------------------
// Data models
// ---------------------------------------------------------------

class FoodPlace {
  final int id;
  final String name;
  final String area;
  final String knownFor;
  final String category;
  final double lat;
  final double lng;

  FoodPlace({
    required this.id,
    required this.name,
    required this.area,
    required this.knownFor,
    required this.category,
    required this.lat,
    required this.lng,
  });

  factory FoodPlace.fromJson(Map<String, dynamic> json) => FoodPlace(
        id: json['id'] as int,
        name: json['name'] as String,
        area: json['area'] as String,
        knownFor: json['known_for'] as String,
        category: json['category'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );

  LatLng get point => LatLng(lat, lng);
}

class FoodCategory {
  final String slug;
  final String name;
  final String description;

  FoodCategory({
    required this.slug,
    required this.name,
    required this.description,
  });

  factory FoodCategory.fromJson(Map<String, dynamic> json) => FoodCategory(
        slug: json['slug'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
      );
}

// ---------------------------------------------------------------
// Map screen
// ---------------------------------------------------------------

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Roughly central Bhopal (New Market / TT Nagar area).
  static const LatLng _bhopalCenter = LatLng(23.2494, 77.4079);

  List<FoodPlace> _allPlaces = [];
  List<FoodCategory> _categories = [];
  String? _selectedCategory; // null = All
  String _searchQuery = '';
  bool _loading = true;
  bool _searching = false;
  Position? _userPosition;
  bool _locating = false;

  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final raw = await rootBundle.loadString('assets/bhopal_food_places.json');
    final data = json.decode(raw) as Map<String, dynamic>;

    final places = (data['places'] as List)
        .map((e) => FoodPlace.fromJson(e as Map<String, dynamic>))
        .toList();
    final categories = (data['categories'] as List)
        .map((e) => FoodCategory.fromJson(e as Map<String, dynamic>))
        .toList();

    setState(() {
      _allPlaces = places;
      _categories = categories;
      _loading = false;
    });
  }

  List<FoodPlace> get _visiblePlaces {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _allPlaces.where((p) {
      final matchesCategory =
          _selectedCategory == null || p.category == _selectedCategory;
      final matchesSearch = q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.area.toLowerCase().contains(q) ||
          p.knownFor.toLowerCase().contains(q);
      return matchesCategory && matchesSearch;
    }).toList();

    if (_userPosition != null) {
      filtered.sort(
        (a, b) => _distanceKmFrom(a)!.compareTo(_distanceKmFrom(b)!),
      );
    }
    return filtered;
  }

  double? _distanceKmFrom(FoodPlace p) {
    final pos = _userPosition;
    if (pos == null) return null;
    final meters = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      p.lat,
      p.lng,
    );
    return meters / 1000;
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage('Location services are turned off on this device.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _showMessage('Location permission denied.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _showMessage(
          'Location permission permanently denied — enable it from app settings.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      setState(() => _userPosition = position);
      _mapController.move(LatLng(position.latitude, position.longitude), 14);
    } catch (_) {
      _showMessage('Could not get your location.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _openInMaps(FoodPlace place) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${place.lat},${place.lng}',
    );
    bool ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open a maps app for this link')),
      );
    }
  }

  void _showPlaceSheet(FoodPlace place) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(place.area, style: TextStyle(color: Colors.grey[700])),
                if (_distanceKmFrom(place) != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${_distanceKmFrom(place)!.toStringAsFixed(1)} km away',
                    style: const TextStyle(
                      color: Color(0xFFD9663B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(place.knownFor, style: const TextStyle(fontSize: 15, height: 1.35)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openInMaps(place),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Open in Google Maps'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final places = _visiblePlaces;
    final markers = places
        .map(
          (p) => Marker(
            point: p.point,
            width: 34,
            height: 34,
            child: GestureDetector(
              onTap: () => _showPlaceSheet(p),
              child: const Icon(
                Icons.location_on,
                color: Color(0xFFD9663B),
                size: 34,
              ),
            ),
          ),
        )
        .toList();

    if (_userPosition != null) {
      markers.add(
        Marker(
          point: LatLng(_userPosition!.latitude, _userPosition!.longitude),
          width: 24,
          height: 24,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search name, area, dish...',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('Bhopal Food Map'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCategoryChips(),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: _bhopalCenter,
                    initialZoom: 12,
                    minZoom: 10,
                    maxZoom: 18,
                  ),
                  children: [
                    // Free OpenStreetMap raster tiles. Fine for development
                    // and light real usage; OSM's tile usage policy asks
                    // heavier / public-facing apps to move to a dedicated
                    // free tile provider (e.g. Stadia Maps, MapTiler, or a
                    // self-hosted OpenMapTiles instance) instead of hammering
                    // the shared tile.openstreetmap.org servers directly.
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.bhopalfoodmap.app',
                    ),
                    MarkerLayer(markers: markers),
                  ],
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(blurRadius: 4, color: Colors.black26),
                      ],
                    ),
                    child: Text(
                      _userPosition == null
                          ? '${places.length} of ${_allPlaces.length} places'
                          : '${places.length} of ${_allPlaces.length} \u2022 nearest first',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _locating ? null : _useMyLocation,
        tooltip: 'Use my location',
        child: _locating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.my_location),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: const Text('All'),
              selected: _selectedCategory == null,
              onSelected: (_) => setState(() => _selectedCategory = null),
            ),
          ),
          for (final c in _categories)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(c.name),
                selected: _selectedCategory == c.slug,
                onSelected: (_) => setState(() => _selectedCategory = c.slug),
              ),
            ),
        ],
      ),
    );
  }
}
