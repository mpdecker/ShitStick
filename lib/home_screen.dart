import 'package:flutter/material.dart';
import 'notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _koan;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String? current = await getCurrentKoan();
    current ??= await scheduleNext();

    setState(() {
      _koan = current;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _ready ? _body() : const SizedBox.shrink(),
      ),
    );
  }

  Widget _body() {
    if (_koan == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _koan!,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            height: 1.7,
            fontWeight: FontWeight.w300,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
