import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:cipherbook/services/password_generator_service.dart';

void main() {
  test('generates a password with expected length and character classes', () {
    final generator = PasswordGeneratorService(random: Random(7));
    final password = generator.generate(length: 16);

    expect(password.length, 16);
    expect(password.contains(RegExp(r'[a-z]')), isTrue);
    expect(password.contains(RegExp(r'[A-Z]')), isTrue);
    expect(password.contains(RegExp(r'[2-9]')), isTrue);
    expect(password.contains(RegExp(r'[!@#\$%\^&*\(\)\-_=+\[\]\{\}\?]')), isTrue);
  });

  test('rejects short generated passwords', () {
    final generator = PasswordGeneratorService(random: Random(1));

    expect(
      () => generator.generate(length: 6),
      throwsArgumentError,
    );
  });
}
