import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AdminSignupScreen extends StatefulWidget {
  const AdminSignupScreen({super.key});

  @override
  State<AdminSignupScreen> createState() => _AdminSignupScreenState();
}

class _AdminSignupScreenState extends State<AdminSignupScreen> {
  // --- CONTROLLERS ---
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _adminKeyController = TextEditingController();

  // --- STYLE CONSTANTS ---
  static const Color goldYellow = Color(0xFFFFD700);
  static const Color darkBlue = Color(0xFF1A3A5F);

  // --- STATE ---
  bool _isPasswordHidden = true;
  bool _isAdminKeyHidden = true;
  bool _isLoading = false;

  Future<void> _handleAdminSignup() async {
    // 1. Validation
    if (_nameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _adminKeyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("All fields including Secret Key are required"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final url = Uri.parse(
        'https://keahlogistics.netlify.app/.netlify/functions/api/admin-signup',
      );

      // 2. Network Request
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "fullName": _nameController.text.trim(),
          "email": _emailController.text.trim(),
          "password": _passwordController.text,
          "adminSecretKey": _adminKeyController.text.trim(), // Verification Key
        }),
      );

      final data = jsonDecode(response.body);

      // 3. Response Handling
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Master Admin Created Successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else if (response.statusCode == 403) {
        // Handle the backend "Only One Admin Allowed" rule
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['error'] ?? "A Master Admin is already registered.",
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['error'] ?? "Signup failed"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Connection error. Check your internet or Netlify URL.",
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: goldYellow,
        title: const Text(
          "Master Admin Registration",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.black, Color(0xFF0D1B2A)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Column(
              children: [
                const SizedBox(height: 40),
                const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: goldYellow,
                  size: 70,
                ),
                const SizedBox(height: 20),

                // GLASSMORPHISM FORM
                ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          _buildField(
                            controller: _nameController,
                            hint: "Full Name",
                            icon: Icons.person_outline,
                          ),
                          const SizedBox(height: 15),
                          _buildField(
                            controller: _emailController,
                            hint: "Admin Email",
                            icon: Icons.email_outlined,
                            type: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 15),

                          // PASSWORD FIELD
                          _buildField(
                            controller: _passwordController,
                            hint: "Password",
                            icon: Icons.lock_outline,
                            isSecure: true,
                            obscure: _isPasswordHidden,
                            onToggle: () => setState(
                              () => _isPasswordHidden = !_isPasswordHidden,
                            ),
                          ),
                          const SizedBox(height: 15),

                          // ADMIN SECRET KEY FIELD
                          _buildField(
                            controller: _adminKeyController,
                            hint: "Admin Secret Key",
                            icon: Icons.key_outlined,
                            isSecure: true,
                            obscure: _isAdminKeyHidden,
                            onToggle: () => setState(
                              () => _isAdminKeyHidden = !_isAdminKeyHidden,
                            ),
                          ),

                          const SizedBox(height: 30),

                          _isLoading
                              ? const CircularProgressIndicator(
                                  color: goldYellow,
                                )
                              : ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: goldYellow,
                                    foregroundColor: darkBlue,
                                    minimumSize: const Size(
                                      double.infinity,
                                      60,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  ),
                                  onPressed: _handleAdminSignup,
                                  child: const Text(
                                    "REGISTER MASTER ADMIN",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- REUSABLE FIELD WIDGET ---
  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isSecure = false,
    bool obscure = false,
    VoidCallback? onToggle,
    TextInputType? type,
  }) {
    return TextField(
      controller: controller,
      obscureText: isSecure ? obscure : false,
      keyboardType: type,
      style: const TextStyle(color: Colors.white),
      cursorColor: goldYellow,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: goldYellow, size: 20),
        suffixIcon: isSecure
            ? IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: goldYellow.withOpacity(0.7),
                  size: 20,
                ),
                onPressed: onToggle,
              )
            : null,
        filled: true,
        fillColor: Colors.black38,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: goldYellow, width: 1),
        ),
      ),
    );
  }
}
