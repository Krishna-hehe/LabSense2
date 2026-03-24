import 'package:flutter_test/flutter_test.dart';
import 'package:clear_health/core/services/input_validation_service.dart';

void main() {
  late InputValidationService validator;

  setUp(() {
    validator = InputValidationService();
  });

  group('InputValidationService Tests', () {
    test('validateEmail returns null for valid email', () {
      expect(validator.validateEmail('test@example.com'), isNull);
    });

    test('validateEmail returns error for invalid email', () {
      expect(validator.validateEmail('invalid-email'), isNotNull);
      expect(validator.validateEmail(''), isNotNull);
      expect(validator.validateEmail(null), isNotNull);
    });

    test('validatePassword enforces strong password policy', () {
      expect(validator.validatePassword('short'), isNotNull);
      expect(validator.validatePassword('longenoughpassword'), isNotNull);
      expect(validator.validatePassword('Longenoughpassword'), isNotNull);
      expect(validator.validatePassword('Longenough1'), isNotNull);
      expect(validator.validatePassword('password123'), isNotNull);
      expect(validator.validatePassword('Str0ng!Pass1'), isNull);
    });

    test('sanitizeInput removes script tags', () {
      const input = 'Hello <script>alert("xss")</script> World';
      const expected = 'Hello  World';
      expect(validator.sanitizeInput(input), expected);
    });

    test('sanitizeInput removes basic HTML tags', () {
      const input = '<b>Bold</b> Text';
      const expected = 'Bold Text';
      expect(validator.sanitizeInput(input), expected);
    });

    // NEW REQUIREMENTS

    test('validateName allows only valid characters', () {
      // Expecting a new method validateName
      // Should allow letters, spaces, hyphens
      expect(validator.validateName('John Doe'), isNull);
      expect(validator.validateName('Mary-Jane'), isNull);
      expect(validator.validateName('John123'), isNotNull); // No numbers
      expect(validator.validateName('John@Doe'), isNotNull); // No special chars
    });

    test('containsSqlInjection detects risk patterns', () {
      // Expecting a new method containsSqlInjection
      expect(validator.containsSqlInjection('DROP TABLE users'), isTrue);
      expect(validator.containsSqlInjection('SELECT * FROM data'), isTrue);
      expect(validator.containsSqlInjection('UNION SELECT'), isTrue);
      expect(validator.containsSqlInjection('normal text'), isFalse);
      expect(
        validator.containsSqlInjection('Mr. O\'Neil'),
        isFalse,
      ); // Should handle escaped quotes or be smart
    });
  });
}

