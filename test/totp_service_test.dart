import 'package:flutter_test/flutter_test.dart';

import 'package:cipherbook/services/totp_service.dart';

void main() {
  test('generates RFC 6238 SHA1 vector', () async {
    const service = TotpService();
    final result = await service.generate(
      'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
      timestamp: DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true),
    );

    expect(result.code, '287082');
    expect(result.secondsRemaining, 1);
  });

  test('reads digits and period from otpauth uri', () async {
    const service = TotpService();
    final result = await service.generate(
      'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&issuer=Example&digits=8&period=60',
      timestamp: DateTime.fromMillisecondsSinceEpoch(120000, isUtc: true),
    );

    expect(result.code.length, 8);
    expect(result.periodSeconds, 60);
    expect(result.secondsRemaining, 60);
  });

  test('rejects invalid secret', () async {
    const service = TotpService();

    expect(
      service.generate('***'),
      throwsArgumentError,
    );
  });

  test('rejects invalid otpauth settings', () async {
    const service = TotpService();

    expect(
      service.generate(
        'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&digits=0&period=30',
      ),
      throwsArgumentError,
    );
  });
}
