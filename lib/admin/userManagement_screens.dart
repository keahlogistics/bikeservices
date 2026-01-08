import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart'; // Added for IDrive Signed URL caching

// --- PROJECT IMPORTS ---
import 'riderManagement_screens.dart';
import 'liveChatOrder_screens.dart';
import '../screens/adminLogin_screens.dart';

// --- SHARED CONSTANTS ---
const Color goldYellow = Color(0xFFFFD700);
const Color darkBlue = Color(0xFF0D1B2A);

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<dynamic> _users = [];
  List<dynamic> _filteredUsers = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- OPTIMIZATION: LOAD CACHE THEN FETCH FRESH ---
  Future<void> _initializeData() async {
    await _loadCachedUsers();
    await _fetchAllUsers();
  }

  Future<void> _loadCachedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cachedData = prefs.getString('cached_client_list');
    if (cachedData != null && mounted) {
      try {
        final List<dynamic> decoded = jsonDecode(cachedData);
        setState(() {
          _users = decoded;
          _filteredUsers = decoded;
          _isLoading = false;
        });
      } catch (e) {
        debugPrint("Cache Decode Error: $e");
      }
    }
  }

  // --- HELPER: IMAGE PROVIDER (Updated for IDrive Private URLs) ---
  ImageProvider? _getProfileImage(String? imageStr) {
    if (imageStr == null || imageStr.isEmpty) return null;

    // 1. Handle IDrive Signed URLs (returned from Netlify Function)
    if (imageStr.startsWith('http')) {
      return CachedNetworkImageProvider(imageStr);
    }

    // 2. Handle Legacy/Local Base64 strings
    try {
      String clean = imageStr.contains(',') ? imageStr.split(',')[1] : imageStr;
      return MemoryImage(base64Decode(clean));
    } catch (e) {
      debugPrint("Image Decode Error: $e");
      return null;
    }
  }

  // --- API CALLS ---
  Future<void> _fetchAllUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('userToken');

      if (token == null || token.isEmpty) {
        _handleSessionExpired();
        return;
      }

      // Endpoint must use the getSecureUrl helper on the backend to return signed links
      final url = Uri.parse(
        'https://keahlogistics.netlify.app/.netlify/functions/api/admin/users',
      );

      final response = await http
          .get(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        await prefs.setString('cached_client_list', response.body);

        if (mounted) {
          setState(() {
            _users = data;
            _filteredUsers = data;
            _isLoading = false;
          });
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _handleSessionExpired();
      } else {
        _showSnackBar("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
      if (mounted) setState(() => _isLoading = false);
      _showSnackBar("Connection error. Please try again.");
    }
  }

  Future<void> _deleteUser(String userId) async {
    final bool? confirm = await _showDeleteDialog();
    if (confirm != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('userToken');

      final url = Uri.parse(
        'https://keahlogistics.netlify.app/.netlify/functions/api/admin/delete-user/$userId',
      );

      final response = await http.delete(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        _showSnackBar("User deleted successfully");
        _fetchAllUsers();
      } else if (response.statusCode == 401) {
        _handleSessionExpired();
      } else {
        _showSnackBar("Failed to delete user: ${response.statusCode}");
      }
    } catch (e) {
      _showSnackBar("Connection error during deletion");
    }
  }

  // --- SESSION & LOGOUT ---
  void _handleSessionExpired() {
    if (!mounted) return;
    _showSnackBar("Session expired. Please login again.");
    _logout();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
    await prefs.remove('userToken');
    await prefs.remove('userRole');
    await prefs.remove('adminEmail');

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (c) => const AdminLoginScreen()),
      (r) => false,
    );
  }

  // --- CSV EXPORT ---
  Future<void> _exportToCSV() async {
    if (_users.isEmpty) {
      _showSnackBar("No data available to export");
      return;
    }

    try {
      String csvData = "Full Name,Email,Gender,Phone,Status,Joined Date\n";
      for (var user in _users) {
        final String name =
            user['fullName']?.toString().replaceAll(',', ' ') ?? 'N/A';
        final String email = user['email'] ?? 'N/A';
        final String gender = user['gender'] ?? 'N/A';
        final String phone = user['phone'] ?? 'N/A';
        final String status = user['isVerified'] == true
            ? 'Verified'
            : 'Unverified';
        final String date = user['createdAt'] ?? 'N/A';

        csvData += "$name,$email,$gender,$phone,$status,$date\n";
      }

      final directory = await getTemporaryDirectory();
      final path =
          "${directory.path}/Keah_Clients_${DateTime.now().millisecondsSinceEpoch}.csv";
      final file = File(path);
      await file.writeAsString(csvData);

      await Share.shareXFiles([
        XFile(path),
      ], text: 'Keah Logistics Client Database Export');
    } catch (e) {
      _showSnackBar("Export failed: $e");
    }
  }

  void _filterUsers(String query) {
    setState(() {
      _filteredUsers = _users.where((user) {
        final name = (user['fullName'] ?? "").toString().toLowerCase();
        final email = (user['email'] ?? "").toString().toLowerCase();
        final searchQuery = query.toLowerCase();
        return name.contains(searchQuery) || email.contains(searchQuery);
      }).toList();
    });
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12)),
        backgroundColor: darkBlue,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // --- NAVIGATION FOOTER ---
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
            _footerItem(Icons.grid_view_rounded, "Dash", () {
              if (Navigator.canPop(context)) {
                Navigator.popUntil(context, (r) => r.isFirst);
              } else {
                Navigator.pushReplacementNamed(context, '/adminDashboard');
              }
            }),
            _footerItem(
              Icons.people_alt_rounded,
              "Users",
              () {},
              isActive: true,
            ),
            _footerItem(Icons.chat_bubble_outline_rounded, "Chat", () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (c) => const AdminLiveChatSystem()),
              );
            }),
            _footerItem(Icons.pedal_bike, "Riders", () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (c) => const RiderManagementScreen(),
                ),
              );
            }),
            _footerItem(Icons.segment_rounded, "Menu", _showMoreMenu),
          ],
        ),
      ),
    );
  }

  Widget _footerItem(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
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
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text(
                "Logout System",
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showDeleteDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: darkBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          "Confirm Delete",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Are you sure you want to remove this client? This action cannot be undone.",
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              "CANCEL",
              style: TextStyle(color: Colors.white38),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "DELETE",
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "CLIENT MANAGEMENT",
          style: TextStyle(
            color: goldYellow,
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: 1.2,
          ),
        ),
        backgroundColor: darkBlue,
        iconTheme: const IconThemeData(color: goldYellow),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined, color: goldYellow),
            onPressed: _exportToCSV,
            tooltip: "Export to CSV",
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _filterUsers,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: "Search by name or email...",
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                prefixIcon: const Icon(
                  Icons.search,
                  color: goldYellow,
                  size: 20,
                ),
                filled: true,
                fillColor: darkBlue,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchAllUsers,
              color: goldYellow,
              backgroundColor: darkBlue,
              child: _isLoading && _users.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: goldYellow),
                    )
                  : _filteredUsers.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 100),
                        Center(
                          child: Text(
                            "No clients found",
                            style: TextStyle(color: Colors.white24),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, index) =>
                          _buildUserTile(_filteredUsers[index]),
                    ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildStickyFooter(),
    );
  }

  Widget _buildUserTile(dynamic user) {
    final imgProvider = _getProfileImage(user['profileImage']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (c) => UserDetailScreen(user: user)),
          );
        },
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: goldYellow.withOpacity(0.1),
          backgroundImage: imgProvider,
          child: imgProvider == null
              ? Text(
                  user['fullName']?[0].toUpperCase() ?? 'U',
                  style: const TextStyle(
                    color: goldYellow,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        title: Text(
          user['fullName'] ?? "Unknown Client",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          "${user['email']}",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white38),
          color: darkBlue,
          onSelected: (val) {
            if (val == 'view') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (c) => UserDetailScreen(user: user)),
              );
            }
            if (val == 'delete') _deleteUser(user['_id']);
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view',
              child: Text(
                "View Profile",
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text(
                "Delete",
                style: TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UserDetailScreen extends StatelessWidget {
  final dynamic user;
  const UserDetailScreen({super.key, required this.user});

  ImageProvider? _getProfileImage(String? imageStr) {
    if (imageStr == null || imageStr.isEmpty) return null;
    if (imageStr.startsWith('http')) {
      return CachedNetworkImageProvider(imageStr);
    }
    try {
      String clean = imageStr.contains(',') ? imageStr.split(',')[1] : imageStr;
      return MemoryImage(base64Decode(clean));
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final address = user['address'] ?? {};
    final imgProvider = _getProfileImage(user['profileImage']);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "CLIENT PROFILE",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        backgroundColor: darkBlue,
        foregroundColor: goldYellow,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: goldYellow,
                    child: CircleAvatar(
                      radius: 57,
                      backgroundColor: darkBlue,
                      backgroundImage: imgProvider,
                      child: imgProvider == null
                          ? const Icon(
                              Icons.person,
                              size: 60,
                              color: goldYellow,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    user['fullName'] ?? "N/A",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    "REGISTERED CLIENT",
                    style: TextStyle(
                      color: goldYellow,
                      fontSize: 10,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            _buildSectionTitle("CONTACT INFORMATION"),
            _detailRow(Icons.email, "Email Address", user['email']),
            _detailRow(Icons.phone, "Phone Number", user['phone']),
            _detailRow(Icons.wc, "Gender", user['gender']),
            _detailRow(Icons.work, "Occupation", user['occupation']),
            const SizedBox(height: 20),
            _buildSectionTitle("ADDRESS"),
            _detailRow(Icons.location_on, "Street", address['street']),
            _detailRow(Icons.location_city, "City", address['city']),
            _detailRow(Icons.map, "State/Province", address['state']),
            const SizedBox(height: 20),
            _buildSectionTitle("ACCOUNT DETAILS"),
            _detailRow(Icons.badge, "Internal ID", user['_id']),
            _detailRow(
              Icons.calendar_month,
              "Registration Date",
              user['createdAt'],
            ),
            _detailRow(
              Icons.verified,
              "Verification Status",
              user['isVerified'] == true ? "Verified" : "Pending",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 10),
        child: Text(
          title,
          style: const TextStyle(
            color: goldYellow,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, dynamic value) {
    return Container(
      padding: const EdgeInsets.all(15),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white38),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
                const SizedBox(height: 2),
                Text(
                  value?.toString() ?? "Not Provided",
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
