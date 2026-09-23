import 'package:flutter/material.dart';

/// One budget-risk signal: a colour that is *always* accompanied by an icon and
/// a word, so the state survives colour blindness, glare and greyscale print.
@immutable
class RiskStyle {
  const RiskStyle({
    required this.color,
    required this.onColor,
    required this.containerColor,
    required this.onContainerColor,
    required this.icon,
    required this.label,
  });

  /// The strong colour: progress bars, icons, emphasised text.
  final Color color;

  /// Foreground that meets contrast on top of [color].
  final Color onColor;

  /// The tinted surface for chips and banners.
  final Color containerColor;

  /// Foreground that meets contrast on top of [containerColor].
  final Color onContainerColor;

  /// Shown next to — never instead of — the colour.
  final IconData icon;

  /// Plain-language state, e.g. "Over budget".
  final String label;

  RiskStyle copyWith({
    Color? color,
    Color? onColor,
    Color? containerColor,
    Color? onContainerColor,
    IconData? icon,
    String? label,
  }) {
    return RiskStyle(
      color: color ?? this.color,
      onColor: onColor ?? this.onColor,
      containerColor: containerColor ?? this.containerColor,
      onContainerColor: onContainerColor ?? this.onContainerColor,
      icon: icon ?? this.icon,
      label: label ?? this.label,
    );
  }

  static RiskStyle lerp(RiskStyle a, RiskStyle b, double t) {
    return RiskStyle(
      color: Color.lerp(a.color, b.color, t)!,
      onColor: Color.lerp(a.onColor, b.onColor, t)!,
      containerColor: Color.lerp(a.containerColor, b.containerColor, t)!,
      onContainerColor: Color.lerp(a.onContainerColor, b.onContainerColor, t)!,
      icon: t < 0.5 ? a.icon : b.icon,
      label: t < 0.5 ? a.label : b.label,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RiskStyle &&
          other.color == color &&
          other.onColor == onColor &&
          other.containerColor == containerColor &&
          other.onContainerColor == onContainerColor &&
          other.icon == icon &&
          other.label == label;

  @override
  int get hashCode => Object.hash(
        color,
        onColor,
        containerColor,
        onContainerColor,
        icon,
        label,
      );
}

/// The three budget states, resolved from the active [Theme].
@immutable
class BudgetRiskTheme extends ThemeExtension<BudgetRiskTheme> {
  const BudgetRiskTheme({
    required this.safe,
    required this.warning,
    required this.over,
  });

  /// Comfortably inside the limit.
  final RiskStyle safe;

  /// At or past 80% of the limit, but not over it.
  final RiskStyle warning;

  /// At or past the limit.
  final RiskStyle over;

  @override
  BudgetRiskTheme copyWith({
    RiskStyle? safe,
    RiskStyle? warning,
    RiskStyle? over,
  }) {
    return BudgetRiskTheme(
      safe: safe ?? this.safe,
      warning: warning ?? this.warning,
      over: over ?? this.over,
    );
  }

  @override
  BudgetRiskTheme lerp(ThemeExtension<BudgetRiskTheme>? other, double t) {
    if (other is! BudgetRiskTheme) return this;
    return BudgetRiskTheme(
      safe: RiskStyle.lerp(safe, other.safe, t),
      warning: RiskStyle.lerp(warning, other.warning, t),
      over: RiskStyle.lerp(over, other.over, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BudgetRiskTheme &&
          other.safe == safe &&
          other.warning == warning &&
          other.over == over;

  @override
  int get hashCode => Object.hash(safe, warning, over);
}

/// Light and dark themes for the app.
abstract final class AppTheme {
  /// Deep teal: distinct from the red/amber/green risk signals, so a risk
  /// colour never reads as "brand chrome".
  static const Color seed = Color(0xFF0B6E5F);

  static const List<FontFeature> _tabularFigures = [
    FontFeature.tabularFigures()
  ];

  static const BudgetRiskTheme _lightRisk = BudgetRiskTheme(
    safe: RiskStyle(
      color: Color(0xFF1B6B3A),
      onColor: Color(0xFFFFFFFF),
      containerColor: Color(0xFFD7F2E0),
      onContainerColor: Color(0xFF0B3D20),
      icon: Icons.check_circle_outline,
      label: 'On track',
    ),
    warning: RiskStyle(
      color: Color(0xFF8A5200),
      onColor: Color(0xFFFFFFFF),
      containerColor: Color(0xFFFFE8C2),
      onContainerColor: Color(0xFF4A2B00),
      icon: Icons.warning_amber_rounded,
      label: 'Nearing limit',
    ),
    over: RiskStyle(
      color: Color(0xFFB3261E),
      onColor: Color(0xFFFFFFFF),
      containerColor: Color(0xFFFFDAD6),
      onContainerColor: Color(0xFF5F1412),
      icon: Icons.error_outline,
      label: 'Over budget',
    ),
  );

  static const BudgetRiskTheme _darkRisk = BudgetRiskTheme(
    safe: RiskStyle(
      color: Color(0xFF7CD9A0),
      onColor: Color(0xFF00351A),
      containerColor: Color(0xFF14432A),
      onContainerColor: Color(0xFFB7F0CC),
      icon: Icons.check_circle_outline,
      label: 'On track',
    ),
    warning: RiskStyle(
      color: Color(0xFFFFC46B),
      onColor: Color(0xFF3B2300),
      containerColor: Color(0xFF523400),
      onContainerColor: Color(0xFFFFDFB0),
      icon: Icons.warning_amber_rounded,
      label: 'Nearing limit',
    ),
    over: RiskStyle(
      color: Color(0xFFFFB4AB),
      onColor: Color(0xFF690005),
      containerColor: Color(0xFF7A1F1A),
      onContainerColor: Color(0xFFFFDAD6),
      icon: Icons.error_outline,
      label: 'Over budget',
    ),
  );

  /// The risk palette from [theme].
  ///
  /// Falls back to the light one rather than returning null: a theme built
  /// without the extension — a bare `MaterialApp` in a test — should still
  /// paint a budget, and a missing palette must never be the reason a badge
  /// loses its colour.
  static BudgetRiskTheme riskOf(ThemeData theme) =>
      theme.extension<BudgetRiskTheme>() ?? _lightRisk;

  static ThemeData light() => _build(Brightness.light, _lightRisk);

  static ThemeData dark() => _build(Brightness.dark, _darkRisk);

  static ThemeData _build(Brightness brightness, BudgetRiskTheme risk) {
    final scheme =
        ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _textTheme(brightness),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        scrolledUnderElevation: 2,
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 12,
        titleAlignment: ListTileTitleAlignment.top,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      extensions: [risk],
    );
  }

  /// Amounts use tabular figures so columns of money line up as they change.
  static TextTheme _textTheme(Brightness brightness) {
    final typography = Typography.material2021();
    final base =
        brightness == Brightness.light ? typography.black : typography.white;

    return base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: _tabularFigures,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: _tabularFigures,
      ),
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.35),
      bodySmall: base.bodySmall?.copyWith(height: 1.3),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }
}
