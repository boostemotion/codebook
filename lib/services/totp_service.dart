import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class TotpResult {
  const TotpResult({
    required this.code,
    required this.periodSeconds,
    required this.secondsRemaining,
    required this.digits,
  });

  final String code;
  final int periodSeconds;
  final int secondsRemaining;
  final int digits;
}

class TotpService {
  const TotpService();

  Future<TotpResult> generate(
    String secretOrUri, {
    DateTime? timestamp,
  }) async {
    final config = _parseConfig(secretOrUri);
    final moment = (timestamp ?? DateTime.now()).toUtc();
    final seconds = moment.millisecondsSinceEpoch ~/ 1000;
    final counter = seconds ~/ config.periodSeconds;
    final secondsRemaining =
        config.periodSeconds - (seconds % config.periodSeconds);
    final counterBytes = ByteData(8)..setInt64(0, counter);
    final mac = await config.algorithm.calculateMac(
      counterBytes.buffer.asUint8List(),
      secretKey: SecretKey(config.secretBytes),
    );
    final code = _truncate(mac.bytes, config.digits);
    return TotpResult(
      code: code,
      periodSeconds: config.periodSeconds,
      secondsRemaining: secondsRemaining,
      digits: config.digits,
    );
  }

  _TotpConfig _parseConfig(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('TOTP secret is empty.');
    }

    if (trimmed.startsWith('otpauth://')) {
      final uri = Uri.parse(trimmed);
      final secret = uri.queryParameters['secret'];
      if (secret == null || secret.trim().isEmpty) {
        throw ArgumentError('TOTP URI does not contain a secret.');
      }
      final digits = int.tryParse(uri.queryParameters['digits'] ?? '') ?? 6;
      final period = int.tryParse(uri.queryParameters['period'] ?? '') ?? 30;
      if (digits <= 0 || period <= 0) {
        throw ArgumentError('TOTP digits and period must be positive.');
      }
      final algorithmName =
          (uri.queryParameters['algorithm'] ?? 'SHA1').toUpperCase();
      return _TotpConfig(
        secretBytes: _decodeBase32(secret),
        digits: digits,
        periodSeconds: period,
        algorithm: _algorithmForName(algorithmName),
      );
    }

    return _TotpConfig(
      secretBytes: _decodeBase32(trimmed),
      digits: 6,
      periodSeconds: 30,
      algorithm: Hmac.sha1(),
    );
  }

  Uint8List _decodeBase32(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final normalized = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (RegExp(r'[^A-Z2-7=]').hasMatch(normalized)) {
      throw ArgumentError('Invalid Base32 secret.');
    }
    final cleaned = normalized.replaceAll('=', '');
    if (cleaned.isEmpty) {
      throw ArgumentError('Invalid Base32 secret.');
    }

    var buffer = 0;
    var bitsLeft = 0;
    final bytes = <int>[];

    for (final rune in cleaned.runes) {
      final value = alphabet.indexOf(String.fromCharCode(rune));
      if (value < 0) {
        throw ArgumentError('Invalid Base32 secret.');
      }
      buffer = (buffer << 5) | value;
      bitsLeft += 5;
      while (bitsLeft >= 8) {
        bitsLeft -= 8;
        bytes.add((buffer >> bitsLeft) & 0xFF);
      }
    }

    return Uint8List.fromList(bytes);
  }

  String _truncate(List<int> macBytes, int digits) {
    final offset = macBytes.last & 0x0F;
    final binary = ((macBytes[offset] & 0x7F) << 24) |
        ((macBytes[offset + 1] & 0xFF) << 16) |
        ((macBytes[offset + 2] & 0xFF) << 8) |
        (macBytes[offset + 3] & 0xFF);
    final modulo = pow(10, digits).toInt();
    final otp = binary % modulo;
    return otp.toString().padLeft(digits, '0');
  }

  MacAlgorithm _algorithmForName(String name) {
    switch (name) {
      case 'SHA1':
        return Hmac.sha1();
      case 'SHA256':
        return Hmac.sha256();
      case 'SHA512':
        return Hmac.sha512();
      default:
        throw ArgumentError('Unsupported TOTP algorithm: $name');
    }
  }
}

class _TotpConfig {
  const _TotpConfig({
    required this.secretBytes,
    required this.digits,
    required this.periodSeconds,
    required this.algorithm,
  });

  final Uint8List secretBytes;
  final int digits;
  final int periodSeconds;
  final MacAlgorithm algorithm;
}
