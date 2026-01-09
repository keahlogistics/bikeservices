import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:keah_logistics/client/order_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  static const Color goldYellow = Color(0xFFFFD700);
  static const Color darkBlue = Color(0xFF0D1B2A);

  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _obscurePassword = true;
  final int _currentIndex = 4;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String? _selectedGender;
  final List<String> _genderOptions = [
    'Male',
    'Female',
    'Other',
    'Prefer not to say',
  ];

  String? userImage;
  File? _selectedImageFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  // --- UPDATED SECURE FETCH METHOD ---
  Future<void> _fetchUserProfile() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString('userEmail');
    final String? token = prefs.getString('token'); // Retrieve the JWT Token

    if (email == null || token == null) {
      if (mounted) {
        _showError("Session expired. Please log in again.");
        _logout();
      }
      return;
    }

    try {
      final url = Uri.parse(
        'https://keahlogistics.netlify.app/.netlify/functions/api/user',
      ).replace(queryParameters: {'email': email.trim().toLowerCase()});

      // Added Authorization Header
      final response = await http
          .get(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _nameController.text = data['fullName'] ?? "";
            _emailController.text = data['email'] ?? "";
            _phoneController.text = data['phone'] ?? "";
            _dobController.text = data['dob'] ?? "";
            _occupationController.text = data['occupation'] ?? "";

            String? fetchedGender = data['gender'];
            _selectedGender = _genderOptions.contains(fetchedGender)
                ? fetchedGender
                : null;

            if (data['address'] != null) {
              _streetController.text = data['address']['street'] ?? "";
              _cityController.text = data['address']['city'] ?? "";
              _stateController.text = data['address']['state'] ?? "";
            }
            userImage = data['profileImage'];
            _isLoading = false;
          });
        }
      } else if (response.statusCode == 401) {
        _showError("Unauthorized. Please log in again.");
        _logout();
      } else {
        _showError("Profile not found.");
        setState(() => _isLoading = false);
      }
    } catch (e) {
      _showError("Connection error. Using cached data.");
      // Load local cache if network fails
      setState(() {
        _nameController.text = prefs.getString('userName') ?? "";
        userImage = prefs.getString('userImage');
        _isLoading = false;
      });
    }
  }

  // --- UPDATED SECURE UPDATE METHOD ---
  Future<void> _updateProfile() async {
    setState(() => _isSaving = true);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString('token');

    String? base64Image;
    if (_selectedImageFile != null) {
      List<int> imageBytes = await _selectedImageFile!.readAsBytes();
      base64Image = base64Encode(imageBytes);
    }

    try {
      final response = await http.put(
        Uri.parse(
          'https://keahlogistics.netlify.app/.netlify/functions/api/update-profile',
        ),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token", // Secure update
        },
        body: jsonEncode({
          "email": _emailController.text.trim(),
          "fullName": _nameController.text,
          "phone": _phoneController.text,
          "dob": _dobController.text,
          "gender": _selectedGender,
          "occupation": _occupationController.text,
          "address": {
            "street": _streetController.text,
            "city": _cityController.text,
            "state": _stateController.text,
          },
          "profileImage": base64Image ?? userImage,
          if (_passwordController.text.isNotEmpty)
            "password": _passwordController.text,
        }),
      );

      if (response.statusCode == 200) {
        if (base64Image != null) {
          userImage = base64Image;
          await prefs.setString('userImage', base64Image);
        }
        await prefs.setString('userName', _nameController.text);
        setState(() => _isEditing = false);
        _passwordController.clear();
        _showSuccess("Profile updated successfully!");
      } else {
        _showError("Update failed. Check your connection.");
      }
    } catch (e) {
      _showError("Failed to update profile.");
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _logout() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
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
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const OrderScreen()),
        );
        break;
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: goldYellow),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "MY PROFILE",
          style: TextStyle(
            color: goldYellow,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isEditing ? Icons.close : Icons.edit,
              color: goldYellow,
            ),
            onPressed: () => setState(() {
              _isEditing = !_isEditing;
              if (!_isEditing) _fetchUserProfile();
            }),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: goldYellow))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Column(
                children: [
                  _buildProfileHeader(),
                  const SizedBox(height: 30),
                  _buildField(
                    "Full Name",
                    _nameController,
                    Icons.person_outline,
                  ),
                  _buildField(
                    "Email Address",
                    _emailController,
                    Icons.email_outlined,
                    enabled: false,
                  ),
                  _buildField(
                    "Phone Number",
                    _phoneController,
                    Icons.phone_android_outlined,
                  ),
                  _buildGenderDropdown(),
                  _buildDatePickerField(
                    "Date of Birth",
                    _dobController,
                    Icons.calendar_today_outlined,
                  ),
                  _buildField(
                    "Occupation",
                    _occupationController,
                    Icons.work_outline,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "ADDRESS DETAILS",
                        style: TextStyle(
                          color: goldYellow,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                  _buildField("Street", _streetController, Icons.map_outlined),
                  Row(
                    children: [
                      Expanded(
                        child: _buildField(
                          "City",
                          _cityController,
                          Icons.location_city_outlined,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildField(
                          "State",
                          _stateController,
                          Icons.explore_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_isEditing) ...[
                    _buildPasswordField(),
                    const SizedBox(height: 30),
                    _buildSaveButton(),
                  ] else ...[
                    _buildLogoutButton(),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // --- UI COMPONENTS ---

  Widget _buildProfileHeader() {
    return Center(
      child: Stack(
        children: [
          CircleAvatar(
            radius: 62,
            backgroundColor: goldYellow,
            child: CircleAvatar(
              radius: 60,
              backgroundColor: darkBlue,
              backgroundImage: _getProfileImage(),
              child: _getProfileImage() == null
                  ? const Icon(Icons.person, size: 60, color: goldYellow)
                  : null,
            ),
          ),
          if (_isEditing)
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: _pickImage,
                child: const CircleAvatar(
                  backgroundColor: goldYellow,
                  radius: 18,
                  child: Icon(Icons.camera_alt, size: 18, color: darkBlue),
                ),
              ),
            ),
        ],
      ),
    );
  }

  ImageProvider? _getProfileImage() {
    if (_selectedImageFile != null) return FileImage(_selectedImageFile!);
    if (userImage == null || userImage!.isEmpty) return null;
    try {
      String clean = userImage!.contains(',')
          ? userImage!.split(',')[1]
          : userImage!;
      return MemoryImage(base64Decode(clean));
    } catch (e) {
      return null;
    }
  }

  Future<void> _pickImage() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 40,
    );
    if (picked != null) setState(() => _selectedImageFile = File(picked.path));
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: controller,
        enabled: _isEditing && enabled,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
          prefixIcon: Icon(icon, color: goldYellow, size: 20),
          disabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: goldYellow.withOpacity(0.3)),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: goldYellow),
          ),
        ),
      ),
    );
  }

  Widget _buildGenderDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<String>(
        // This value must match exactly one of the items in 'items' or be null
        initialValue: _genderOptions.contains(_selectedGender)
            ? _selectedGender
            : null,
        dropdownColor: darkBlue,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: "Gender",
          labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
          prefixIcon: const Icon(Icons.wc, color: goldYellow, size: 20),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: _isEditing
                  ? goldYellow.withOpacity(0.3)
                  : Colors.white.withOpacity(0.05),
            ),
          ),
        ),
        // Ensure the items are built from the same list used for the value
        items: _genderOptions.map((String value) {
          return DropdownMenuItem<String>(value: value, child: Text(value));
        }).toList(),
        onChanged: _isEditing
            ? (newValue) {
                setState(() {
                  _selectedGender = newValue;
                });
              }
            : null, // Disables the dropdown when not editing
      ),
    );
  }

  Widget _buildDatePickerField(
    String label,
    TextEditingController controller,
    IconData icon,
  ) {
    return GestureDetector(
      onTap: _isEditing
          ? () async {
              DateTime? picked = await showDatePicker(
                context: context,
                initialDate: DateTime(2000),
                firstDate: DateTime(1940),
                lastDate: DateTime.now(),
                builder: (context, child) => Theme(
                  data: ThemeData.dark().copyWith(
                    colorScheme: const ColorScheme.dark(primary: goldYellow),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                setState(
                  () =>
                      controller.text = DateFormat('yyyy-MM-dd').format(picked),
                );
              }
            }
          : null,
      child: AbsorbPointer(child: _buildField(label, controller, icon)),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: "Security: New Password",
        labelStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
        prefixIcon: const Icon(Icons.lock_reset, color: Colors.redAccent),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: Colors.white24,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: goldYellow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        onPressed: _isSaving ? null : _updateProfile,
        child: _isSaving
            ? const CircularProgressIndicator(color: darkBlue)
            : const Text(
                "SAVE CHANGES",
                style: TextStyle(color: darkBlue, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.redAccent),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: _logout,
        icon: const Icon(Icons.logout, color: Colors.redAccent),
        label: const Text(
          "LOG OUT",
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: darkBlue,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        backgroundColor: darkBlue,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: goldYellow,
        unselectedItemColor: Colors.white38,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Home"),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_box_outlined),
            label: "Send",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: "Track",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            label: "Orders",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: "Settings",
          ),
        ],
      ),
    );
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ),
  );
  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
