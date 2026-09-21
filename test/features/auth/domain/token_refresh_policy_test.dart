import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/auth/domain/auth_token.dart';
import 'package:sdui_demo/features/auth/domain/token_refresh_policy.dart';

AuthToken _tokenExpiringIn(Duration d) => AuthToken(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(d),
    );

void main() {
  test('null token never needs refreshing', () {
    expect(shouldRefresh(null), isFalse);
  });

  test('a token well outside the buffer does not need refreshing', () {
    final token = _tokenExpiringIn(const Duration(minutes: 30));
    expect(shouldRefresh(token, buffer: const Duration(minutes: 2)), isFalse);
  });

  test('a token inside the buffer needs refreshing', () {
    final token = _tokenExpiringIn(const Duration(seconds: 30));
    expect(shouldRefresh(token, buffer: const Duration(minutes: 2)), isTrue);
  });

  test('an already-expired token needs refreshing', () {
    final token = _tokenExpiringIn(const Duration(minutes: -5));
    expect(shouldRefresh(token, buffer: const Duration(minutes: 2)), isTrue);
  });
}
