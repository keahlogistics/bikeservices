import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

// --- PROJECT IMPORTS ---
import 'screens/login_screen.dart';
import 'screens/adminLogin_screens.dart';
import 'admin/adminDashboard_screens.dart';
import 'admin/userManagement_screens.dart';
import 'riderAgent/riderDashboard_screen.dart';
import 'admin/liveChatOrder_screens.dart';
import 'client/home_screen.dart';
import 'client/order_screen.dart';
import 'client/userProfile_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- ONESIGNAL SETUP ---
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize("8993629f-aabc-4a84-b34c-0b57935fe8db");
  OneSignal.Notifications.requestPermission(true);

  OneSignal.Notifications.addForegroundWillDisplayListener((event) {
    event.notification.display();
  });

  OneSignal.Notifications.addClickListener((event) {
    final data = event.notification.additionalData;
    if (data != null && data.containsKey('type')) {
      if (data['type'] == 'chat_alert') {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (context) => const AdminLiveChatSystem()),
        );
      }
    }
  });

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // --- SESSION & ROLE CHECK ---
  final prefs = await SharedPreferences.getInstance();
  final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  final String? role = prefs.getString('userRole');

  // FIXED: Check both userEmail and adminEmail to ensure OneSignal logs in correctly
  final String? userEmail =
      prefs.getString('userEmail') ?? prefs.getString('adminEmail');

  // CRITICAL FIX: Changed 'token' to 'userToken' to match AdminLoginScreen persistence
  final String? token = prefs.getString('userToken');

  // Link User to OneSignal using email as External ID
  if (isLoggedIn && userEmail != null) {
    OneSignal.login(userEmail.toLowerCase().trim());
  }

  // --- UPDATED NAVIGATION LOGIC ---
  Widget initialWidget;

  // Logic: Verify both the login flag and the existence of the token string
  if (isLoggedIn && token != null && token.isNotEmpty) {
    if (role == 'admin') {
      initialWidget = const AdminDashboard();
    } else if (role == 'rider') {
      initialWidget = const RiderDashboardScreen();
    } else if (role == 'user') {
      initialWidget = const HomeScreen();
    } else {
      initialWidget = const LoginScreen();
    }
  } else {
    // If token is missing, force login even if isLoggedIn is true
    initialWidget = const LoginScreen();
  }

  runApp(MyApp(initialWidget: initialWidget));
}

class MyApp extends StatelessWidget {
  final Widget initialWidget;
  const MyApp({super.key, required this.initialWidget});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Keah Logistics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A3A5F),
          primary: const Color(0xFF1A3A5F),
          secondary: const Color(0xFFFFD700),
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: initialWidget,
      routes: {
        '/login': (context) => const LoginScreen(),
        '/adminLogin': (context) => const AdminLoginScreen(),
        '/adminDashboard': (context) => const AdminDashboard(),
        '/riderDashboard': (context) => const RiderDashboardScreen(),
        '/liveChatORder': (context) => const AdminLiveChatSystem(),
        '/order_screen': (context) => const OrderScreen(),
        '/userProfile_screen': (context) => const UserProfileScreen(),
        '/userManagement_screen': (context) => const UserManagementScreen(),

        '/home': (context) => const HomeScreen(),
      },
      onUnknownRoute: (settings) {
        return MaterialPageRoute(builder: (context) => const LoginScreen());
      },
    );
  }
}
