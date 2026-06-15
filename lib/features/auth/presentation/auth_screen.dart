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
import 'widgets/auth_widgets.dart';

/// Combined Sign In / Sign Up screen, mobile-first. Mirrors the behaviour of
/// the React `Auth.tsx` (allowlist email check, readonly name autofill,
/// deactivation handling) with a clean, premium card layout.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  // 0 = Sign In, 1 = Sign Up.
  int _mode = 0;

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

  void _toast(String message, {bool isError = true}) {
    if (!mounted) return;
    showAuthSnack(context, message, isError: isError);
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
      body: AuthGradientBackground(
        child: SafeArea(
          // Top-anchored + horizontally centred so the segmented switch never
          // shifts when the form height changes; the scroll view keeps it
          // keyboard-safe and overflow-free on small devices.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AuthBrandMark(),
                    const SizedBox(height: 30),
                    AuthCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AuthSegmentedSwitch(
                            index: _mode,
                            labels: const ['Sign In', 'Sign Up'],
                            onChanged: (i) => setState(() => _mode = i),
                          ),
                          const SizedBox(height: 24),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                            alignment: Alignment.topCenter,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: _mode == 0
                                  ? KeyedSubtree(
                                      key: const ValueKey('login'),
                                      child: _buildLoginForm(),
                                    )
                                  : KeyedSubtree(
                                      key: const ValueKey('signup'),
                                      child: _buildSignupForm(),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeading(
            title: 'Welcome back',
            subtitle: 'Sign in to continue to your Focus HRM workspace.',
          ),
          const SizedBox(height: 22),
          AuthTextField(
            controller: _loginEmail,
            label: 'Email',
            hint: 'you@company.com',
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: Validators.email,
          ),
          const SizedBox(height: 16),
          AuthTextField(
            controller: _loginPassword,
            label: 'Password',
            icon: Icons.lock_outline,
            obscureText: _obscureLogin,
            autofillHints: const [AutofillHints.password],
            suffix: IconButton(
              icon: Icon(_obscureLogin ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureLogin = !_obscureLogin),
            ),
            validator: (v) => Validators.requiredField(v, label: 'Password'),
            onFieldSubmitted: (_) => _busy ? null : _submitLogin(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: AuthLinkButton(
              label: 'Forgot password?',
              onPressed: () => context.push(Routes.forgotPassword),
            ),
          ),
          const SizedBox(height: 4),
          AuthPrimaryButton(
            label: 'Sign In',
            busy: _busy,
            onPressed: _submitLogin,
          ),
          const SizedBox(height: 18),
          const AuthOrDivider(),
          const SizedBox(height: 18),
          AuthOutlineButton(
            label: 'Continue with Google',
            icon: Icons.g_mobiledata,
            onPressed: _busy
                ? null
                : () => _toast(
                      'Google sign-in is coming in a later phase.',
                      isError: false,
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignupForm() {
    final valid = _emailValid == true;
    return Form(
      key: _signupFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeading(
            title: 'Create your account',
            subtitle: 'Sign up with your authorized work email to get started.',
          ),
          const SizedBox(height: 22),
          AuthTextField(
            controller: _signupEmail,
            label: 'Work Email',
            hint: 'you@company.com',
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            suffix: _emailSuffix(),
            errorText: _emailError,
            validator: Validators.email,
          ),
          const SizedBox(height: 16),
          if (valid) ...[
            Row(
              children: [
                Expanded(
                  child: AuthTextField(
                    controller: _firstName,
                    label: 'First Name',
                    icon: Icons.badge_outlined,
                    readOnly: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AuthTextField(
                    controller: _lastName,
                    label: 'Last Name',
                    readOnly: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AuthTextField(
              controller: _signupPassword,
              label: 'Password',
              icon: Icons.lock_outline,
              obscureText: _obscureSignup,
              helperText: 'Min 8 chars, upper, lower, number & special char',
              helperMaxLines: 2,
              suffix: IconButton(
                icon: Icon(_obscureSignup ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureSignup = !_obscureSignup),
              ),
              validator: Validators.password,
            ),
            const SizedBox(height: 16),
            AuthTextField(
              controller: _signupConfirm,
              label: 'Confirm Password',
              icon: Icons.lock_outline,
              obscureText: _obscureSignup,
              validator: (v) => Validators.confirmPassword(v, _signupPassword.text),
            ),
            const SizedBox(height: 22),
          ],
          AuthPrimaryButton(
            label: 'Create Account',
            busy: _busy,
            onPressed: valid ? _submitSignup : null,
          ),
        ],
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
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryDark),
        ),
      );
    }
    if (_emailValid == true) {
      return const Icon(Icons.check_circle, color: Color(0xFF6EE7B7));
    }
    if (_emailValid == false) {
      return const Icon(Icons.error_outline, color: Color(0xFFFF8A8A));
    }
    return null;
  }
}
