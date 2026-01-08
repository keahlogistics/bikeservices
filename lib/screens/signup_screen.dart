import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:keah_logistics/screens/verifyOtp_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _workController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Address Controllers
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _countryController = TextEditingController(
    text: "Nigeria",
  );

  String? _selectedGender;
  final List<String> _genderOptions = ["Male", "Female"];

  File? _image;
  final ImagePicker _picker = ImagePicker();
  bool _isPasswordHidden = true;
  bool _isLoading = false;

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 40, // Reduced quality for faster Netlify upload
    );
    if (pickedFile != null) {
      setState(() => _image = File(pickedFile.path));
    }
  }

  void _showImageSourceActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E3C72),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text(
                'Gallery',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                _pickImage(ImageSource.gallery);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: Colors.white),
              title: const Text(
                'Camera',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                _pickImage(ImageSource.camera);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSignup() async {
    // Basic Validation
    if (_emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _nameController.text.isEmpty ||
        _selectedGender == null) {
      _showSnackBar(
        "Please fill in all required fields (Name, Email, Password, Gender)",
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? base64Image;
      if (_image != null) {
        final bytes = await _image!.readAsBytes();
        base64Image = "data:image/jpeg;base64,${base64Encode(bytes)}";
      }

      final Map<String, dynamic> userData = {
        "fullName": _nameController.text.trim(),
        "email": _emailController.text.trim().toLowerCase(),
        "phone": _phoneController.text.trim(),
        "gender": _selectedGender,
        "dob": _dobController.text.trim(),
        "occupation": _workController.text.trim(),
        "password": _passwordController.text,
        "profileImage": base64Image,
        "role": "user", // Default role for signup
        "address": {
          "street": _streetController.text.trim(),
          "city": _cityController.text.trim(),
          "state": _stateController.text.trim(),
          "country": _countryController.text.trim(),
        },
      };

      // Note: Using your Netlify Function endpoint
      final url = Uri.parse(
        'https://keahlogistics.netlify.app/.netlify/functions/api/signup',
      );

      final response = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode(userData),
          )
          .timeout(const Duration(seconds: 45));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return;
        _showSnackBar("Verification code sent to your email!", isError: false);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VerificationScreen(
              email: userData["email"],
              serverOtp: data['otpCode']?.toString() ?? "",
              userData: userData,
            ),
          ),
        );
      } else {
        _showSnackBar(data['error'] ?? "Signup failed. Please try again.");
      }
    } catch (e) {
      _showSnackBar("Connection error or timeout. Please check your internet.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "Create Account",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1E3C72), Color(0xFF2A5298)],
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 100, 20, 40),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        _buildImagePicker(),
                        const SizedBox(height: 25),
                        _buildTextField(
                          "Full Name",
                          Icons.person_outline,
                          _nameController,
                        ),
                        _buildGenderDropdown(),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(left: 5, bottom: 10),
                            child: Text(
                              "Home Address",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        _buildTextField(
                          "Street Address",
                          Icons.home_outlined,
                          _streetController,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                "City",
                                Icons.location_city,
                                _cityController,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildTextField(
                                "State",
                                Icons.map_outlined,
                                _stateController,
                              ),
                            ),
                          ],
                        ),
                        _buildTextField(
                          "Country",
                          Icons.public,
                          _countryController,
                        ),
                        const Divider(color: Colors.white24, height: 30),
                        _buildTextField(
                          "Email",
                          Icons.email_outlined,
                          _emailController,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        _buildTextField(
                          "Phone Number",
                          Icons.phone_android_outlined,
                          _phoneController,
                          keyboardType: TextInputType.phone,
                        ),
                        _buildTextField(
                          "Date of Birth",
                          Icons.cake_outlined,
                          _dobController,
                          hint: "DD/MM/YYYY",
                        ),
                        _buildTextField(
                          "Occupation",
                          Icons.work_outline,
                          _workController,
                        ),
                        _buildTextField(
                          "Password",
                          Icons.lock_outline,
                          _passwordController,
                          obscure: _isPasswordHidden,
                          isPasswordField: true,
                          onToggle: () => setState(
                            () => _isPasswordHidden = !_isPasswordHidden,
                          ),
                        ),
                        const SizedBox(height: 25),
                        _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : _buildSignupButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: () => _showImageSourceActionSheet(context),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.white24,
            backgroundImage: _image != null ? FileImage(_image!) : null,
            child: _image == null
                ? const Icon(Icons.camera_alt, color: Colors.white, size: 30)
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.amber,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, size: 20, color: Color(0xFF1E3C72)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignupButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E3C72),
        minimumSize: const Size(double.infinity, 55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        elevation: 5,
      ),
      onPressed: _handleSignup,
      child: const Text(
        "CREATE ACCOUNT",
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _buildGenderDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: DropdownButtonFormField<String>(
        initialValue: _selectedGender,
        dropdownColor: const Color(0xFF2A5298),
        style: const TextStyle(color: Colors.white),
        decoration: _inputDecoration("Gender", Icons.people_outline),
        items: _genderOptions
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: (val) => setState(() => _selectedGender = val),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    IconData icon,
    TextEditingController controller, {
    bool obscure = false,
    TextInputType? keyboardType,
    String? hint,
    bool isPasswordField = false,
    VoidCallback? onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: _inputDecoration(label, icon, hint: hint).copyWith(
          suffixIcon: isPasswordField
              ? IconButton(
                  icon: Icon(
                    obscure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white70,
                  ),
                  onPressed: onToggle,
                )
              : null,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label,
    IconData icon, {
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 14),
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
      prefixIcon: Icon(icon, color: Colors.white70, size: 20),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Colors.white),
      ),
    );
  }
}
