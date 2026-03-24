class InputValidationService {
  static const Set<String> _commonWeakPasswords = {
    'password',
    'password123',
    '12345678',
    'qwerty123',
    'letmein',
    'admin123',
    'welcome123',
  };

  // Singleton pattern not strictly needed with Riverpod, but good for static access if needed

  /// Validates an email address
  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }
    // Basic email regex
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null; // Valid
  }

  /// Validates a password
  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 10) {
      return 'Password must be at least 10 characters';
    }
    if (!_hasUppercase(value)) {
      return 'Password must include at least one uppercase letter';
    }
    if (!_hasLowercase(value)) {
      return 'Password must include at least one lowercase letter';
    }
    if (!_hasDigit(value)) {
      return 'Password must include at least one number';
    }
    if (!_hasSpecial(value)) {
      return 'Password must include at least one special character';
    }
    if (_commonWeakPasswords.contains(value.toLowerCase())) {
      return 'Please choose a less common password';
    }
    return null;
  }

  /// Sanitizes generic text input for XSS prevention (basic)
  /// Removes <script> tags and html entities
  String sanitizeInput(String input) {
    var sanitized = input;
    // Remove script tags
    sanitized = sanitized.replaceAll(
      RegExp(r'<script.*?>.*?</script>', caseSensitive: false),
      '',
    );
    // Remove HTML tags (basic)
    sanitized = sanitized.replaceAll(RegExp(r'<[^>]*>'), '');
    return sanitized.trim();
  }

  /// Validates a numeric lab result
  String? validateLabValue(String? value) {
    if (value == null || value.isEmpty) {
      return 'Value is required';
    }
    final number = double.tryParse(value);
    if (number == null) {
      return 'Please enter a valid number';
    }
    if (number < 0) {
      return 'Value cannot be negative';
    }
    // Check for astronomical values (sanity check)
    if (number > 100000) {
      return 'Value seems seemingly high, please verify';
    }
    return null;
  }

  /// Validates generic required fields
  String? validateRequired(String? value, {String fieldName = 'Field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Validates a name (letters, spaces, hyphens only)
  String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Name is required';
    if (!RegExp(r'^[a-zA-Z\s-]+$').hasMatch(value)) {
      return 'Name must contain only letters, spaces, or hyphens';
    }
    return null;
  }

  /// Sanitizes a string for safe database insertion.
  /// Removes control characters and normalizes whitespace.
  String sanitizeForDb(String input, {int maxLength = 500}) {
    if (input.length > maxLength) {
      // Or handle this case as you see fit, e.g., truncate
      throw ArgumentError('Input exceeds maximum length of $maxLength characters.');
    }
    // Remove control characters, normalize whitespace
    return input.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
                .trim()
                .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Detects potential SQL injection patterns
  /// Returns true if risky patterns are found
  bool containsSqlInjection(String value) {
    final upper = value.toUpperCase();
    return upper.contains('DROP TABLE') ||
        upper.contains('SELECT *') ||
        upper.contains('UNION SELECT') ||
        upper.contains('DELETE FROM') ||
        upper.contains('UPDATE SET') ||
        upper.contains('INSERT INTO') ||
        upper.contains('WHERE 1=1');
  }

  bool _hasUppercase(String input) => input.contains(RegExp(r'[A-Z]'));
  bool _hasLowercase(String input) => input.contains(RegExp(r'[a-z]'));
  bool _hasDigit(String input) => input.contains(RegExp(r'\d'));
  bool _hasSpecial(String input) => input.contains(RegExp(r'[^A-Za-z0-9\s]'));
}
