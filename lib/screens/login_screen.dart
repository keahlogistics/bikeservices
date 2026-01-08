import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Screens
import 'package:keah_logistics/screens/verifyOtp_screen.dart';
import 'package:keah_logistics/client/home_screen.dart';
import 'signup_screen.dart';
import 'adminLogin_screens.dart';
import '../riderAgent/riderDashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  static const Color goldYellow = Color(0xFFFFD700);
  static const Color darkBlue = Color(0xFF1A3A5F);

  bool _isPasswordHidden = true;
  bool _isLoading = false;
  bool _isRiderMode = false;
  bool _rememberMe = false; // Persistent Login State
  int _adminTapCount = 0;

  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _initPrefsAndLoadData();
  }

  // Initialize SharedPreferences and auto-fill if Remember Me was active
  Future<void> _initPrefsAndLoadData() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _rememberMe = _prefs.getBool('remember_me') ?? false;
      if (_rememberMe) {
        _emailController.text = _prefs.getString('saved_email') ?? '';
        _passwordController.text = _prefs.getString('saved_password') ?? '';
      }
    });
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar("Please enter both email and password", Colors.redAccent);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final String requiredRole = _isRiderMode ? 'rider' : 'user';
      final url = Uri.parse(
        'https://keahlogistics.netlify.app/.netlify/functions/api/login',
      );

      final response = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "email": email,
              "password": password,
              "requiredRole": requiredRole,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      // --- 1. HANDLE UNVERIFIED ACCOUNTS ---
      if (response.statusCode == 401 && data['notVerified'] == true) {
        if (!mounted) return;
        _showSnackBar("Account not verified. Redirecting...", Colors.orange);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VerificationScreen(
              email: email,
              serverOtp: data['otpCode'] ?? "",
              userData: data['user'] ?? {},
            ),
          ),
        );
        return;
      }

      // --- 2. HANDLE SUCCESSFUL LOGIN ---
      if (response.statusCode == 200) {
        final user = data['user'] ?? {};

        // Parallel save user session and JWT token
        await Future.wait([
          _prefs.setBool('isLoggedIn', true),
          _prefs.setString('token', data['token'] ?? ''),
          _prefs.setString('userEmail', email),
          _prefs.setString('userRole', user['role'] ?? ''),
          _prefs.setString('userName', user['fullName'] ?? 'User'),
          _prefs.setString('userId', user['id'] ?? ''),

          // Persistence for "Remember Me"
          _prefs.setBool('remember_me', _rememberMe),
          if (_rememberMe) ...[
            _prefs.setString('saved_email', email),
            _prefs.setString('saved_password', password),
          ] else ...[
            _prefs.remove('saved_email'),
            _prefs.remove('saved_password'),
          ],
        ]);

        if (!mounted) return;

        final String role = user['role'] ?? '';
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => role == 'rider'
                ? const RiderDashboardScreen()
                : const HomeScreen(),
          ),
          (route) => false,
        );
      } else {
        _showSnackBar(data['error'] ?? "Login failed", Colors.redAccent);
      }
    } catch (e) {
      _showSnackBar(
        "Connection error or timeout. Please try again.",
        Colors.orange,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
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
          _buildBrandingSection(),
          _buildGradientOverlay(),
          Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildRoleToggle(),
                  const SizedBox(height: 20),
                  _buildLoginForm(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandingSection() {
    return Positioned(
      top: 50,
      left: 0,
      right: 0,
      child: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.3,
            child: Lottie.asset(
              'assets/animations/delivery_man.json',
              fit: BoxFit.contain,
              repeat: true,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.delivery_dining,
                size: 100,
                color: goldYellow,
              ),
            ),
          ),
          const Text(
            "KEAH LOGISTICS",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: goldYellow,
              letterSpacing: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.8),
            Colors.black,
          ],
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              _buildAdminPortalTrigger(),
              const SizedBox(height: 25),
              _buildInputField(
                controller: _emailController,
                hint: "Email Address",
                icon: Icons.email_outlined,
              ),
              const SizedBox(height: 15),
              _buildInputField(
                controller: _passwordController,
                hint: "Password",
                icon: Icons.lock_outline,
                isPassword: true,
                obscureText: _isPasswordHidden,
                onToggleVisibility: () =>
                    setState(() => _isPasswordHidden = !_isPasswordHidden),
              ),

              // REMEMBER ME TOGGLE
              Row(
                children: [
                  Theme(
                    data: ThemeData(unselectedWidgetColor: Colors.white54),
                    child: Checkbox(
                      value: _rememberMe,
                      activeColor: goldYellow,
                      checkColor: darkBlue,
                      onChanged: (val) => setState(() => _rememberMe = val!),
                    ),
                  ),
                  const Text(
                    "Remember Me",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {}, // Add forgot password logic
                    child: const Text(
                      "Forgot Password?",
                      style: TextStyle(color: goldYellow, fontSize: 12),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 15),
              _isLoading
                  ? const CircularProgressIndicator(color: goldYellow)
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: goldYellow,
                        foregroundColor: darkBlue,
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: _handleLogin,
                      child: const Text(
                        "SECURE LOGIN",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
              if (!_isRiderMode) ...[
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SignupScreen(),
                    ),
                  ),
                  child: const Text(
                    "Don't have an account? Create one",
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminPortalTrigger() {
    return GestureDetector(
      onTap: () {
        _adminTapCount++;
        if (_adminTapCount == 3) {
          _adminTapCount = 0;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AdminLoginScreen()),
          );
        }
        Future.delayed(const Duration(seconds: 2), () => _adminTapCount = 0);
      },
      child: Text(
        _isRiderMode ? "RIDER AGENT PORTAL" : "CLIENT LOGIN",
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: goldYellow,
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _buildRoleToggle() {
    return Container(
      width: 220,
      height: 45,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 250),
            alignment: _isRiderMode
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Container(
              width: 110,
              height: 45,
              decoration: BoxDecoration(
                color: goldYellow,
                borderRadius: BorderRadius.circular(25),
              ),
            ),
          ),
          Row(
            children: [
              _buildToggleButton(
                "CLIENT",
                !_isRiderMode,
                () => setState(() => _isRiderMode = false),
              ),
              _buildToggleButton(
                "RIDER",
                _isRiderMode,
                () => setState(() => _isRiderMode = true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, bool isActive, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? darkBlue : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword ? obscureText : false,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
        prefixIcon: Icon(icon, color: goldYellow, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_off : Icons.visibility,
                  color: goldYellow.withOpacity(0.7),
                ),
                onPressed: onToggleVisibility,
              )
            : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: goldYellow),
        ),
      ),
    );
  }
}
