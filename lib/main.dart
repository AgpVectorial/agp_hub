import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme.dart';
import 'core/features/home/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: AgpWearHubApp()));
}

class AgpWearHubApp extends StatelessWidget {
  const AgpWearHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AGP Wear Hub',
      debugShowCheckedModeBanner: false,
      theme: appDarkTheme(),
      home: const HomePage(),
    );
  }
}
