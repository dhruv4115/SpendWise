/// What happens after the category sheet closes: the request, the rollback,
/// the Undo, and everything the customer is told about any of it.
///
/// Its own file because two screens start the same flow — one transaction
/// from its detail screen, and a whole merchant from theirs — and a
/// recategorisation must be reported the same way whichever it came from.
library;

import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../categories/domain/category.dart';
import '../../categories/state/categories_provider.dart';
import '../domain/transaction.dart';
import '../state/recategorise_controller.dart';
import '../widgets/category_sheet.dart';

/// A recategorisation from the moment the sheet closes.
///
/// Everything it needs is captured while the screen is still mounted, so it
/// finishes — rollback, SnackBar, announcement — even if the customer has
/// already gone back to the feed. The messenger belongs to the app, not to
/// this screen, and the controller keeps itself alive for the request and
/// for the Undo.
class RecategoriseFlow {
  RecategoriseFlow({
    required this.controller,
    required this.messenger,
    required this.view,
    required this.textDirection,
    required this.transaction,
    required this.categories,
    required this.screenMounted,
  });

  factory RecategoriseFlow.capture(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
  ) {
    return RecategoriseFlow(
      controller:
          ref.read(recategoriseControllerProvider(transaction.id).notifier),
      messenger: ScaffoldMessenger.of(context),
      view: View.of(context),
      textDirection: Directionality.of(context),
      transaction: transaction,
      categories: ref.read(categoriesProvider).valueOrNull ?? const [],
      screenMounted: () => context.mounted,
    );
  }

  final RecategoriseController controller;
  final ScaffoldMessengerState messenger;
  final FlutterView view;
  final TextDirection textDirection;
  final Transaction transaction;
  final List<Category> categories;
  final bool Function() screenMounted;

  Future<void> commit(CategoryChoice choice) async {
    final outcome = await controller.commit(
      transaction: transaction,
      category: choice.category,
      applyToMerchant: choice.applyToMerchant,
    );

    switch (outcome) {
      case RecategoriseSucceeded(value: final change):
        final name = categories.nameOf(change.category);
        final message = change.applyToMerchant
            ? 'Moved all ${transaction.merchantName} transactions to $name.'
            : 'Moved to $name.';
        messenger.hideCurrentSnackBar();
        final shown = messenger.showSnackBar(
          SnackBar(
            content: Text(message),
            duration: undoWindow,
            // A SnackBar with an action stays up until dismissed unless told
            // otherwise; the Undo is a five-second offer.
            persist: false,
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => unawaited(undo(change)),
            ),
          ),
        );
        unawaited(shown.closed.then((_) => controller.releaseUndo(change)));
        _announce('$message Undo is available for '
            '${undoWindow.inSeconds} seconds.');

      case RecategoriseFailed(:final error):
        _showError(
          'Category not changed. ${error.userMessage}',
          retry: error.isRetryable ? () => unawaited(commit(choice)) : null,
        );
    }
  }

  Future<void> undo(AppliedRecategorisation change) async {
    final outcome = await controller.undo();

    switch (outcome) {
      case RecategoriseSucceeded():
        final previous = change.previousCategories[change.transactionId];
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Change undone.')));
        _announce(
          previous == null || change.applyToMerchant
              ? 'Change undone.'
              : 'Change undone. Back in ${categories.nameOf(previous)}.',
        );

      case RecategoriseFailed(:final error):
        _showError(
          'We could not undo that. ${error.userMessage}',
          retry: error.isRetryable ? () => unawaited(undo(change)) : null,
        );
    }
  }

  /// A Retry is only offered while the screen is up: once it has gone, so
  /// has the controller the retry would need.
  void _showError(String message, {VoidCallback? retry}) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 8),
          persist: false,
          action: retry != null && screenMounted()
              ? SnackBarAction(label: 'Retry', onPressed: retry)
              : null,
        ),
      );
    _announce(message);
  }

  void _announce(String message) {
    unawaited(SemanticsService.sendAnnouncement(view, message, textDirection));
  }
}
