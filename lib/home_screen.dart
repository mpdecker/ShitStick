import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'notification_service.dart';

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
    await ensureKoanChain();
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _koan!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.5),
          ),
        ),
      ),
    );
  }
}
