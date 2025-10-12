import 'package:flutter/material.dart';

class BlinkingMarker extends StatefulWidget {
  const BlinkingMarker({Key? key}) : super(key: key);

  @override
  State<BlinkingMarker> createState() => _BlinkingMarkerState();
}

class _BlinkingMarkerState extends State<BlinkingMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(_controller);
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: const Icon(Icons.location_on, size: 40, color: Colors.red),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
