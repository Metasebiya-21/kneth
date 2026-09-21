import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/services/auth_token_provider.dart';

void main() {
  test('DevAuthTokenProvider returns null when never given a token', () {
    final provider = DevAuthTokenProvider();

    expect(provider.currentToken(), isNull);
  });

  test('DevAuthTokenProvider returns whatever token it was constructed or set with', () {
    final provider = DevAuthTokenProvider(token: 'abc');
    expect(provider.currentToken(), 'abc');

    provider.token = 'xyz';
    expect(provider.currentToken(), 'xyz');

    provider.token = null;
    expect(provider.currentToken(), isNull);
  });
}
