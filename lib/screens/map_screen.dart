import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/blinking_marker.dart';

class MapScreen extends StatefulWidget {
  final LatLng? initialLocation;
  final GlobalKey<ScaffoldState> scaffoldKey;
  const MapScreen({Key? key, this.initialLocation, required this.scaffoldKey})
      : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapController? _mapController;
  LatLng? _initialPosition;
  List<Marker> _markers = [];
  List<Map<String, dynamic>> _savedLocations = [];
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  Timer? _debounce;
  Position? _currentPosition;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _initialPosition = widget.initialLocation ?? const LatLng(0.0, 0.0);
    if (widget.initialLocation == null) {
      _getUserLocation();
    }
    _loadSavedLocations();
    if (widget.initialLocation != null) {
      _showNavigationFeedback();
      _updateMapForInitialLocation();
    }
    _isInitialized = true;
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isInitialized &&
        widget.initialLocation != oldWidget.initialLocation &&
        widget.initialLocation != null) {
      setState(() {
        _initialPosition = widget.initialLocation;
      });
      _updateMapForInitialLocation();
      _showNavigationFeedback();
    }
  }

  void _updateMapForInitialLocation() {
    if (!_isInitialized || _mapController == null || _initialPosition == null)
      return;
    _markers.clear();
    _loadSavedLocations();
    _mapController!.move(_initialPosition!, 14.0);
  }

  Future<void> _showNavigationFeedback() async {
    await _loadSavedLocations();
    final bookmark = _savedLocations.firstWhere(
      (loc) =>
          loc['lat'] == widget.initialLocation?.latitude &&
          loc['lng'] == widget.initialLocation?.longitude,
      orElse: () => {'name': 'Location'},
    );
    if (mounted && widget.scaffoldKey.currentContext != null) {
      ScaffoldMessenger.of(widget.scaffoldKey.currentContext!).showSnackBar(
        SnackBar(content: Text('Navigated to ${bookmark['name']}')),
      );
    }
  }

  Future<void> _getUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted && widget.scaffoldKey.currentContext != null) {
        ScaffoldMessenger.of(widget.scaffoldKey.currentContext!).showSnackBar(
          const SnackBar(content: Text('Please enable location services')),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted && widget.scaffoldKey.currentContext != null) {
          ScaffoldMessenger.of(widget.scaffoldKey.currentContext!).showSnackBar(
            const SnackBar(content: Text('Location permissions denied')),
          );
        }
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted && widget.scaffoldKey.currentContext != null) {
        ScaffoldMessenger.of(widget.scaffoldKey.currentContext!).showSnackBar(
          const SnackBar(
              content: Text('Location permissions permanently denied')),
        );
      }
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _initialPosition = LatLng(position.latitude, position.longitude);
          _addMarker(_initialPosition!, 'My Location');
          if (_mapController != null) {
            _mapController!.move(_initialPosition!, 14.0);
          }
        });
      }
    } catch (e) {
      if (mounted && widget.scaffoldKey.currentContext != null) {
        ScaffoldMessenger.of(widget.scaffoldKey.currentContext!).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
    }
  }

  Future<void> _loadSavedLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBookmarks = prefs.getStringList('saved_locations');
    if (savedBookmarks != null) {
      setState(() {
        _savedLocations = savedBookmarks
            .map((bookmark) => jsonDecode(bookmark) as Map<String, dynamic>)
            .toList();
        _markers.removeWhere((marker) => marker.key == const ValueKey('temp'));
        for (var location in _savedLocations) {
          final position = LatLng(location['lat'], location['lng']);
          if (!_markers.any((m) => m.point == position)) {
            _addMarker(position, location['name']);
          }
        }
      });
    }
  }

  void fetchSearchSuggestions(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (query.isEmpty || _currentPosition == null) {
        setState(() => _searchResults = []);
        return;
      }
      const minLat = 8.0;
      const maxLat = 37.0;
      const minLon = 68.0;
      const maxLon = 97.0;
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=10&viewbox=$minLon,$maxLat,$maxLon,$minLat&bounded=1&countrycodes=in',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'SmartMapNavigator/1.0 (contact@example.com)'},
      );
      if (response.statusCode == 200 && mounted) {
        final results = jsonDecode(response.body) as List<dynamic>;
        results.sort((a, b) {
          final distA = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            double.parse(a['lat']),
            double.parse(a['lon']),
          );
          final distB = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            double.parse(b['lat']),
            double.parse(b['lon']),
          );
          return distA.compareTo(distB);
        });
        setState(() => _searchResults = results);
      }
    });
  }

  void _addBlinkingMarker(LatLng position, String name,
      {bool isTemporary = false}) {
    setState(() {
      _markers.add(
        Marker(
          key: isTemporary ? const ValueKey('temp') : null,
          point: position,
          width: 80.0,
          height: 80.0,
          child: GestureDetector(
            onTap: () => _showSaveLocationDialog(
                context, position.latitude, position.longitude),
            child: const BlinkingMarker(),
          ),
        ),
      );
    });
  }

  void _showSaveLocationDialog(BuildContext context, double lat, double lon) {
    if (!mounted) return;
    final nameController = TextEditingController();
    final noteController = TextEditingController();
    String selectedCategory = 'General';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(
          'Save Current Location',
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 20, color: Colors.black87),
        ),
        content: Container(
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Location Details',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xff18948a)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[200],
                  hintText: 'Enter a location name',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[200],
                  hintText: 'Add comments or details',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              const Text(
                'Category',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xff18948a)),
              ),
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[200],
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
                  ),
                ),
                dropdownColor: Colors.white,
                style: const TextStyle(color: Colors.black87, fontSize: 16),
                iconEnabledColor: Colors.blue[700],
                items: const [
                  DropdownMenuItem(value: 'General', child: Text('General')),
                  DropdownMenuItem(value: 'Work', child: Text('Work')),
                  DropdownMenuItem(value: 'Travel', child: Text('Travel')),
                  DropdownMenuItem(value: 'Home', child: Text('Home')),
                  DropdownMenuItem(
                      value: 'Favorites', child: Text('Favorites')),
                  DropdownMenuItem(
                      value: 'Uncategorized', child: Text('Uncategorized')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      selectedCategory = value;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim().isEmpty
                  ? 'Unnamed Location'
                  : nameController.text.trim();
              final notes = noteController.text.trim();
              final prefs = await SharedPreferences.getInstance();
              if (mounted) {
                setState(() {
                  _savedLocations.add({
                    'name': name,
                    'lat': lat,
                    'lng': lon,
                    'notes': notes,
                    'category': selectedCategory,
                  });
                  _markers.add(
                    Marker(
                      key: ValueKey('$lat-$lon'),
                      point: LatLng(lat, lon),
                      width: 80.0,
                      height: 100.0,
                      child: GestureDetector(
                        onTap: () => _zoomToMarker(LatLng(lat, lon)),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: const Icon(
                                Icons.location_pin,
                                color: Colors.red,
                                size: 40,
                              ),
                            ),
                            Text(
                              name.length > 10
                                  ? '${name.substring(0, 10)}...'
                                  : name,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                });
                await prefs.setStringList(
                  'saved_locations',
                  _savedLocations.map((e) => jsonEncode(e)).toList(),
                );
                Navigator.pop(context);
                if (widget.scaffoldKey.currentContext != null) {
                  ScaffoldMessenger.of(widget.scaffoldKey.currentContext!)
                      .showSnackBar(
                    SnackBar(content: Text('Saved: $name')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Save',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  void _addMarker(LatLng point, String name) {
    final isNavigatedLocation = widget.initialLocation != null &&
        (point.latitude - widget.initialLocation!.latitude).abs() < 0.001 &&
        (point.longitude - widget.initialLocation!.longitude).abs() < 0.001;
    if (!mounted) return;
    setState(() {
      final key = isNavigatedLocation
          ? const ValueKey('navigated')
          : ValueKey('${point.latitude}-${point.longitude}');
      if (!_markers.any((m) => m.key == key)) {
        _markers.add(
          Marker(
            key: key,
            point: point,
            width: 80.0,
            height: 100.0,
            child: GestureDetector(
              onTap: () => _zoomToMarker(point),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: isNavigatedLocation
                        ? const Icon(
                            Icons.bookmark,
                            color: Color(0xFF4CAF50),
                            size: 36,
                          )
                        : const Icon(
                            Icons.location_pin,
                            color: Colors.red,
                            size: 40,
                          ),
                  ),
                  Text(
                    name.length > 10 ? '${name.substring(0, 10)}...' : name,
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    });
  }

  void _zoomToMarker(LatLng point) {
    if (_mapController != null) {
      _mapController!.move(point, 16.0);
    }
  }

  void _saveCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted && widget.scaffoldKey.currentContext != null) {
          ScaffoldMessenger.of(widget.scaffoldKey.currentContext!).showSnackBar(
            const SnackBar(content: Text('Please enable location services')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted && widget.scaffoldKey.currentContext != null) {
            ScaffoldMessenger.of(widget.scaffoldKey.currentContext!)
                .showSnackBar(
              const SnackBar(content: Text('Location permissions denied')),
            );
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted && widget.scaffoldKey.currentContext != null) {
          ScaffoldMessenger.of(widget.scaffoldKey.currentContext!).showSnackBar(
            const SnackBar(
                content: Text('Location permissions permanently denied')),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        _showSaveLocationDialog(context, position.latitude, position.longitude);
      }
    } catch (e) {
      if (mounted && widget.scaffoldKey.currentContext != null) {
        ScaffoldMessenger.of(widget.scaffoldKey.currentContext!).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
    }
  }

  void _searchByCoordinates() {
    final latController = TextEditingController();
    final lonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Search by Coordinates',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Color(0xff18948a)),
        ),
        content: Container(
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 300, maxHeight: 200),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              TextField(
                controller: latController,
                decoration: InputDecoration(
                  labelText: 'Latitude',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[200],
                  hintText: 'Enter latitude',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lonController,
                decoration: InputDecoration(
                  labelText: 'Longitude',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[200],
                  hintText: 'Enter longitude',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () {
              final lat = double.tryParse(latController.text);
              final lon = double.tryParse(lonController.text);
              if (lat != null &&
                  lon != null &&
                  lat >= -90 &&
                  lat <= 90 &&
                  lon >= -180 &&
                  lon <= 180) {
                final position = LatLng(lat, lon);
                setState(() {
                  _markers.removeWhere(
                      (marker) => marker.key == const ValueKey('temp'));
                  _addBlinkingMarker(position, 'Searched Location',
                      isTemporary: true);
                  if (_mapController != null) {
                    _mapController!.move(position, 14.0);
                  }
                });
                Navigator.pop(context);
              } else if (widget.scaffoldKey.currentContext != null) {
                ScaffoldMessenger.of(widget.scaffoldKey.currentContext!)
                    .showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Enter valid coordinates (Lat: -90 to 90, Lon: -180 to 180)')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Search',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  void _clearNonNavigatedMarkers() {
    setState(() {
      _markers
          .removeWhere((marker) => marker.key != const ValueKey('navigated'));
      if (widget.scaffoldKey.currentContext != null) {
        ScaffoldMessenger.of(widget.scaffoldKey.currentContext!).showSnackBar(
          const SnackBar(content: Text('Non-navigated markers cleared')),
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _mapController == null || _initialPosition == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: _initialPosition,
              zoom: 14.0,
              maxZoom: 18.0,
              minZoom: 3.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.app',
              ),
              MarkerLayer(markers: _markers),
            ],
          ),
          Positioned(
            top: 50,
            left: 10,
            right: 10,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue[700]!, Colors.blue[300]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Search for a place...',
                    hintStyle: TextStyle(color: Colors.white70, fontSize: 16),
                    prefixIcon: const Icon(Icons.search, color: Colors.white),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                    filled: false,
                  ),
                  onChanged: fetchSearchSuggestions,
                ),
              ),
            ),
          ),
          if (_searchResults.isNotEmpty)
            Positioned(
              top: 110,
              left: 10,
              right: 10,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final result = _searchResults[index];
                      final distance = _currentPosition != null
                          ? Geolocator.distanceBetween(
                              _currentPosition!.latitude,
                              _currentPosition!.longitude,
                              double.parse(result['lat']),
                              double.parse(result['lon']),
                            )
                          : 0.0;
                      return ListTile(
                        title: Text(
                          result['display_name'],
                          style: const TextStyle(color: Colors.black),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${(distance / 1000).toStringAsFixed(2)} km away',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        onTap: () {
                          final lat = double.parse(result['lat']);
                          final lon = double.parse(result['lon']);
                          final position = LatLng(lat, lon);
                          setState(() {
                            _markers.removeWhere((marker) =>
                                marker.key == const ValueKey('temp'));
                            _addBlinkingMarker(position, result['display_name'],
                                isTemporary: true);
                            if (_mapController != null) {
                              _mapController!.move(position, 14.0);
                            }
                            _searchResults = [];
                            _searchController.clear();
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 64.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
              onPressed: _clearNonNavigatedMarkers,
              tooltip: 'Clear Bookmarks',
              child: const Icon(Icons.delete),
            ),
            const SizedBox(height: 10),
            FloatingActionButton(
              onPressed: _saveCurrentLocation,
              tooltip: 'Save Current Location',
              child: const Icon(Icons.bookmark_add),
            ),
            const SizedBox(height: 10),
            FloatingActionButton(
              onPressed: _searchByCoordinates,
              tooltip: 'Search by Coordinates',
              child: const Icon(Icons.my_location),
            ),
          ],
        ),
      ),
    );
  }
}
