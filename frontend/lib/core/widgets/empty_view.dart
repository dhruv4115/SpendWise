import 'package:flutter/material.dart';

/// The "there is genuinely nothing here" state — distinct from loading and
/// from failure, both of which have their own widgets.
///
/// Scrolls rather than overflows, so it survives a 2.0 text scale on a short
/// screen.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;

  /// One or two sentences explaining what would put content here.
  final String message;

  /// Optional call to action, usually a button.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Decorative: the title below carries the meaning.
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (action case final Widget callToAction) ...[
              const SizedBox(height: 20),
              callToAction,
            ],
          ],
        ),
      ),
    );
  }
}
