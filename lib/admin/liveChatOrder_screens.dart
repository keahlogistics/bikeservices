import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

// --- PROJECT IMPORTS ---
import 'userManagement_screens.dart';
import 'riderManagement_screens.dart';
import '../screens/adminLogin_screens.dart';

// --- SHARED CONFIG ---
const Color goldYellow = Color(0xFFFFD700);
const Color darkBlue = Color(0xFF0D1B2A);
const String baseApiUrl =
    'https://keahlogistics.netlify.app/.netlify/functions/api';
const String companyAccountNumber = "8149747864";
const String companyBankName = "Moniepoint";
const String adminEmail = "keahlogisticsq@gmail.com";

class AdminLiveChatSystem extends StatefulWidget {
  const AdminLiveChatSystem({super.key});

  @override
  State<AdminLiveChatSystem> createState() => _AdminLiveChatSystemState();
}

class _AdminLiveChatSystemState extends State<AdminLiveChatSystem> {
  bool _isViewingChat = false;
  String? _selectedUserEmail;
  String? _selectedUserName;
  String? _selectedUserProfile;

  List<dynamic> _chatThreads = [];
  bool _isLoadingThreads = true;
  bool _isFetchingInbox = false;
  Timer? _inboxTimer;

  @override
  void initState() {
    super.initState();
    _fetchChatThreads();
    _inboxTimer = Timer.periodic(
      const Duration(seconds: 15),
      (t) => _fetchChatThreads(),
    );
  }

  @override
  void dispose() {
    _inboxTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchChatThreads() async {
    if (_isFetchingInbox) return;
    if (mounted) setState(() => _isFetchingInbox = true);

    try {
      final response = await http
          .get(Uri.parse('$baseApiUrl/get-all-messages'))
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200 && mounted) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _chatThreads = data;
          _isLoadingThreads = false;
        });
      }
    } catch (e) {
      debugPrint("Inbox Fetch Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingInbox = false;
          _isLoadingThreads = false;
        });
      }
    }
  }

  void _openChat(dynamic thread) {
    setState(() {
      _selectedUserEmail = thread['userEmail'];
      _selectedUserName = thread['userName'] ?? "Customer";
      _selectedUserProfile = thread['profileImage'];
      _isViewingChat = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isViewingChat && _selectedUserEmail != null) {
      return LiveChatOrderScreen(
        userEmail: _selectedUserEmail!,
        userName: _selectedUserName!,
        profileImage: _selectedUserProfile,
        onBack: () {
          setState(() => _isViewingChat = false);
          _fetchChatThreads();
        },
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: darkBlue,
        centerTitle: true,
        title: const Text(
          "ADMIN INBOX",
          style: TextStyle(
            color: goldYellow,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _fetchChatThreads,
            icon: _isFetchingInbox
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: goldYellow,
                    ),
                  )
                : const Icon(Icons.refresh, color: goldYellow),
          ),
        ],
      ),
      body: _isLoadingThreads
          ? const Center(child: CircularProgressIndicator(color: goldYellow))
          : RefreshIndicator(
              color: goldYellow,
              backgroundColor: darkBlue,
              onRefresh: _fetchChatThreads,
              child: _chatThreads.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.3,
                        ),
                        const Center(
                          child: Text(
                            "No active customer chats",
                            style: TextStyle(color: Colors.white38),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(10),
                      itemCount: _chatThreads.length,
                      itemBuilder: (context, index) {
                        final thread = _chatThreads[index];
                        final bool hasUnread = (thread['unreadCount'] ?? 0) > 0;
                        return _buildThreadTile(thread, hasUnread);
                      },
                    ),
            ),
      bottomNavigationBar: _buildStickyFooter(),
    );
  }

  Widget _buildThreadTile(dynamic thread, bool hasUnread) {
    final String? imgUrl = thread['profileImage'];
    final bool hasValidImage =
        imgUrl != null && imgUrl.isNotEmpty && imgUrl.startsWith('http');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: darkBlue,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasUnread ? goldYellow.withOpacity(0.5) : Colors.white10,
        ),
      ),
      child: ListTile(
        onTap: () => _openChat(thread),
        leading: CircleAvatar(
          backgroundColor: Colors.white10,
          backgroundImage: hasValidImage
              ? CachedNetworkImageProvider(imgUrl)
              : null,
          child: !hasValidImage
              ? const Icon(Icons.person, color: goldYellow)
              : null,
        ),
        title: Text(
          thread['userName'] ?? "User",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          thread['lastMessage'] ?? "No messages",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: hasUnread ? Colors.white : Colors.white38,
            fontSize: 12,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (hasUnread)
              CircleAvatar(
                radius: 10,
                backgroundColor: goldYellow,
                child: Text(
                  "${thread['unreadCount']}",
                  style: const TextStyle(
                    fontSize: 10,
                    color: darkBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              const Icon(Icons.chevron_right, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _buildStickyFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        color: darkBlue,
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
              Icons.chat_bubble_rounded,
              "Chat",
              () {},
              isActive: true,
            ),
            _footerItem(
              Icons.pedal_bike,
              "Riders",
              () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (c) => const RiderManagementScreen(),
                ),
              ),
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
      backgroundColor: darkBlue,
      builder: (context) => ListTile(
        leading: const Icon(Icons.logout, color: Colors.redAccent),
        title: const Text("Logout", style: TextStyle(color: Colors.white)),
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
    );
  }
}

class LiveChatOrderScreen extends StatefulWidget {
  final String userEmail;
  final String userName;
  final String? profileImage;
  final VoidCallback onBack;

  const LiveChatOrderScreen({
    super.key,
    required this.userEmail,
    required this.userName,
    this.profileImage,
    required this.onBack,
  });

  @override
  State<LiveChatOrderScreen> createState() => _LiveChatOrderScreenState();
}

class _LiveChatOrderScreenState extends State<LiveChatOrderScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _messages = [];
  bool _isLoading = true;
  bool _isFetching = false;
  Timer? _timer;

  late AnimationController _animationController;
  late Animation<double> _expandAnimation;
  bool _isMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _initialLoad();
    _timer = Timer.periodic(const Duration(seconds: 5), (t) => _fetchChat());
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.fastOutSlowIn,
    );
  }

  Future<void> _initialLoad() async {
    await _fetchChat();
    _markAsRead();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
      _isMenuOpen
          ? _animationController.forward()
          : _animationController.reverse();
    });
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        imageQuality: 70,
      );

      if (pickedFile != null) {
        File imageFile = File(pickedFile.path);
        List<int> imageBytes = await imageFile.readAsBytes();
        String base64Image =
            "data:image/jpeg;base64,${base64Encode(imageBytes)}";

        // We still send Base64 to the Netlify function,
        // but the function will now save it to IDrive and return the Key.
        _postMessage("Sent an image", imageBase64: base64Image);
      }
    } catch (e) {
      _showErrorSnackBar("Image Error: Check permissions.");
    }
  }

  Future<void> _markAsRead() async {
    try {
      await http.post(
        Uri.parse('$baseApiUrl/mark-read'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": widget.userEmail, "isAdminSide": true}),
      );
    } catch (e) {
      debugPrint("Read Status Error: $e");
    }
  }

  Future<void> _fetchChat() async {
    if (_isFetching) return;
    _isFetching = true;
    try {
      final response = await http
          .get(Uri.parse('$baseApiUrl/get-messages?email=${widget.userEmail}'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && mounted) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.length != _messages.length) {
          setState(() {
            _messages = data;
            _isLoading = false;
          });
          _scrollToBottom();
          _markAsRead();
        } else {
          if (_isLoading) setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
    } finally {
      _isFetching = false;
    }
  }

  Future<void> _postMessage(String text, {String? imageBase64}) async {
    if (text.trim().isEmpty && imageBase64 == null) return;
    String originalText = text.trim();
    if (imageBase64 == null) _messageController.clear();

    // Optimistic Update: Temporary Base64 for instant feedback
    final newMessage = {
      "text": originalText,
      "isAdmin": true,
      "senderEmail": adminEmail,
      "receiverEmail": widget.userEmail,
      "packageImage": imageBase64 ?? "",
      "timestamp": DateTime.now().toIso8601String(),
      "isSending": true,
    };

    if (mounted) {
      setState(() => _messages.add(newMessage));
      _scrollToBottom();
    }

    try {
      final response = await http
          .post(
            Uri.parse('$baseApiUrl/send-message'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "senderEmail": adminEmail,
              "receiverEmail": widget.userEmail,
              "text": originalText,
              "isAdmin": true,
              "packageImage":
                  imageBase64 ??
                  "", // Netlify function handles the IDrive upload
            }),
          )
          .timeout(
            const Duration(seconds: 45),
          ); // Longer timeout for IDrive upload processing

      if (response.statusCode != 201 && mounted) {
        _showErrorSnackBar("Failed to deliver. Retrying...");
      }
      _fetchChat();
    } catch (e) {
      if (mounted) _showErrorSnackBar("IDrive Upload Delay. Please wait...");
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasValidImage =
        widget.profileImage != null && widget.profileImage!.startsWith('http');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: darkBlue,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: goldYellow),
          onPressed: widget.onBack,
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white10,
              backgroundImage: hasValidImage
                  ? CachedNetworkImageProvider(widget.profileImage!)
                  : null,
              child: !hasValidImage
                  ? const Icon(Icons.person, color: goldYellow, size: 18)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.userName,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFabMenu(),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: goldYellow),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(15),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final bool isMe = msg['isAdmin'] == true;
                      if (msg['text'].toString().contains(
                        "📦 NEW ORDER LOGGED",
                      )) {
                        return _buildOrderReceiptCard(msg);
                      }
                      return _buildChatBubble(
                        msg['text'] ?? "",
                        msg['packageImage'] ??
                            "", // This will be the IDrive Signed URL or temporary Base64
                        isMe,
                        isSending: msg['isSending'] ?? false,
                      );
                    },
                  ),
          ),
          _buildInputSection(),
        ],
      ),
    );
  }

  Widget _buildFabMenu() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 70),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildAnimatedFab(
            Icons.camera_alt_rounded,
            "Camera",
            () => _pickAndSendImage(ImageSource.camera),
          ),
          const SizedBox(height: 12),
          _buildAnimatedFab(
            Icons.image_rounded,
            "Gallery",
            () => _pickAndSendImage(ImageSource.gallery),
          ),
          const SizedBox(height: 12),
          _buildAnimatedFab(
            Icons.verified_rounded,
            "Paid",
            () => _postMessage("✅ Payment Confirmed!"),
          ),
          const SizedBox(height: 12),
          _buildAnimatedFab(Icons.receipt_long, "Fee", _showFeeDialog),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: "main_toggle",
            backgroundColor: goldYellow,
            onPressed: _toggleMenu,
            child: AnimatedRotation(
              duration: const Duration(milliseconds: 250),
              turns: _isMenuOpen ? 0.125 : 0,
              child: Icon(
                _isMenuOpen ? Icons.close : Icons.add,
                color: darkBlue,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedFab(IconData icon, String label, VoidCallback onTap) {
    return SizeTransition(
      sizeFactor: _expandAnimation,
      child: FadeTransition(
        opacity: _expandAnimation,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: goldYellow,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton.small(
                heroTag: "fab_$label",
                backgroundColor: const Color(0xFF1E3A5F),
                onPressed: () {
                  onTap();
                  if (_isMenuOpen) _toggleMenu();
                },
                child: Icon(icon, color: goldYellow, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatBubble(
    String text,
    String img,
    bool isMe, {
    bool isSending = false,
  }) {
    bool isPaymentReq = text.contains("[PAYMENT_REQ]");
    String cleanText = text.replaceFirst("[PAYMENT_REQ] ", "");
    bool hasImage = img.isNotEmpty;

    return Opacity(
      opacity: isSending ? 0.6 : 1.0,
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFF1E3A5F) : const Color(0xFF262626),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(15),
              topRight: const Radius.circular(15),
              bottomLeft: Radius.circular(isMe ? 15 : 0),
              bottomRight: Radius.circular(isMe ? 0 : 15),
            ),
            border: Border.all(
              color: isPaymentReq ? goldYellow : Colors.white10,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasImage) ...[
                GestureDetector(
                  onTap: () => _showImageOverlay(img),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: img.startsWith('http')
                        ? CachedNetworkImage(
                            imageUrl: img,
                            placeholder: (c, u) => const SizedBox(
                              height: 150,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                            errorWidget: (context, url, error) => const Icon(
                              Icons.broken_image,
                              color: Colors.white24,
                            ),
                          )
                        : Image.memory(
                            base64Decode(img.split(',').last),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.image_not_supported),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                cleanText,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              if (isSending)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    "sending...",
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFeeDialog() {
    final TextEditingController amountController = TextEditingController();
    double deliveryFee = 0.0;
    double total = 0.0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: darkBlue,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: goldYellow),
          ),
          title: const Text(
            "CREATE BILLING",
            style: TextStyle(
              color: goldYellow,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                autofocus: true,
                onChanged: (val) {
                  setDialogState(() {
                    deliveryFee = double.tryParse(val) ?? 0.0;
                    total = deliveryFee + (deliveryFee * 0.05);
                  });
                },
                decoration: const InputDecoration(
                  labelText: "Delivery Amount",
                  labelStyle: TextStyle(color: Colors.white38),
                  prefixText: "₦ ",
                  prefixStyle: TextStyle(color: goldYellow),
                ),
              ),
              const SizedBox(height: 20),
              _feeRow(
                "Service Fee (5%):",
                "₦${(deliveryFee * 0.05).toStringAsFixed(2)}",
              ),
              const Divider(color: Colors.white10),
              _feeRow("TOTAL:", "₦${total.toStringAsFixed(2)}", isBold: true),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "CANCEL",
                style: TextStyle(color: Colors.white38),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: goldYellow),
              onPressed: () {
                if (total > 0) {
                  _postMessage(
                    "[PAYMENT_REQ] *BILLING SUMMARY*\nTotal: ₦${total.toStringAsFixed(2)}\n\nBank: $companyBankName\nAcc: $companyAccountNumber\nName: KEAH LOGISTICS",
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text(
                "SEND BILL",
                style: TextStyle(color: darkBlue, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feeRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          value,
          style: TextStyle(
            color: isBold ? goldYellow : Colors.white,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  void _showImageOverlay(String img) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: img.startsWith('http')
                  ? CachedNetworkImage(imageUrl: img)
                  : Image.memory(base64Decode(img.split(',').last)),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderReceiptCard(dynamic msg) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141E26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: goldYellow.withOpacity(0.4)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text(
            msg['text'],
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  onPressed: () => _postMessage("Order Accepted! ✅"),
                  child: const Text(
                    "ACCEPT",
                    style: TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => _postMessage("Order Declined. ❌"),
                  child: const Text(
                    "DECLINE",
                    style: TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.all(10),
      color: darkBlue,
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              onPressed: () => _pickAndSendImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt, color: goldYellow),
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Type a reply...",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: goldYellow,
              child: IconButton(
                icon: const Icon(Icons.send, color: darkBlue),
                onPressed: () => _postMessage(_messageController.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
