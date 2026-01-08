import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// --- PROJECT IMPORTS ---
import 'adminSignup_screens.dart';
import '../admin/adminDashboard_screens.dart';
import 'login_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  static const Color goldYellow = Color(0xFFFFD700);
  static const Color darkBlue = Color(0xFF1A3A5F);

  bool _isPasswordHidden = true;
  bool _isLoading = false;

  // --- RECTIFIED SESSION PERSISTENCE ---
  Future<void> _saveAdminSession(
    Map<String, dynamic> userData,
    String token,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    // Set persistence flags
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('userRole', 'admin');

    // Unified Token Keys (Fixed to match main.dart expectations)
    await prefs.setString('userToken', token);
    await prefs.setString('adminToken', token);

    // Sync Email Keys for OneSignal and Profile checks
    await prefs.setString('userEmail', userData['email'] ?? '');
    await prefs.setString('adminEmail', userData['email'] ?? '');
    await prefs.setString('adminName', userData['fullName'] ?? '');

    await prefs.setString(
      'userId',
      userData['id']?.toString() ?? userData['_id']?.toString() ?? '',
    );

    debugPrint("Admin Session Saved Successfully.");
  }

  Future<void> _handleAdminLogin() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showErrorSnackBar("Please enter your admin credentials");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http
          .post(
            Uri.parse(
              'https://keahlogistics.netlify.app/.netlify/functions/api/admin-login',
            ),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"email": email, "password": password}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final adminData = data['user'];
        final token = data['token'];

        if (token == null) throw Exception("No token received");

        // Save session data
        await _saveAdminSession(adminData, token);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Access Granted. Redirecting..."),
            backgroundColor: Colors.green,
          ),
        );

        // --- CRITICAL FIX: Small delay ensures SharedPrefs is written before Navigator clears the stack ---
        await Future.delayed(const Duration(milliseconds: 300));

        if (!mounted) return;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AdminDashboard()),
          (route) => false,
        );
      } else {
        _showErrorSnackBar(data['error'] ?? "Authentication Failed");
      }
    } catch (e) {
      debugPrint("Login Error: $e");
      if (mounted) _showErrorSnackBar("Connection error. Please try again.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.black, Color(0xFF0D1B2A)],
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                children: [
                  const Icon(
                    Icons.admin_panel_settings,
                    color: goldYellow,
                    size: 80,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "ADMIN PORTAL",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 40),
                  _buildFormCard(),
                  const SizedBox(height: 25),

                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AdminSignupScreen(),
                      ),
                    ),
                    child: const Text(
                      "Create Admin Account",
                      style: TextStyle(
                        color: goldYellow,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                  const Divider(
                    color: Colors.white10,
                    indent: 50,
                    endIndent: 50,
                  ),
                  const SizedBox(height: 10),

                  // --- REDIRECT TO LOGIN SCREEN ---
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                        (route) => false,
                      );
                    },
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white60,
                      size: 18,
                    ),
                    label: const Text(
                      "Return to User Login",
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              _buildAdminField(
                controller: _emailController,
                hint: "Admin Email",
                icon: Icons.alternate_email,
              ),
              const SizedBox(height: 15),
              _buildAdminField(
                controller: _passwordController,
                hint: "Security Password",
                icon: Icons.security,
                isPassword: true,
                obscureText: _isPasswordHidden,
                onToggle: () =>
                    setState(() => _isPasswordHidden = !_isPasswordHidden),
              ),
              const SizedBox(height: 30),
              _isLoading
                  ? const CircularProgressIndicator(color: goldYellow)
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: goldYellow,
                        foregroundColor: darkBlue,
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _handleAdminLogin,
                      child: const Text(
                        "ACCESS DASHBOARD",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword ? obscureText : false,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        prefixIcon: Icon(icon, color: goldYellow),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white30,
                ),
                onPressed: onToggle,
              )
            : null,
        filled: true,
        fillColor: Colors.black26,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: goldYellow),
        ),
      ),
    );
  }
}
