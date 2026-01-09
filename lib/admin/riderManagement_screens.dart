import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

// --- PROJECT IMPORTS ---
import 'rider_registration_screens.dart';
import 'userManagement_screens.dart';
import 'liveChatOrder_screens.dart';
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
      debugPrint("Error fetching riders: $e");
      if (mounted) setState(() => _isLoading = false);
    }
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
    bool isPending = rider['status'] == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isPending ? goldYellow.withOpacity(0.3) : Colors.white10,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: navyDark,
          child: ClipOval(
            child: CachedNetworkImage(
              imageUrl: rider['profileImage'] ?? "",
              fit: BoxFit.cover,
              width: 50,
              height: 50,
              errorWidget: (context, url, error) =>
                  const Icon(Icons.motorcycle, color: goldYellow),
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                rider['fullName'] ?? "Unnamed Rider",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (isPending)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  "NEW",
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          "${rider['rideType'] ?? 'Rider'} • ${rider['plateNumber'] ?? 'No Plate'}",
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
}

class RiderDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> rider;
  const RiderDetailsScreen({super.key, required this.rider});

  @override
  State<RiderDetailsScreen> createState() => _RiderDetailsScreenState();
}

class _RiderDetailsScreenState extends State<RiderDetailsScreen> {
  late TextEditingController _nameController,
      _phoneController,
      _emailController,
      _dobController,
      _addressController;
  late TextEditingController _licenseController,
      _plateController,
      _bikeColorController,
      _ninController,
      _gNameController,
      _gPhoneController;

  String _selectedRiderType = "Motorbike";
  File? _newImageFile;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.rider['fullName']);
    _phoneController = TextEditingController(text: widget.rider['phone']);
    _emailController = TextEditingController(text: widget.rider['email']);
    _dobController = TextEditingController(text: widget.rider['dob']);

    // FIXED: Properly initialized address controller
    _addressController = TextEditingController(
      text: widget.rider['address']?.toString() ?? "",
    );

    _licenseController = TextEditingController(
      text: widget.rider['licenseNumber'],
    );
    _plateController = TextEditingController(text: widget.rider['plateNumber']);
    _bikeColorController = TextEditingController(
      text: widget.rider['bikeColor'],
    );
    _ninController = TextEditingController(text: widget.rider['nin']);
    _gNameController = TextEditingController(
      text: widget.rider['guarantorName'],
    );
    _gPhoneController = TextEditingController(
      text: widget.rider['guarantorPhone'],
    );

    _selectedRiderType = widget.rider['rideType'] ?? "Motorbike";
  }

  Future<void> _updateStatus(bool approve) async {
    setState(() => _isUpdating = true);
    try {
      final response = await http.put(
        Uri.parse(
          'https://keahlogistics.netlify.app/.netlify/functions/api/admin/verify-rider/${widget.rider['_id']}',
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "isVerified": approve,
          "status": approve ? "active" : "suspended",
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve ? "Rider Agent Approved!" : "Rider Application Declined",
            ),
            backgroundColor: approve ? Colors.green : Colors.red,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Status update error: $e");
    } finally {
      if (mounted) setState(() => _isUpdating = false);
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
        "address": _addressController.text,
        "licenseNumber": _licenseController.text,
        "plateNumber": _plateController.text,
        "rideType": _selectedRiderType,
        "bikeColor": _bikeColorController.text,
        "nin": _ninController.text,
        "guarantorName": _gNameController.text,
        "guarantorPhone": _gPhoneController.text,
      };

      if (_newImageFile != null) {
        final bytes = await _newImageFile!.readAsBytes();
        body["riderImage"] = "data:image/jpeg;base64,${base64Encode(bytes)}";
      }

      final response = await http.put(
        Uri.parse(
          'https://keahlogistics.netlify.app/.netlify/functions/api/update-rider/${widget.rider['_id']}',
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Profile updated!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Update error: $e");
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color goldYellow = Color(0xFFFFD700);
    const Color navyDark = Color(0xFF0D1B2A);
    bool isPending = widget.rider['status'] == 'pending';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          isPending ? "REVIEW APPLICATION" : "EDIT RIDER PROFILE",
          style: const TextStyle(
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

            if (isPending) ...[
              _sectionLabel("VERIFICATION MEDIA"),
              _buildDocPreview(
                "Bike Front View",
                widget.rider['bikeFrontImage'],
              ),
              _buildDocPreview("Bike Back View", widget.rider['bikeBackImage']),
              _buildDocPreview(
                "Utility Bill",
                widget.rider['utilityBillImage'],
              ),
              _buildDocPreview(
                "Video Verification",
                widget.rider['videoVerification'],
                isVideo: true,
              ),
              const Divider(color: Colors.white10, height: 40),
            ],

            _sectionLabel("PERSONAL INFORMATION"),
            _buildField("Full Name", _nameController, Icons.person),
            _buildField("Phone Number", _phoneController, Icons.phone),
            // FIXED: Using initialized address controller
            _buildField("Home Address", _addressController, Icons.location_on),
            _buildField("NIN (National ID)", _ninController, Icons.fingerprint),

            _sectionLabel("VEHICLE DETAILS"),
            _buildRiderTypeDropdown(),
            _buildField("Plate Number", _plateController, Icons.numbers),
            _buildField(
              "License Number",
              _licenseController,
              Icons.badge_outlined,
            ),

            _sectionLabel("GUARANTOR DETAILS"),
            _buildField("Guarantor Name", _gNameController, Icons.security),
            _buildField(
              "Guarantor Phone",
              _gPhoneController,
              Icons.contact_phone,
            ),

            const SizedBox(height: 40),

            if (_isUpdating)
              const Center(child: CircularProgressIndicator(color: goldYellow))
            else if (isPending)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _updateStatus(false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        minimumSize: const Size(double.infinity, 55),
                      ),
                      child: const Text(
                        "DECLINE",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _updateStatus(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        minimumSize: const Size(double.infinity, 55),
                      ),
                      child: const Text(
                        "APPROVE",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              ElevatedButton(
                onPressed: _updateRider,
                style: ElevatedButton.styleFrom(
                  backgroundColor: goldYellow,
                  minimumSize: const Size(double.infinity, 60),
                ),
                child: const Text(
                  "SAVE CHANGES",
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildDocPreview(String label, String? url, {bool isVideo = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: url == null || url.isEmpty
              ? const Center(
                  child: Text(
                    "Not Uploaded",
                    style: TextStyle(color: Colors.white24),
                  ),
                )
              : isVideo
              ? const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    color: Colors.white,
                    size: 50,
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    errorWidget: (c, u, e) =>
                        const Icon(Icons.broken_image, color: Colors.white10),
                  ),
                ),
        ),
        const SizedBox(height: 15),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFFFFD700),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _buildProfileImagePicker(Color gold, Color navy) {
    return Center(
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CircleAvatar(
            radius: 55,
            backgroundColor: navy,
            backgroundImage: _newImageFile != null
                ? FileImage(_newImageFile!)
                : (widget.rider['profileImage'] != null
                          ? CachedNetworkImageProvider(
                              widget.rider['profileImage'],
                            )
                          : null)
                      as ImageProvider?,
            child:
                (_newImageFile == null && widget.rider['profileImage'] == null)
                ? Icon(Icons.person, size: 50, color: gold)
                : null,
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor: gold,
            child: IconButton(
              onPressed: () async {
                final XFile? image = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 40,
                );
                if (image != null)
                  setState(() => _newImageFile = File(image.path));
              },
              icon: const Icon(Icons.camera_alt, size: 18, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiderTypeDropdown() {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: DropdownButtonFormField<String>(
        value: _selectedRiderType,
        dropdownColor: const Color(0xFF0D1B2A),
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: const InputDecoration(
          labelText: "Vehicle Type",
          labelStyle: TextStyle(color: Colors.white38, fontSize: 13),
          border: InputBorder.none,
          prefixIcon: Icon(
            Icons.delivery_dining,
            color: Color(0xFFFFD700),
            size: 20,
          ),
        ),
        items: [
          "Motorbike",
          "Bicycle",
          "Van",
          "Car",
        ].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
        onChanged: (value) => setState(() => _selectedRiderType = value!),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool isPass = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: controller,
        obscureText: isPass,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
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
