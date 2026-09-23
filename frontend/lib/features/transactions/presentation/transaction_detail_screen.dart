import 'package:flutter/material.dart';

/// Placeholder for `/transactions/:id`. It exists so a tapped feed row has
/// somewhere to land; the real detail screen replaces it in a later phase.
class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction')),
      body: Center(child: Text('Transaction $id')),
    );
  }
}
