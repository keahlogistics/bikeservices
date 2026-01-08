import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- PROJECT IMPORTS ---
import 'rider_registration_screens.dart';
import 'userManagement_screens.dart'; // Ensure this matches your file name
import 'liveChatOrder_screens.dart'; // Ensure this matches your file name
import '../screens/adminLogin_screens.dart';

class RiderManagementScreen extends StatefulWidget {
  const RiderManagementScreen({super.key});

  @override
  State<RiderManagementScreen> createState() => _RiderManagementScreenState();
}

class _RiderManagementScreenState extends State<RiderManagementScreen> {
  static const Color goldYellow = Color(0xFFFFD700);
  static const Color navyDark = Color(0xFF0D1B2A);

  List<dynamic> _riders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRiders();
  }

  Future<void> _fetchRiders() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final response = await http.get(
        Uri.parse(
          'https://keahlogistics.netlify.app/.netlify/functions/api/admin/riders',
        ),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _riders = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- STICKY FOOTER COMPONENTS ---
  Widget _buildStickyFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        color: navyDark,
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _footerItem(
              Icons.grid_view_rounded,
              "Dash",
              () => Navigator.popUntil(context, (r) => r.isFirst),
            ),
            _footerItem(Icons.people_alt_rounded, "Users", () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (c) => const UserManagementScreen()),
              );
            }),
            _footerItem(Icons.chat_bubble_outline_rounded, "Chat", () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (c) => const AdminLiveChatSystem()),
              );
            }),
            _footerItem(Icons.pedal_bike, "Riders", () {}, isActive: true),
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
      backgroundColor: navyDark,
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
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (c) => const AdminLoginScreen()),
                  (r) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "RIDER AGENT MANAGEMENT",
          style: TextStyle(
            color: goldYellow,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        backgroundColor: navyDark,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _fetchRiders,
            icon: const Icon(Icons.refresh, color: goldYellow),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RiderRegistrationScreen(),
                  ),
                ).then((_) => _fetchRiders());
              },
              icon: const Icon(Icons.person_add_alt_1, color: Colors.black),
              label: const Text("REGISTER NEW RIDER AGENT"),
              style: ElevatedButton.styleFrom(
                backgroundColor: goldYellow,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: goldYellow),
                  )
                : _riders.isEmpty
                ? const Center(
                    child: Text(
                      "No riders found.",
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: _riders.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) =>
                        _buildRiderCard(_riders[index]),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _buildStickyFooter(),
    );
  }

  Widget _buildRiderCard(Map<String, dynamic> rider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: navyDark,
          backgroundImage:
              (rider['profileImage'] != null &&
                  rider['profileImage'].isNotEmpty)
              ? MemoryImage(base64Decode(rider['profileImage']))
              : null,
          child:
              (rider['profileImage'] == null || rider['profileImage'].isEmpty)
              ? const Icon(Icons.motorcycle, color: goldYellow)
              : null,
        ),
        title: Text(
          rider['fullName'] ?? "Unnamed Rider",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          rider['email'] ?? "",
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: goldYellow,
          size: 16,
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RiderDetailsScreen(rider: rider),
            ),
          ).then((_) => _fetchRiders());
        },
      ),
    );
  }
}

// --- FULL SCREEN: RIDER DETAILS & EDITING ---
class RiderDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> rider;
  const RiderDetailsScreen({super.key, required this.rider});

  @override
  State<RiderDetailsScreen> createState() => _RiderDetailsScreenState();
}

class _RiderDetailsScreenState extends State<RiderDetailsScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _dobController;
  late TextEditingController _occupationController;
  late TextEditingController _addressController;
  late TextEditingController _passwordController;

  String? _profileImageBase64;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.rider['fullName']);
    _phoneController = TextEditingController(text: widget.rider['phone']);
    _emailController = TextEditingController(text: widget.rider['email']);
    _dobController = TextEditingController(text: widget.rider['dob']);
    _occupationController = TextEditingController(
      text: widget.rider['occupation'],
    );
    _addressController = TextEditingController(text: widget.rider['address']);
    _passwordController = TextEditingController();
    _profileImageBase64 = widget.rider['profileImage'];
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );
    if (image != null) {
      final bytes = await File(image.path).readAsBytes();
      setState(() => _profileImageBase64 = base64Encode(bytes));
    }
  }

  Future<void> _updateRider() async {
    setState(() => _isUpdating = true);
    try {
      Map<String, dynamic> body = {
        "fullName": _nameController.text,
        "phone": _phoneController.text,
        "email": _emailController.text,
        "dob": _dobController.text,
        "occupation": _occupationController.text,
        "address": _addressController.text,
        "profileImage": _profileImageBase64,
      };

      if (_passwordController.text.isNotEmpty) {
        body["password"] = _passwordController.text;
      }

      final response = await http.put(
        Uri.parse(
          'https://keahlogistics.netlify.app/.netlify/functions/api/update-rider/${widget.rider['_id']}',
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Rider updated successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Update failed"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color goldYellow = Color(0xFFFFD700);
    const Color navyDark = Color(0xFF0D1B2A);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "EDIT RIDER AGENT",
          style: TextStyle(
            color: goldYellow,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: navyDark,
        iconTheme: const IconThemeData(color: goldYellow),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildProfileImagePicker(goldYellow, navyDark),
            const SizedBox(height: 30),
            _sectionLabel("ACCOUNT ACCESS"),
            _buildField("Full Name", _nameController, Icons.person),
            _buildField("Email Address", _emailController, Icons.email),
            _buildField("Phone Number", _phoneController, Icons.phone),
            const SizedBox(height: 20),
            _sectionLabel("PERSONAL INFORMATION"),
            _buildField("Date of Birth", _dobController, Icons.calendar_month),
            _buildField("Occupation", _occupationController, Icons.work),
            _buildField(
              "Address",
              _addressController,
              Icons.location_on,
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            _sectionLabel("SECURITY"),
            _buildField(
              "New Password",
              _passwordController,
              Icons.lock_outline,
              isPass: true,
              hint: "Leave blank to keep current",
            ),
            const SizedBox(height: 40),
            _isUpdating
                ? const CircularProgressIndicator(color: goldYellow)
                : ElevatedButton(
                    onPressed: _updateRider,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: goldYellow,
                      minimumSize: const Size(double.infinity, 60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text(
                      "UPDATE PROFILE",
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFFFFD700),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildProfileImagePicker(Color gold, Color navy) {
    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CircleAvatar(
            radius: 55,
            backgroundColor: navy,
            backgroundImage:
                (_profileImageBase64 != null && _profileImageBase64!.isNotEmpty)
                ? MemoryImage(base64Decode(_profileImageBase64!))
                : null,
            child: (_profileImageBase64 == null || _profileImageBase64!.isEmpty)
                ? Icon(Icons.person, size: 50, color: gold)
                : null,
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor: gold,
            child: const Icon(Icons.camera_alt, size: 18, color: Colors.black),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool isPass = false,
    String? hint,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: controller,
        obscureText: isPass,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
          labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          prefixIcon: Icon(icon, color: const Color(0xFFFFD700), size: 20),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white10),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFFD700)),
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
        ),
      ),
    );
  }
}
