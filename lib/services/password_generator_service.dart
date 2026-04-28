import 'dart:math';

class PasswordGeneratorService {
  PasswordGeneratorService({Random? random})
      : _random = random ?? Random.secure();

  static const String _lower = 'abcdefghijkmnopqrstuvwxyz';
  static const String _upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const String _digits = '23456789';
  static const String _symbols = '!@#\$%^&*()-_=+[]{}?';

  final Random _random;

  String generate({
    int length = 20,
    bool includeUppercase = true,
    bool includeDigits = true,
    bool includeSymbols = true,
  }) {
    if (length < 8) {
      throw ArgumentError('密码长度至少为 8 位。');
    }

    final pools = <String>[_lower];
    if (includeUppercase) {
      pools.add(_upper);
    }
    if (includeDigits) {
      pools.add(_digits);
    }
    if (includeSymbols) {
      pools.add(_symbols);
    }

    final requiredChars = <String>[
      _pickFrom(_lower),
      if (includeUppercase) _pickFrom(_upper),
      if (includeDigits) _pickFrom(_digits),
      if (includeSymbols) _pickFrom(_symbols),
    ];

    final allChars = pools.join();
    final output = <String>[
      ...requiredChars,
      for (var i = requiredChars.length; i < length; i++) _pickFrom(allChars),
    ];
    output.shuffle(_random);
    return output.join();
  }

  String _pickFrom(String pool) => pool[_random.nextInt(pool.length)];
}
