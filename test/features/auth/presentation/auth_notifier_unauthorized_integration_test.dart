// Confirms the actual wiring main.dart establishes (commented there,
// see ApiClientImpl construction: `onUnauthorized: authNotifier.forceLogout`)
// end to end: a real 401 reaching ApiClientImpl really does drive
// AuthNotifier back to AuthLoggedOut, not just that ApiClientImpl's own
// callback fires (api_client_impl_test.dart's own
// "onUnauthorized callback" group already covers that half in isolation,
// transport-mocked, with no AuthNotifier involved at all).
//
// The AuthTokenProvider handing ApiClientImpl its (valid-looking) token and
// the AuthRepository backing AuthNotifier are deliberately two separate
// fakes here, not one dual-purpose object the way BackendAuthRepositoryImpl
// is in production (NOTES.md's Phase 1) — what this test exercises is the
// callback plumbing between the two, which doesn't depend on them sharing a
// single underlying token store.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sdui_demo/features/auth/presentation/auth_notifier.dart';
import 'package:sdui_demo/services/api_client_impl.dart';
import 'package:sdui_demo/services/api_http_client.dart';
import 'package:sdui_demo/services/auth_token_provider.dart';

import '../../../support/fake_auth_repository.dart';

void main() {
  test('a real 401 reaching ApiClientImpl drives AuthNotifier.forceLogout, matching main.dart\'s wiring', () async {
    final authRepository = FakeAuthRepository();
    final notifier = AuthNotifier(authRepository);
    addTearDown(notifier.dispose);
    await notifier.login(username: 'agent1', password: 'secret');
    expect(notifier.state, isA<AuthLoggedIn>());

    final httpClient = ApiHttpClient(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        // The request really does carry a token — this is a genuine server
        // rejection (e.g. expired mid-flight), not the local no-token
        // check ApiClientImpl already handles before ever making a call.
        expect(request.headers['Authorization'], 'Bearer looks-valid');
        return http.Response(jsonEncode({'message': 'token expired'}), 401);
      }),
      baseBackoff: const Duration(milliseconds: 1),
    );
    final apiClient = ApiClientImpl(
      httpClient: httpClient,
      authTokenProvider: DevAuthTokenProvider(token: 'looks-valid'),
      // The exact wiring main.dart's own (commented) ApiClientImpl
      // construction uses.
      onUnauthorized: notifier.forceLogout,
    );

    await expectLater(apiClient.fetchClients(), throwsA(anything));

    expect(notifier.state, isA<AuthLoggedOut>());
    // forceLogout stops the background refresh loop too (see
    // auth_notifier.dart) — logout() itself was called on the repository as
    // part of that, not left half-done.
    expect(authRepository.logoutCallCount, 1);
  });
}
