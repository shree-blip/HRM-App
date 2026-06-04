import 'package:form_builder_validators/form_builder_validators.dart';

/// Form validators mirroring the React app's Zod schemas in `Auth.tsx`.
///
/// Built on `form_builder_validators` (the chosen form-validation package),
/// usable directly as `TextFormField.validator`.
class Validators {
  const Validators._();

  static String normalizeEmail(String email) => email.trim().toLowerCase();

  /// `z.string().email()`
  static String? email(String? value) => FormBuilderValidators.compose([
        FormBuilderValidators.required(errorText: 'Email is required'),
        FormBuilderValidators.email(
          errorText: 'Please enter a valid email address',
        ),
      ])(value);

  /// React passwordSchema: min 8, upper, lower, number, special char.
  /// Implemented manually (rather than via `FormBuilderValidators.match`)
  /// so it is independent of validator-package version differences.
  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
      return 'Password must contain at least one special character';
    }
    return null;
  }

  /// Login password: presence only (don't re-validate complexity on login).
  static String? requiredField(String? value, {String label = 'This field'}) =>
      FormBuilderValidators.required(errorText: '$label is required')(value);

  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != original) return "Passwords don't match";
    return null;
  }
}
