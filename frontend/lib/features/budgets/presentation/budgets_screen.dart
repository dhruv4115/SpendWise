import 'package:flutter/material.dart';

/// Placeholder. Budget rows and the set-a-limit flow replace this later.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: const Center(child: Text('Budgets')),
    );
  }
}

/// Placeholder for `/budgets/:category`.
class BudgetDetailScreen extends StatelessWidget {
  const BudgetDetailScreen({super.key, required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budget')),
      body: Center(child: Text('Budget $category')),
    );
  }
}
