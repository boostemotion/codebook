import 'package:cipherbook/presentation/app/frontend_flag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Prism frontend is enabled by default', () {
    expect(cipherbookFrontendV2, isTrue);
  });
}
