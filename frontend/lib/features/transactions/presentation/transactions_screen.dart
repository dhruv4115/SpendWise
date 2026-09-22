import 'package:flutter/material.dart';

/// Placeholder. The paged, filterable feed replaces this in a later phase.
class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transactions')),
      body: const Center(child: Text('Transactions')),
    );
  }
}

/// Placeholder for `/transactions/:id`. It exists this phase so the deep link
/// has somewhere to land; the real detail screen arrives with the feed.
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
