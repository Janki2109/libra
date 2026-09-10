/// Shared form-field validators, kept in one place so every screen enforces
/// the same rules instead of re-deriving (and drifting from) them.
class Validators {
  Validators._();

  static final RegExp _indianMobile = RegExp(r'^[6-9]\d{9}$');
  static final RegExp _alphaSpace = RegExp(r'^[A-Za-z ]+$');
  static final RegExp _sixDigitPincode = RegExp(r'^\d{6}$');

  /// Letters and spaces only — no digits or special characters.
  static String? name(String? value, {bool required = true}) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return required ? 'Name is required' : null;
    }
    if (!_alphaSpace.hasMatch(trimmed)) {
      return 'Name can only contain letters and spaces.';
    }
    return null;
  }

  /// Exactly 6 numeric digits.
  static String? pincode(String? value, {bool required = true}) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return required ? 'Pincode is required' : null;
    }
    if (!_sixDigitPincode.hasMatch(trimmed)) {
      return 'Pincode must be exactly 6 digits.';
    }
    return null;
  }

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
