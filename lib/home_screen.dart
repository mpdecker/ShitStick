import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'notification_service.dart';

const _kofiUrl = 'https://ko-fi.com/matthieudecker';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _koan;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ensureKoanChain().then((_) => _loadKoan());
    }
  }

  Future<void> _init() async {
    await requestPermissions();
    // freshVisit: a web open always rolls a new koan — the screen is the
    // only delivery channel there, so the gap must not pin one koan across
    // consecutive visits. Native ignores the flag (the notification chain
    // owns delivery).
    await ensureKoanChain(freshVisit: true);
    final current = await getCurrentKoan();
    if (current == null) await scheduleNext();
    await _loadKoan();
  }

  Future<void> _loadKoan() async {
    final current = await getCurrentKoan();
    if (mounted) setState(() => _koan = current);
  }

  @override
  Widget build(BuildContext context) {
    // Native: the koan lives only in the notification — this screen stays
    // black. Web has no equivalent to a background-scheduled notification
    // chain, so it's the only place the koan can actually be seen there.
    if (!kIsWeb || _koan == null) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _koan!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.5),
              ),
            ),
          ),
          // Quiet, not a settings screen — this app doesn't have one and
          // shouldn't grow one. Just a way out for anyone who wants it,
          // small enough not to compete with the koan.
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: GestureDetector(
                onTap: () => launchUrl(Uri.parse(_kofiUrl), webOnlyWindowName: '_blank'),
                child: Text(
                  'support',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11, letterSpacing: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
