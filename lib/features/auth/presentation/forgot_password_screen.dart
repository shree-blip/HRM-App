import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/validation/validators.dart';
import 'widgets/auth_widgets.dart';

/// Mirrors React `ForgotPassword.tsx`: send a reset email, then show a
/// confirmation state.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).resetPassword(_email.text);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        showAuthSnack(context, 'Error: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthGradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    tooltip: 'Back',
                  ),
                ),
                const SizedBox(height: 8),
                const AuthBrandMark(),
                const SizedBox(height: 30),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: AuthCard(
                      child: _sent ? _buildSent() : _buildForm(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: AuthIconBadge(icon: Icons.lock_reset)),
          const SizedBox(height: 18),
          const AuthHeading(
            title: 'Reset your password',
            subtitle: "Enter your email and we'll send you a secure link to reset your password.",
          ),
          const SizedBox(height: 22),
          AuthTextField(
            controller: _email,
            label: 'Email Address',
            hint: 'you@company.com',
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: Validators.email,
            onFieldSubmitted: (_) => _busy ? null : _submit(),
          ),
          const SizedBox(height: 20),
          AuthPrimaryButton(
            label: 'Send Reset Link',
            busy: _busy,
            onPressed: _submit,
          ),
          const SizedBox(height: 6),
          AuthLinkButton(label: 'Back to Login', onPressed: () => context.pop()),
        ],
      ),
    );
  }

  Widget _buildSent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: AuthIconBadge(
            icon: Icons.mark_email_read_outlined,
            accent: Color(0xFF6EE7B7),
          ),
        ),
        const SizedBox(height: 18),
        const AuthHeading(
          title: 'Check your inbox',
          subtitle: 'Your reset link is on its way.',
        ),
        const SizedBox(height: 14),
        AuthMessage(
          text: "We've sent a reset link to ${_email.text}. "
              'Check your inbox (and spam folder).',
          isError: false,
        ),
        const SizedBox(height: 22),
        AuthOutlineButton(
          label: 'Send Again',
          icon: Icons.refresh,
          onPressed: () => setState(() => _sent = false),
        ),
        const SizedBox(height: 4),
        AuthLinkButton(label: 'Back to Login', onPressed: () => context.pop()),
      ],
    );
  }
}
