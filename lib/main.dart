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
  // Initialize OneSignal first
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize("8993629f-aabc-4a84-b34c-0b57935fe8db");

  // Explicitly request permissions
  OneSignal.Notifications.requestPermission(true);

  // Handle Foreground Notifications
  OneSignal.Notifications.addForegroundWillDisplayListener((event) {
    debugPrint(
      'Notification received in foreground: ${event.notification.body}',
    );
    event.notification.display();
  });

  // Handle Notification Taps (Click Listener)
  OneSignal.Notifications.addClickListener((event) {
    final data = event.notification.additionalData;
    debugPrint("Notification Clicked with data: $data");

    if (data != null && data.containsKey('type')) {
      // Logic for Admin Chat Alerts
      if (data['type'] == 'chat_alert' || data['type'] == 'chat') {
        navigatorKey.currentState?.pushNamed('/liveChatORder');
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

  // Check both userEmail and adminEmail for OneSignal identity
  final String? userEmail =
      prefs.getString('userEmail') ?? prefs.getString('adminEmail');
  final String? token = prefs.getString('userToken');

  // --- SYNC ONESIGNAL EXTERNAL ID ---
  // This links the device to the email so the backend can target via 'targetEmail'
  if (isLoggedIn && userEmail != null) {
    String cleanEmail = userEmail.toLowerCase().trim();
    OneSignal.login(cleanEmail);
    debugPrint("OneSignal Identity Synced: $cleanEmail");
  }

  // --- NAVIGATION LOGIC ---
  Widget initialWidget;

  if (isLoggedIn && token != null && token.isNotEmpty) {
    switch (role) {
      case 'admin':
        initialWidget = const AdminDashboard();
        break;
      case 'rider':
        initialWidget = const RiderDashboardScreen();
        break;
      case 'user':
        initialWidget = const HomeScreen();
        break;
      default:
        initialWidget = const LoginScreen();
    }
  } else {
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
