import 'package:flutter/material.dart';

import 'lab_controls.dart';
import 'lab_stage.dart';
import 'lab_state.dart';

/// Tree Lab — the tuning harness for GROW's procedural trees.
///
/// The distance between "correct L-system" and "a tree you want to look at" is
/// a few hundred iterations on twenty numbers. Doing that inside the full game
/// is far too slow a loop, so this exists: every parameter on a slider, the
/// tree redrawing live, and a button that writes the result back out as JSON.
///
///   flutter run -d DEVICE -t tools/tree_lab/lib/main.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TreeLabApp());
}

class TreeLabApp extends StatelessWidget {
  const TreeLabApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tree Lab',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2F6B4F),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF4F5F3),
    ),
    home: const _LabHome(),
  );
}

class _LabHome extends StatefulWidget {
  const _LabHome();

  @override
  State<_LabHome> createState() => _LabHomeState();
}

class _LabHomeState extends State<_LabHome> {
  final LabState _state = LabState();

  @override
  void initState() {
    super.initState();
    _state.addListener(_onChanged);
    _state.loadAtlas();
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _state.removeListener(_onChanged);
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final stage = LabStage(state: _state);
    final controls = LabControls(state: _state);

    return Scaffold(
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  Expanded(child: stage),
                  SizedBox(width: 380, child: controls),
                ],
              )
            : Column(
                children: [
                  Expanded(flex: 3, child: stage),
                  Expanded(flex: 4, child: controls),
                ],
              ),
      ),
    );
  }
}
