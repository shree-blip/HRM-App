import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/auth/auth_controller.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/validation/validators.dart';

/// Combined Sign In / Sign Up screen, mobile-first. Mirrors the behaviour of
/// the React `Auth.tsx` (allowlist email check, readonly name autofill,
/// deactivation handling) with a clean tabbed mobile layout.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();

  final _loginEmail = TextEditingController();
  final _loginPassword = TextEditingController();

  final _signupEmail = TextEditingController();
  final _signupPassword = TextEditingController();
  final _signupConfirm = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();

  bool _obscureLogin = true;
  bool _obscureSignup = true;
  bool _busy = false;

  // Allowlist email-check state.
  Timer? _debounce;
  bool _emailChecking = false;
  bool? _emailValid;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    _signupEmail.addListener(_onSignupEmailChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _loginEmail.dispose();
    _loginPassword.dispose();
    _signupEmail.dispose();
    _signupPassword.dispose();
    _signupConfirm.dispose();
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  // ── Allowlist debounce (verify_signup_email) ─────────────
  void _onSignupEmailChanged() {
    _debounce?.cancel();
    final email = Validators.normalizeEmail(_signupEmail.text);
    if (email.isEmpty || Validators.email(email) != null) {
      setState(() {
        _emailValid = null;
        _emailError = null;
        _emailChecking = false;
      });
      return;
    }
    setState(() => _emailChecking = true);
    _debounce = Timer(const Duration(milliseconds: 700), () => _checkEmail(email));
  }

  Future<void> _checkEmail(String email) async {
    try {
      final result = await ref.read(authControllerProvider.notifier).verifySignupEmail(email);
      if (!mounted) return;
      if (!result.allowed) {
        setState(() {
          _emailValid = false;
          _emailChecking = false;
          _emailError = result.reason == 'already_used'
              ? 'This email is already registered. Please sign in instead.'
              : 'This email is not authorized to sign up. Please contact your VP or manager.';
        });
        return;
      }
      // Allowed — try to autofill the name from the directory.
      if (result.employeeId != null) {
        final name = await ref.read(authControllerProvider.notifier).employeeName(result.employeeId!);
        if (name != null && mounted) {
          _firstName.text = name.firstName;
          _lastName.text = name.lastName;
        }
      }
      if (!mounted) return;
      setState(() {
        _emailValid = true;
        _emailError = null;
        _emailChecking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _emailValid = false;
        _emailChecking = false;
        _emailError = 'Error checking email. Please try again.';
      });
    }
  }

  // ── Submit handlers ──────────────────────────────────────
  Future<void> _submitLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).signIn(
            _loginEmail.text,
            _loginPassword.text,
          );
      // On success the router redirects automatically.
    } on AccountDeactivatedException {
      _toast('Your account has been deactivated. Please contact your Admin or Executive.');
    } on AuthException catch (e) {
      final msg = e.message.contains('Invalid login credentials')
          ? 'Invalid email or password. Please try again.'
          : e.message;
      _toast(msg);
    } catch (e) {
      _toast('Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitSignup() async {
    if (_emailValid != true) {
      _toast(_emailError ?? 'This email is not authorized to sign up.');
      return;
    }
    if (!_signupFormKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).signUp(
            email: _signupEmail.text,
            password: _signupPassword.text,
            firstName: _firstName.text,
            lastName: _lastName.text,
          );
    } on AuthException catch (e) {
      final msg = e.message.contains('already registered')
          ? 'This email is already registered. Please sign in instead.'
          : e.message;
      _toast(msg);
    } catch (e) {
      _toast('Sign up failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Surface one-time rejection reasons (deactivated / not allowed).
    ref.listen<AuthRejection?>(
      authControllerProvider.select((s) => s.rejection),
      (_, rejection) {
        if (rejection == null) return;
        _toast(switch (rejection) {
          AuthRejection.accountDeactivated =>
            'Your account has been deactivated. Please contact your Admin or Executive.',
          AuthRejection.notAllowed =>
            'Your email is not authorized to access this system.',
        },);
        ref.read(authControllerProvider.notifier).clearRejection();
      },
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.slate900, AppColors.slate800, AppColors.slate900],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const _Header(),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      TabBar(
                        controller: _tabs,
                        tabs: const [Tab(text: 'Sign In'), Tab(text: 'Sign Up')],
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabs,
                          children: [
                            _buildLoginForm(),
                            _buildSignupForm(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Form(
        key: _loginFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _loginEmail,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'you@company.com',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: Validators.email,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _loginPassword,
              obscureText: _obscureLogin,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscureLogin ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureLogin = !_obscureLogin),
                ),
              ),
              validator: (v) => Validators.requiredField(v, label: 'Password'),
              onFieldSubmitted: (_) => _busy ? null : _submitLogin(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.push(Routes.forgotPassword),
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: _busy ? null : _submitLogin,
              child: _busy
                  ? const _BtnSpinner()
                  : const Text('Sign In'),
            ),
            const SizedBox(height: 12),
            _GoogleComingSoonButton(busy: _busy, onTap: _toast),
          ],
        ),
      ),
    );
  }

  Widget _buildSignupForm() {
    final valid = _emailValid == true;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Form(
        key: _signupFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _signupEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Work Email',
                hintText: 'you@company.com',
                prefixIcon: const Icon(Icons.mail_outline),
                suffixIcon: _emailSuffix(),
                errorText: _emailError,
              ),
              validator: Validators.email,
            ),
            const SizedBox(height: 16),
            if (valid) ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstName,
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'First Name'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastName,
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'Last Name'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _signupPassword,
                obscureText: _obscureSignup,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  helperText: 'Min 8 chars, upper, lower, number & special char',
                  helperMaxLines: 2,
                  suffixIcon: IconButton(
                    icon: Icon(_obscureSignup ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureSignup = !_obscureSignup),
                  ),
                ),
                validator: Validators.password,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _signupConfirm,
                obscureText: _obscureSignup,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) => Validators.confirmPassword(v, _signupPassword.text),
              ),
              const SizedBox(height: 20),
            ],
            FilledButton(
              onPressed: (_busy || !valid) ? null : _submitSignup,
              child: _busy ? const _BtnSpinner() : const Text('Create Account'),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _emailSuffix() {
    if (_emailChecking) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_emailValid == true) {
      return const Icon(Icons.check_circle, color: AppColors.success);
    }
    if (_emailValid == false) {
      return const Icon(Icons.error_outline, color: AppColors.destructive);
    }
    return null;
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Image.asset('assets/images/focus-logo.png', width: 64, height: 64),
          const SizedBox(height: 10),
          const Text(
            'FOCUS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            'Human Resource Management',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _BtnSpinner extends StatelessWidget {
  const _BtnSpinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
      );
}

/// Placeholder for Google OAuth (deferred to a later phase per the plan).
class _GoogleComingSoonButton extends StatelessWidget {
  const _GoogleComingSoonButton({required this.busy, required this.onTap});
  final bool busy;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: busy ? null : () => onTap('Google sign-in is coming in a later phase.'),
      icon: const Icon(Icons.g_mobiledata, size: 28),
      label: const Text('Continue with Google'),
    );
  }
}
