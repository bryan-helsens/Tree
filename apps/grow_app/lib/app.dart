import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'design_system/tokens.dart';
import 'features/forest/forest_screen.dart';

class GrowApp extends StatelessWidget {
  const GrowApp({super.key});

  @override
  Widget build(BuildContext context) => ProviderScope(
    child: WidgetsApp(
      color: GrowTokens.ink,
      title: 'GROW',
      debugShowCheckedModeBanner: false,
      builder: (context, _) => const ForestScreen(),
    ),
  );
}
