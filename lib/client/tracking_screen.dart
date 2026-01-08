import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:keah_logistics/client/order_screen.dart';
import 'package:keah_logistics/client/userProfile_screen.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  static const Color goldYellow = Color(0xFFFFD700);
  static const Color darkBlue = Color(0xFF0D1B2A);

  // Map State
  final Completer<GoogleMapController> _mapController = Completer();
  final Set<Marker> _markers = {};

  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _orderData;
  int _currentIndex = 2; // Fixed on "Track"

  // Default camera position: Lagos, Nigeria
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(6.5244, 3.3792),
    zoom: 14.0,
  );

  // --- LOGIC: FETCH TRACKING DATA FROM NETLIFY ---

  Future<void> _trackOrder(String trackingId) async {
    if (trackingId.isEmpty) {
      _showSnackBar("Please enter a Tracking ID", Colors.orange);
      return;
    }

    setState(() {
      _isLoading = true;
      _orderData = null;
      _markers.clear();
    });

    try {
      final url = Uri.parse(
        'https://keahlogistics.netlify.app/.netlify/functions/api/track/${trackingId.trim()}',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _orderData = data;
          _updateMapMarkers(data);
        });
      } else {
        _showSnackBar("Order ID not found.", Colors.redAccent);
      }
    } catch (e) {
      _showSnackBar("Connection error. Check your internet.", Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateMapMarkers(Map<String, dynamic> data) async {
    // Parse coordinates from API or fallback to defaults if not provided yet
    double riderLat =
        double.tryParse(data['riderLat']?.toString() ?? '') ?? 6.5350;
    double riderLng =
        double.tryParse(data['riderLng']?.toString() ?? '') ?? 3.3850;
    double destLat =
        double.tryParse(data['destLat']?.toString() ?? '') ?? 6.5244;
    double destLng =
        double.tryParse(data['destLng']?.toString() ?? '') ?? 3.3792;

    LatLng riderPos = LatLng(riderLat, riderLng);
    LatLng destinationPos = LatLng(destLat, destLng);

    setState(() {
      _markers.clear();
      // Rider Marker
      _markers.add(
        Marker(
          markerId: const MarkerId('rider'),
          position: riderPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueYellow,
          ),
          infoWindow: const InfoWindow(title: "Rider Current Location"),
        ),
      );
      // Destination Marker
      _markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destinationPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: "Delivery Point"),
        ),
      );
    });

    // Animate camera to show the rider
    if (_mapController.isCompleted) {
      final GoogleMapController controller = await _mapController.future;
      controller.animateCamera(CameraUpdate.newLatLngZoom(riderPos, 14));
    }
  }

  // --- NAVIGATION ---

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);

    switch (index) {
      case 0:
        Navigator.popUntil(context, (route) => route.isFirst);
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const OrderScreen()),
        );
        break;
      case 4:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const UserProfileScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          _buildLiveMapHeader(),
          _buildSearchBarOverlay(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: goldYellow),
                  )
                : _orderData == null
                ? _buildEmptyState()
                : _buildTrackingContent(),
          ),
        ],
      ),
      bottomNavigationBar: _buildStickyFooter(),
    );
  }

  Widget _buildLiveMapHeader() {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.38,
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialPosition,
            markers: _markers,
            onMapCreated: (controller) => _mapController.complete(controller),
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
          ),
          // Gradient Overlay for readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.7),
                  Colors.transparent,
                  Colors.black,
                ],
              ),
            ),
          ),
          Positioned(
            top: 50,
            left: 20,
            child: CircleAvatar(
              backgroundColor: darkBlue,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: goldYellow),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBarOverlay() {
    return Container(
      transform: Matrix4.translationValues(0, -30, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        elevation: 15,
        borderRadius: BorderRadius.circular(15),
        color: darkBlue,
        child: TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Enter Tracking ID (e.g. KEAH-101)",
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: goldYellow),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            suffixIcon: IconButton(
              icon: const Icon(Icons.local_shipping, color: goldYellow),
              onPressed: () => _trackOrder(_searchController.text.trim()),
            ),
          ),
          onSubmitted: (val) => _trackOrder(val.trim()),
        ),
      ),
    );
  }

  Widget _buildTrackingContent() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRiderCard(),
          const SizedBox(height: 30),
          const Text(
            "SHIPMENT PROGRESS",
            style: TextStyle(
              color: goldYellow,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 20),
          _buildStatusTimeline(_orderData?['status'] ?? 'Pending'),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildRiderCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: darkBlue,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.white10,
            child: Icon(Icons.delivery_dining, color: goldYellow),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Keah Express Rider",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Status: ${_orderData?['status'] ?? 'Processing'}",
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.phone_in_talk, color: Colors.greenAccent),
            onPressed: () {
              _showSnackBar("Calling Rider...", Colors.blueGrey);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline(String currentStatus) {
    List<String> stages = [
      "Order Placed",
      "Picked Up",
      "In Transit",
      "Out for Delivery",
      "Delivered",
    ];
    int currentStageIndex = stages.indexWhere(
      (s) => s.toLowerCase() == currentStatus.toLowerCase(),
    );
    if (currentStageIndex == -1) currentStageIndex = 0;

    return Column(
      children: List.generate(stages.length, (index) {
        bool isCompleted = index <= currentStageIndex;
        return Row(
          children: [
            Column(
              children: [
                Icon(
                  isCompleted
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: isCompleted ? goldYellow : Colors.white10,
                  size: 20,
                ),
                if (index != stages.length - 1)
                  Container(
                    width: 2,
                    height: 30,
                    color: isCompleted ? goldYellow : Colors.white10,
                  ),
              ],
            ),
            const SizedBox(width: 15),
            Text(
              stages[index],
              style: TextStyle(
                color: isCompleted ? Colors.white : Colors.white24,
                fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.map_outlined,
            size: 80,
            color: Colors.white.withOpacity(0.05),
          ),
          const SizedBox(height: 10),
          const Text(
            "Enter a Tracking ID to start",
            style: TextStyle(color: Colors.white24),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyFooter() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: _onTabTapped,
      backgroundColor: darkBlue,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: goldYellow,
      unselectedItemColor: Colors.white38,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.grid_view_rounded),
          label: "Home",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.add_circle_outline),
          label: "Send",
        ),
        BottomNavigationBarItem(icon: Icon(Icons.explore), label: "Track"),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: "Orders"),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          label: "Profile",
        ),
      ],
    );
  }

  void _showSnackBar(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
