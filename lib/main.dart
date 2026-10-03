import 'package:flutter/material.dart';

import 'ui/home_screen.dart';

void main() => runApp(const BikeAssystApp());

class BikeAssystApp extends StatelessWidget {
  const BikeAssystApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Bike Assyst',
        theme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark),
        home: const HomeScreen(),
      );
}
