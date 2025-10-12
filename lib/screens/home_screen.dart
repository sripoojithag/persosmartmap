import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'bookmark_screen.dart';
import 'reminder_screen.dart';
import 'map_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 2; // Show MapScreen by default
  LatLng? _mapInitialLocation;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late AnimationController _zoomController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _zoomController,
        curve: Curves.easeOut,
      ),
    );
    if (_currentIndex >= 0 && _currentIndex < 3) {
      _zoomController.forward();
    }
  }

  void _navigateToMap(LatLng location) {
    setState(() {
      _mapInitialLocation = location;
      _currentIndex = 2;
      _updateZoom();
    });
  }

  void _onButtonTap(int index) {
    setState(() {
      _currentIndex = index;
      if (index != 2) _mapInitialLocation = null;
      _updateZoom();
    });
  }

  void _updateZoom() {
    _zoomController.reset();
    _zoomController.forward();
  }

  @override
  void dispose() {
    _zoomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      const ReminderScreen(),
      BookmarkScreen(onNavigateToMap: _navigateToMap),
      MapScreen(
        initialLocation: _mapInitialLocation,
        scaffoldKey: _scaffoldKey,
      ),
    ];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(child: screens[_currentIndex]),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 70,
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavButton(
                      icon: Icons.alarm, index: 0, label: 'Reminders'),
                  _buildNavButton(
                      icon: Icons.bookmark, index: 1, label: 'Bookmarks'),
                  _buildNavButton(icon: Icons.map, index: 2, label: 'Maps'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required int index,
    required String label,
  }) {
    final bool isSelected = _currentIndex == index;
    final Color glowColor = Colors.greenAccent.shade400;
    final Color baseColor = const Color(0xff141313);

    return GestureDetector(
      onTap: () => _onButtonTap(index),
      child: AnimatedScale(
        scale: isSelected ? _scaleAnimation.value : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? glowColor.withOpacity(0.2)
                    : Colors.transparent,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: glowColor.withOpacity(0.6),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
              padding: const EdgeInsets.all(10),
              child: Icon(
                icon,
                color: baseColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: baseColor,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                shadows: isSelected
                    ? [
                        Shadow(
                          color: glowColor.withOpacity(0.5),
                          blurRadius: 4,
                        ),
                      ]
                    : [],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
