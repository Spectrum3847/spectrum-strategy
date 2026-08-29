// Placeholder entry point. This repository is the public mirror of Spectrum
// Strategy and receives the real source when release 1.0.0 publishes; see
// README.md. Nothing here reflects the app.
import 'package:flutter/material.dart';

void main() => runApp(const PlaceholderApp());

/// Says what this repository is, for anyone who builds it before the first
/// release sync.
class PlaceholderApp extends StatelessWidget {
  const PlaceholderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Spectrum Strategy',
      home: Scaffold(
        body: Center(
          child: Text('The Spectrum Strategy source lands with release 1.0.0.'),
        ),
      ),
    );
  }
}
