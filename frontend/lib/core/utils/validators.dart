/// Shared form-field validators, kept in one place so every screen enforces
/// the same rules instead of re-deriving (and drifting from) them.
class Validators {
  Validators._();

  static final RegExp _indianMobile = RegExp(r'^[6-9]\d{9}$');

  /// Validates an Indian mobile number: exactly 10 digits, numeric only,
  /// starting 6-9. Returns an error message, or null when valid.
  static String? phone(String? value, {bool required = true}) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return required ? 'Please enter a valid 10-digit mobile number.' : null;
    }
    if (!_indianMobile.hasMatch(trimmed)) {
      return 'Please enter a valid 10-digit mobile number.';
    }
    return null;
  }
}
