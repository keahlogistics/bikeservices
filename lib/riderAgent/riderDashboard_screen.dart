import 'dart:convert'; // REQUIRED for Base64 decoding
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RiderDashboardScreen extends StatefulWidget {
  const RiderDashboardScreen({super.key});

  @override
  State<RiderDashboardScreen> createState() => _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends State<RiderDashboardScreen> {
  String riderName = "Rider Agent";
  String? profileImageBase64;
  bool _isLoading = true;

  // Theme Colors matching Keah Logistics branding
  static const Color goldYellow = Color(0xFFFFD700);
  static const Color darkBlue = Color(0xFF0D1B2A);

  @override
  void initState() {
    super.initState();
    _loadRiderData();
  }

  // Load the data saved during login from SharedPreferences
  Future<void> _loadRiderData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Keys match the ones saved in your LoginScreen logic
      riderName = prefs.getString('riderName') ?? "Rider Agent";
      profileImageBase64 = prefs.getString('riderImage');
      _isLoading = false;
    });
  }

  // Logout Function
  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Wipes the session
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: darkBlue,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "RIDER PORTAL",
          style: TextStyle(
            color: goldYellow,
            fontWeight: FontWeight.bold,
            fontSize: 16,
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () => _showLogoutDialog(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: goldYellow))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 30),

                  // --- RIDER PROFILE SECTION ---
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: goldYellow,
                            shape: BoxShape.circle,
                          ),
                          child: CircleAvatar(
                            radius: 60,
                            backgroundColor: darkBlue,
                            // Safe decoding of Base64 image
                            backgroundImage:
                                (profileImageBase64 != null &&
                                    profileImageBase64!.isNotEmpty)
                                ? MemoryImage(base64Decode(profileImageBase64!))
                                : const AssetImage(
                                        'assets/images/default_rider.png',
                                      )
                                      as ImageProvider,
                          ),
                        ),
                        const SizedBox(height: 15),
                        Text(
                          "Welcome Back,",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          riderName.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Chip(
                          side: BorderSide.none,
                          backgroundColor: Color(0xFF1B5E20), // Dark Green
                          label: Text(
                            "ACTIVE STATUS",
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // --- ACTION BUTTONS ---
                  _buildDashboardAction(
                    title: "AVAILABLE PICKUPS",
                    subtitle: "View packages waiting for collection",
                    icon: Icons.local_shipping,
                    color: goldYellow,
                    onTap: () {
                      // TODO: Navigate to Available Pickups screen
                    },
                  ),

                  const SizedBox(height: 15),

                  _buildDashboardAction(
                    title: "MY DELIVERIES",
                    subtitle: "Track your ongoing tasks",
                    icon: Icons.map_outlined,
                    color: Colors.white,
                    onTap: () {
                      // TODO: Navigate to ongoing deliveries screen
                    },
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  // Logout Confirmation Dialog
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: darkBlue,
        title: const Text("Logout", style: TextStyle(color: goldYellow)),
        content: const Text(
          "Are you sure you want to log out?",
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: _handleLogout,
            child: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Custom widget for Dashboard Buttons
  Widget _buildDashboardAction({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    bool isPrimary = color == goldYellow;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isPrimary ? goldYellow : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: goldYellow.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isPrimary ? darkBlue : goldYellow.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: goldYellow, size: 30),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isPrimary ? darkBlue : Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isPrimary
                          ? darkBlue.withOpacity(0.7)
                          : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: isPrimary ? darkBlue : Colors.white24,
            ),
          ],
        ),
      ),
    );
  }
}
