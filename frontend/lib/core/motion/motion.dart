/// Every duration and curve the app animates with, and the question each one
/// has to ask first.
///
/// Motion in a banking app is there to explain a change, never to decorate
/// one: a ring sweeping in says "this is being drawn for you now", a bar
/// sliding from amber to red says "this moved, and here is how far". So every
/// animation here is short, and every one of them is optional — [reduceMotion]
/// is the one switch, and an implicit animation handed [Duration.zero] lands
/// on its end state in the same frame.
library;

import 'package:flutter/material.dart';

/// Whether the customer has asked the platform for less motion.
///
/// Reads the one aspect rather than the whole [MediaQuery], so flipping the
/// keyboard open does not rebuild every animated widget in the tree.
bool reduceMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);

/// [duration], or nothing at all when the customer has asked for less motion.
///
/// The single line every animation in this app goes through, so "honours
/// reduced motion" is not a thing each widget has to remember separately.
Duration motionDuration(BuildContext context, Duration duration) =>
    reduceMotion(context) ? Duration.zero : duration;

/// The named durations and curves. Nothing animates for a length of time that
/// is not one of these.
abstract final class Motion {
  /// A control answering a tap: a chip filling in, an icon turning.
  static const Duration quick = Duration(milliseconds: 150);

  /// One page of the month strip sliding past.
  static const Duration page = Duration(milliseconds: 240);

  /// A chart being redrawn because its data changed — a cross-fade, so the
  /// figures are never seen mid-morph and misread on the way.
  static const Duration crossFade = Duration(milliseconds: 220);

  /// A budget moving between risk states: the bar's fill and its colour, and
  /// the badge's words, all on this one clock so they change together.
  static const Duration riskChange = Duration(milliseconds: 300);

  /// A line chart drawing its path.
  static const Duration lineDraw = Duration(milliseconds: 300);

  /// The donut drawing itself the first time a month is shown.
  static const Duration donutSweep = Duration(milliseconds: 450);

  /// One direction of a skeleton's pulse.
  static const Duration skeletonPulse = Duration(milliseconds: 1100);

  /// Something arriving: fast at first, settling at the end.
  static const Curve enter = Curves.easeOutCubic;

  /// Something changing from one settled state to another.
  static const Curve standard = Curves.easeInOut;
}
