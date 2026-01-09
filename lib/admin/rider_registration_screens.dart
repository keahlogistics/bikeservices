import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/adminLogin_screens.dart';
import 'liveChatOrder_screens.dart';
import 'userManagement_screens.dart';

class RiderRegistrationScreen extends StatefulWidget {
  const RiderRegistrationScreen({super.key});

  @override
  State<RiderRegistrationScreen> createState() =>
      _RiderRegistrationScreenState();
}

class _RiderRegistrationScreenState extends State<RiderRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  // Basic Info Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController(
    text: "Rider Agent",
  );
  final TextEditingController _passwordController = TextEditingController();

  // Address Controllers
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();

  // Bike & License Controllers
  final TextEditingController _licenseController = TextEditingController();
  final TextEditingController _plateController = TextEditingController();
  final TextEditingController _bikeColorController = TextEditingController();
  String _riderType = "Motorbike";

  final TextEditingController _adminKeyController = TextEditingController();

  static const Color goldYellow = Color(0xFFFFD700);
  static const Color navyDark = Color(0xFF0D1B2A);

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureAdminKey = true;

  Future<void> _pickImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 40,
    );
    if (pickedFile != null) setState(() => _imageFile = File(pickedFile.path));
  }

  Future<void> _selectDate(BuildContext context) async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: goldYellow,
            onPrimary: Colors.black,
            surface: navyDark,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null)
      setState(
        () => _dobController.text = DateFormat('yyyy-MM-dd').format(picked),
      );
  }

  Future<void> _handleCreateRider() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a profile photo")),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final bytes = await _imageFile!.readAsBytes();
      String base64Image = "data:image/jpeg;base64,${base64Encode(bytes)}";

      final response = await http.post(
        Uri.parse(
          'https://keahlogistics.netlify.app/.netlify/functions/api/create-rider',
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "fullName": _nameController.text.trim(),
          "email": _emailController.text.trim(),
          "phone": _phoneController.text.trim(),
          "password": _passwordController.text.trim(),
          "adminSecretKey": _adminKeyController.text.trim(),
          "riderImage": base64Image,
          "address": {
            "street": _streetController.text.trim(),
            "city": _cityController.text.trim(),
            "state": _stateController.text.trim(),
            "country": "Nigeria",
          },
          "dob": _dobController.text,
          "occupation": _occupationController.text.trim(),
          "licenseNumber": _licenseController.text.trim(),
          "plateNumber": _plateController.text.trim(),
          "riderType": _riderType,
          "bikeColor": _bikeColorController.text.trim(),
        }),
      );

      if (response.statusCode == 201) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Rider Onboarded Successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error'] ?? "Registration failed")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Network error.")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "ONBOARD RIDER",
          style: TextStyle(
            color: goldYellow,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        backgroundColor: navyDark,
        iconTheme: const IconThemeData(color: goldYellow),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: const Color(0xFF1A3A5F),
                  backgroundImage: _imageFile != null
                      ? FileImage(_imageFile!)
                      : null,
                  child: _imageFile == null
                      ? const Icon(
                          Icons.add_a_photo,
                          color: goldYellow,
                          size: 35,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 25),
              _buildField(_nameController, "Full Name", Icons.person),
              _buildField(
                _emailController,
                "Email Contact",
                Icons.email,
                type: TextInputType.emailAddress,
              ),
              _buildField(
                _phoneController,
                "Phone Number",
                Icons.phone,
                type: TextInputType.phone,
              ),
              _buildField(
                _dobController,
                "Date of Birth",
                Icons.calendar_month,
                readOnly: true,
                onTap: () => _selectDate(context),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: Colors.white24),
              ),
              const Text(
                "BIKE & LICENSE INFO",
                style: TextStyle(
                  color: goldYellow,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 15),

              // --- FIXED DROPDOWN BLOCK ---
              Container(
                margin: const EdgeInsets.only(bottom: 15),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonFormField<String>(
                  value: _riderType,
                  dropdownColor: navyDark,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    // FIXED: Changed border: BorderSide.none to InputBorder.none
                    border: InputBorder.none,
                    prefixIcon: Icon(
                      Icons.category,
                      color: goldYellow,
                      size: 20,
                    ),
                    labelText: "Rider Type",
                    labelStyle: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  items: ["Motorbike", "Bicycle"].map((String type) {
                    return DropdownMenuItem(value: type, child: Text(type));
                  }).toList(),
                  onChanged: (val) => setState(() => _riderType = val!),
                ),
              ),

              _buildField(
                _licenseController,
                "Driver's License Number",
                Icons.badge,
              ),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      _plateController,
                      "Plate Number",
                      Icons.pin,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildField(
                      _bikeColorController,
                      "Bike Color",
                      Icons.palette,
                    ),
                  ),
                ],
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: Colors.white24),
              ),
              const Text(
                "ADDRESS DETAILS",
                style: TextStyle(
                  color: goldYellow,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 15),
              _buildField(_streetController, "Street Address", Icons.home),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      _cityController,
                      "City",
                      Icons.location_city,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildField(_stateController, "State", Icons.map),
                  ),
                ],
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(color: Colors.white24),
              ),
              _buildField(
                _passwordController,
                "Set Rider Password",
                Icons.lock_outline,
                isSecure: _obscurePassword,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: goldYellow,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const Divider(color: Colors.white24, height: 40),
              _buildField(
                _adminKeyController,
                "Master Admin Secret Key",
                Icons.security,
                isSecure: _obscureAdminKey,
                suffix: IconButton(
                  icon: Icon(
                    _obscureAdminKey ? Icons.visibility_off : Icons.visibility,
                    color: goldYellow,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscureAdminKey = !_obscureAdminKey),
                ),
              ),
              const SizedBox(height: 30),
              _isLoading
                  ? const CircularProgressIndicator(color: goldYellow)
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: goldYellow,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 60),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: _handleCreateRider,
                      child: const Text(
                        "REGISTER RIDER AGENT",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildStickyFooter(),
    );
  }

  // Footer methods and buildField...
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
            _footerItem(
              Icons.people_alt_rounded,
              "Users",
              () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (c) => const UserManagementScreen()),
              ),
            ),
            _footerItem(
              Icons.chat_bubble_outline_rounded,
              "Chat",
              () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (c) => const AdminLiveChatSystem()),
              ),
            ),
            _footerItem(
              Icons.pedal_bike,
              "Riders",
              () => Navigator.pop(context),
              isActive: true,
            ),
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
        child: ListTile(
          leading: const Icon(Icons.logout, color: Colors.redAccent),
          title: const Text(
            "Logout System",
            style: TextStyle(color: Colors.white),
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
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType type = TextInputType.text,
    bool isSecure = false,
    Widget? suffix,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        obscureText: isSecure,
        readOnly: readOnly,
        onTap: onTap,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
          prefixIcon: Icon(icon, color: goldYellow, size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: goldYellow),
          ),
        ),
        validator: (value) =>
            (value == null || value.isEmpty) ? "Required" : null,
      ),
    );
  }
}
