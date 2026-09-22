import 'package:flutter/material.dart';

/// A placeholder block for content that has not arrived yet.
///
/// No shimmer package and no gradient sweep: a slow opacity pulse is cheaper,
/// reads better on low-end devices, and stops dead when the platform asks for
/// reduced motion — in which case the box simply sits at its end state.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 8,
  });

  /// Null stretches to the available width.
  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(milliseconds: 1100);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _period,
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncWithMotionPreference(MediaQuery.of(context).disableAnimations);
  }

  void _syncWithMotionPreference(bool disableAnimations) {
    if (disableAnimations) {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 1; // Jump to the end state.
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final peak =
        Color.alphaBlend(scheme.onSurface.withValues(alpha: 0.06), base);

    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: Color.lerp(peak, base, _controller.value),
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
          );
        },
      ),
    );
  }
}

/// A stack of [Skeleton] rows shaped like a transaction list, for the loading
/// branch of `AsyncValue.when`.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(16),
    this.label = 'Loading',
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;

  /// Announced to screen readers in place of the blocks themselves.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      container: true,
      child: ListView.separated(
        padding: padding,
        itemCount: itemCount,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        separatorBuilder: (_, __) => const SizedBox(height: 20),
        itemBuilder: (_, __) => const _SkeletonRow(),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Skeleton(width: 40, height: 40, borderRadius: 20),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(height: 14),
              SizedBox(height: 8),
              Skeleton(width: 120, height: 12),
            ],
          ),
        ),
        SizedBox(width: 12),
        Skeleton(width: 72, height: 14),
      ],
    );
  }
}
