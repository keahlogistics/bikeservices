import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../screens/adminLogin_screens.dart';
import 'riderManagement_screens.dart';
import 'userManagement_screens.dart';
import 'liveChatOrder_screens.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  static const Color goldYellow = Color(0xFFFFD700);
  static const Color darkBlue = Color(0xFF0D1B2A);
  static const Color cardBg = Color(0xFF1B263B);

  int userCount = 0;
  int riderCount = 0;
  int packageCount = 0;
  int activeRequests = 0;
  bool _isFetching = true;
  String _lastUpdated = "Syncing...";

  String _adminName = "Admin";
  String _adminEmail = "";

  @override
  void initState() {
    super.initState();
    _loadCachedData().then((_) {
      _fetchDashboardData();
    });
  }

  // --- CACHING ENGINE ---
  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        userCount = prefs.getInt('cache_userCount') ?? 0;
        riderCount = prefs.getInt('cache_riderCount') ?? 0;
        packageCount = prefs.getInt('cache_packageCount') ?? 0;
        activeRequests = prefs.getInt('cache_activeRequests') ?? 0;
        _adminName = prefs.getString('adminName') ?? "Admin";
        _adminEmail = prefs.getString('adminEmail') ?? "Logistics Admin";
        _lastUpdated = prefs.getString('cache_time') ?? "Initial Sync...";

        // Only stop showing the loader if we actually have cached data
        if (userCount > 0) _isFetching = false;
      });
    }
  }

  Future<void> _saveToCache(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final String now = DateFormat('hh:mm a').format(DateTime.now());

    await prefs.setInt('cache_userCount', data['totalUsers'] ?? 0);
    await prefs.setInt('cache_riderCount', data['activeRiders'] ?? 0);
    await prefs.setInt('cache_packageCount', data['totalPackages'] ?? 0);
    await prefs.setInt('cache_activeRequests', data['activeRequests'] ?? 0);
    await prefs.setString('cache_time', now);

    if (mounted) {
      setState(() => _lastUpdated = now);
    }
  }

  // --- UPDATED API CALL WITH FIXES ---
  Future<void> _fetchDashboardData() async {
    if (!mounted) return;
    setState(() => _isFetching = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      // Ensure we are pulling the same key as main.dart
      final String? token = prefs.getString('userToken');
      final String? role = prefs.getString('userRole');

      // Security Check - Added .toLowerCase() to prevent case-sensitive logout bugs
      if (token == null || token.isEmpty || (role?.toLowerCase() != 'admin')) {
        debugPrint("Access Denied: Missing token or incorrect role ($role)");
        _handleLogout();
        return;
      }

      const baseUrl =
          'https://keahlogistics.netlify.app/.netlify/functions/api';

      final response = await http
          .get(
            Uri.parse('$baseUrl/admin/stats'),
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer $token",
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveToCache(data);

        if (mounted) {
          setState(() {
            userCount = data['totalUsers'] ?? 0;
            riderCount = data['activeRiders'] ?? 0;
            packageCount = data['totalPackages'] ?? 0;
            activeRequests = data['activeRequests'] ?? 0;
            _isFetching = false;
          });
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        debugPrint("Session invalid: ${response.statusCode}");
        _handleLogout();
      } else {
        if (mounted) setState(() => _isFetching = false);
      }
    } catch (e) {
      debugPrint("Dashboard Sync Error: $e");
      if (mounted) setState(() => _isFetching = false);
    }
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();

    // Clear EVERYTHING related to the session to be safe
    await prefs.setBool('isLoggedIn', false);
    await prefs.remove('userToken');
    await prefs.remove('adminToken');
    await prefs.remove('userRole');
    await prefs.remove('userEmail');
    await prefs.remove('adminEmail');

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const AdminLoginScreen()),
      (route) => false,
    );
  }

  // ... [Keep the Build, buildStatsGrid, and build3DCard methods as they are, they are excellent] ...

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Column(
          children: [
            const Text(
              "KEAH COMMAND CENTER",
              style: TextStyle(
                color: goldYellow,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 2.0,
              ),
            ),
            Text(
              "LAST UPDATED: $_lastUpdated",
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        backgroundColor: darkBlue,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: goldYellow, size: 20),
            onPressed: _fetchDashboardData,
          ),
        ],
      ),
      body: _isFetching && userCount == 0
          ? const Center(
              child: CircularProgressIndicator(
                color: goldYellow,
                strokeWidth: 2,
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchDashboardData,
              color: goldYellow,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(),
                    const SizedBox(height: 12),
                    _buildStatsGrid(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _buildStickyFooter(),
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(width: 3, height: 12, color: goldYellow),
            const SizedBox(width: 8),
            const Text(
              "SYSTEM ANALYTICS",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        if (_isFetching && userCount > 0)
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: goldYellow,
            ),
          ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _build3DCard(
          "Total Users",
          userCount.toString(),
          Icons.people_rounded,
          Colors.blueAccent,
        ),
        _build3DCard(
          "Active Riders",
          riderCount.toString(),
          Icons.motorcycle,
          Colors.greenAccent,
        ),
        _build3DCard(
          "Total Packages",
          packageCount.toString(),
          Icons.inventory_2,
          goldYellow,
        ),
        _build3DCard(
          "Support Alerts",
          activeRequests.toString(),
          Icons.notifications_active,
          Colors.redAccent,
        ),
      ],
    );
  }

  Widget _build3DCard(String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            offset: const Offset(4, 4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -5,
            bottom: -5,
            child: Icon(icon, color: color.withOpacity(0.05), size: 60),
          ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        color: darkBlue,
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildFooterItem(
              Icons.grid_view_rounded,
              "Dash",
              () {},
              isActive: true,
            ),
            _buildFooterItem(Icons.people_alt_outlined, "Users", () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const UserManagementScreen(),
                ),
              );
            }),
            _buildFooterItem(Icons.chat_bubble_outline_rounded, "Chat", () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminLiveChatSystem(),
                ),
              );
            }),
            _buildFooterItem(Icons.pedal_bike, "Riders", () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RiderManagementScreen(),
                ),
              );
            }),
            _buildFooterItem(Icons.segment_rounded, "Menu", _showMoreMenu),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterItem(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isActive ? goldYellow : Colors.white24, size: 22),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? goldYellow : Colors.white24,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: darkBlue,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.forum_rounded, color: goldYellow),
              title: const Text(
                "Live Chat Center",
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminLiveChatSystem(),
                  ),
                );
              },
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.person_outline, color: goldYellow),
              title: Text(
                _adminName,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              subtitle: Text(
                _adminEmail,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text(
                "Logout System",
                style: TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
              onTap: () {
                Navigator.pop(context);
                _handleLogout();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
