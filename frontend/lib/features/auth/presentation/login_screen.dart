import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/bank_error.dart';
import '../../../core/utils/validators.dart';
import '../state/login_controller.dart';

/// Sign-in. The only screen a signed-out customer can reach.
///
/// It navigates nowhere: a successful submit changes the session state, and
/// the router's redirect takes the customer to where they were headed.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  bool _obscure = true;
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Read, not watch: this is a handler.
    final controller = ref.read(loginControllerProvider.notifier);

    if (!(_formKey.currentState?.validate() ?? false)) {
      // From here on the fields correct themselves as they are edited, rather
      // than waiting for another rejected submit.
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }

    await controller.submit(
      email: _email.text.trim(),
      password: _password.text,
    );
  }

  void _clearBanner() =>
      ref.read(loginControllerProvider.notifier).dismissError();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(loginControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Scrolls rather than overflows: at textScaler 2.0 this content is
            // taller than a phone screen, and a form that cannot be scrolled
            // to its submit button is a form that cannot be used.
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  // Never negative: the vertical padding can exceed a very
                  // short viewport, such as a phone in landscape.
                  minHeight: math.max(0, constraints.maxHeight - 64),
                  maxWidth: 480,
                ),
                child: Center(
                  child: Form(
                    key: _formKey,
                    autovalidateMode: _autovalidate,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'SpendWise',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in to see where your money went.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (state.error case final BankError error) ...[
                          LoginErrorBanner(error: error),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _email,
                          autofillHints: const [AutofillHints.email],
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          enabled: !state.submitting,
                          validator: emailValidator,
                          onChanged: (_) => _clearBanner(),
                          onFieldSubmitted: (_) =>
                              _passwordFocus.requestFocus(),
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            hintText: 'you@example.com',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          focusNode: _passwordFocus,
                          autofillHints: const [AutofillHints.password],
                          obscureText: _obscure,
                          enabled: !state.submitting,
                          textInputAction: TextInputAction.done,
                          validator: passwordValidator,
                          onChanged: (_) => _clearBanner(),
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            suffixIcon: IconButton(
                              // Icon-only, so it carries both a tooltip and
                              // the semantics label a screen reader reads.
                              tooltip:
                                  _obscure ? 'Show password' : 'Hide password',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _SubmitButton(
                          submitting: state.submitting,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Demo build: any email address, password '
                          '"password123".',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.submitting, required this.onPressed});

  final bool submitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: submitting ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (submitting) ...[
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
          ],
          // The label changes too: the spinner is never the only sign that
          // something is happening.
          Flexible(child: Text(submitting ? 'Signing in…' : 'Sign in')),
        ],
      ),
    );
  }
}

/// The failure banner. Renders [BankError.userMessage] — never the exception,
/// never a stack trace, never a raw code.
class LoginErrorBanner extends StatelessWidget {
  const LoginErrorBanner({super.key, required this.error});

  final BankError error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.error),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Colour is never the only signal: the icon and the wording say
            // "this went wrong" on their own.
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error.userMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
