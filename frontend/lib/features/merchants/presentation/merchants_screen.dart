import 'package:flutter/material.dart';

/// Placeholder. Merchant insights replace this later.
class MerchantsScreen extends StatelessWidget {
  const MerchantsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Merchants')),
      body: const Center(child: Text('Merchants')),
    );
  }
}

/// Placeholder for `/merchants/:id`, where the id is a merchant key.
class MerchantDetailScreen extends StatelessWidget {
  const MerchantDetailScreen({super.key, required this.merchantKey});

  final String merchantKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Merchant')),
      body: Center(child: Text('Merchant $merchantKey')),
    );
  }
}
