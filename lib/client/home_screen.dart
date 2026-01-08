import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:keah_logistics/client/userProfile_screen.dart';
import 'package:keah_logistics/client/order_screen.dart';
import 'package:keah_logistics/client/tracking_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String userName = "Client";
  String? userImage;
  bool _isSyncing = false;
  int _currentIndex = 0;

  static const Color goldYellow = Color(0xFFFFD700);
  static const Color darkBlue = Color(0xFF0D1B2A);

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    _syncUserData();
  }

  Future<void> _loadLocalData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        userName = prefs.getString('userName') ?? "Valued Client";
        userImage = prefs.getString('userImage');
      });
    }
  }

  // --- UPDATED SYNC LOGIC WITH JWT AUTHORIZATION ---
  Future<void> _syncUserData() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString('userEmail');
    final String? token = prefs.getString(
      'token',
    ); // Retrieve the JWT saved during login

    if (email == null || token == null) {
      debugPrint("Missing email or token. Sync aborted.");
      return;
    }

    if (mounted) setState(() => _isSyncing = true);

    try {
      final response = await http
          .get(
            Uri.parse(
              'https://keahlogistics.netlify.app/.netlify/functions/api/user?email=${email.trim()}',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token', // The critical security update
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final freshName = data['fullName'] ?? userName;
        final freshImage = data['profileImage'];

        await prefs.setString('userName', freshName);
        if (freshImage != null) await prefs.setString('userImage', freshImage);

        if (mounted) {
          setState(() {
            userName = freshName;
            userImage = freshImage;
          });
        }
      } else if (response.statusCode == 401) {
        debugPrint("Unauthorized: Token may be expired.");
        // Optional: Redirect user to login screen if token is invalid
      }
    } catch (e) {
      debugPrint("Netlify Sync Error: $e");
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex && index == 0) return;

    setState(() => _currentIndex = index);

    if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const OrderScreen()),
      ).then((_) => setState(() => _currentIndex = 0));
    } else if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const TrackingScreen()),
      ).then((_) => setState(() => _currentIndex = 0));
    } else if (index == 3) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const OrderScreen()),
      ).then((_) => setState(() => _currentIndex = 0));
    } else if (index == 4) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const UserProfileScreen()),
      ).then((_) {
        setState(() => _currentIndex = 0);
        _syncUserData();
      });
    }
  }

  ImageProvider? _getProfileImage(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return null;
    if (imagePath.startsWith('http')) return NetworkImage(imagePath);
    try {
      String cleanBase64 = imagePath.contains(',')
          ? imagePath.split(',')[1]
          : imagePath;
      return MemoryImage(base64Decode(cleanBase64));
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: darkBlue,
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(10.0),
          child: GestureDetector(
            onTap: () => _onTabTapped(4),
            child: CircleAvatar(
              backgroundColor: goldYellow.withOpacity(0.2),
              backgroundImage: _getProfileImage(userImage),
              child: (userImage == null)
                  ? const Icon(Icons.person, color: goldYellow, size: 18)
                  : null,
            ),
          ),
        ),
        title: Column(
          children: [
            const Text(
              "KEAH LOGISTICS",
              style: TextStyle(
                color: goldYellow,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            if (_isSyncing)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  color: goldYellow,
                  minHeight: 1,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.notifications_none,
              color: goldYellow,
              size: 22,
            ),
            onPressed: () {},
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _syncUserData,
        color: goldYellow,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 30),
              Text(
                "Welcome back,",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                ),
              ),
              Text(
                userName.split(' ')[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 25),
              _buildStatusCard(),
              const SizedBox(height: 40),
              _buildSectionTitle("QUICK ACTIONS"),
              const SizedBox(height: 15),
              _buildMainActionTile(
                "Send a Package",
                "Instant pickup & delivery",
                Icons.local_shipping_outlined,
                () => _onTabTapped(1),
              ),
              const SizedBox(height: 15),
              _buildMainActionTile(
                "Track Shipment",
                "Check your order progress",
                Icons.explore_outlined,
                () => _onTabTapped(2),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [darkBlue, darkBlue.withOpacity(0.8)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: goldYellow.withOpacity(0.1)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user, color: goldYellow, size: 14),
              SizedBox(width: 8),
              Text(
                "SYSTEM SECURE",
                style: TextStyle(
                  color: goldYellow,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            "Your deliveries are secured and being processed in real-time. Thanks for using Keah Logistics.",
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildMainActionTile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: goldYellow.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: goldYellow, size: 24),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white12,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(width: 3, height: 12, color: goldYellow),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        backgroundColor: darkBlue,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: goldYellow,
        unselectedItemColor: Colors.white24,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: "Send",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore),
            label: "Track",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Orders"),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}
