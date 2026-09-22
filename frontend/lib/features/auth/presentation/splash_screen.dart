import 'package:flutter/material.dart';

/// Shown for the moment it takes to read the keystore on boot.
///
/// It never decides anything: the router's redirect moves on as soon as the
/// session state stops being [SessionUnknown].
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A spinner is an animation like any other. When the platform asks for
    // reduced motion it is replaced rather than frozen — a stopped spinner
    // reads as a broken app.
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('SpendWise', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 24),
              if (reduceMotion)
                Icon(
                  Icons.hourglass_empty,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              else
                const SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              const SizedBox(height: 16),
              Text(
                'Getting your account ready…',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
