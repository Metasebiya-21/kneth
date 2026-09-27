import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'debug/network_log.dart';
import 'debug/network_log_viewer.dart';
import 'features/auth/data/backend_auth_repository_impl.dart';
import 'features/auth/presentation/auth_notifier.dart';
import 'features/auth/presentation/change_password_screen.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/client_selection/presentation/client_selection_screen.dart';
import 'features/flow/data/flow_repository_impl.dart';
import 'features/flow/domain/flow_manifest.dart';
import 'features/flow/domain/flow_repository.dart';
import 'features/flow/presentation/flow_notifier.dart';
import 'features/flow/presentation/flow_screen.dart';
import 'features/flow/presentation/resume_choice_screen.dart';
import 'features/stac_rendering/presentation/stac_bootstrap.dart';
import 'services/api_client_impl.dart';
import 'services/api_http_client.dart';

/// The onboarding-platform backend. The only place this app's backend URL
/// is written down — auth and `ApiClientImpl` both use it. A literal, like
/// every earlier base URL here: this app has no environment/flavor mechanism.
///
/// The development Mac's Wi-Fi address, so a phone on the same network
/// reaches it without `adb reverse`. Needs the backend listening on the LAN
/// (`--host 0.0.0.0`, set in onboarding-platform's .vscode/launch.json), and
/// changes whenever the Mac's DHCP lease does. For an emulator, or a phone
/// using `adb reverse tcp:8000 tcp:8000`, use `http://localhost:8000`.
const backendBaseUrl = 'http://192.168.1.7:8000';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Registers the kneth_* Stac parsers. Cheap, and only used if the Stac
  // renderer is used (it is the only one).
  ensureKnethStacInitialized();

  // Every real network call goes through this one client. In a debug build
  // it's wrapped to record requests for the shake-to-open network log;
  // kDebugMode is a compile-time constant, so in a release build that
  // branch — and everything in lib/debug/ — is compiled out, not merely
  // unused (NOTES.md, "Auth through the backend's /auth proxy" -> "Release-
  // build check", including how to confirm it on a release binary).
  final http.Client httpClient = kDebugMode ? NetworkLogClient(http.Client(), debugNetworkLog) : http.Client();

  // Login, refresh, logout and the password flows all go through the
  // backend's own /auth routes (NOTES.md, "Auth through the backend's /auth
  // proxy"); the app no longer talks to Keycloak at all.
  final authRepository = BackendAuthRepositoryImpl(baseUrl: backendBaseUrl, client: httpClient);
  final authNotifier = AuthNotifier(authRepository);
  // Same cheap, local-only check flow's own saved-case lookup does before
  // runApp — reads secure storage once, synchronously deciding whether
  // the agent starts at LoginScreen or already has a session.
  await authNotifier.initialize();

  // The one ApiClient instance the whole app shares — flow's own
  // FlowRepositoryImpl uses it directly; other features (sync,
  // native_capture) still get it via FlowSession.apiClient, exactly as
  // before this migration.
  //
  // The real backend (switched on 2026-09-27; before that MockApiClient ran
  // here and only /auth calls ever went over the network). Same logged
  // http.Client as auth, so every call shows up in the debug network log.
  // A real 401 signs the agent out via onUnauthorized. MockApiClient is kept
  // in api_client.dart for tests and offline demos: to go back, replace this
  // with `final apiClient = MockApiClient();`.
  final apiClient = ApiClientImpl(
    httpClient: ApiHttpClient(baseUrl: backendBaseUrl, client: httpClient),
    authTokenProvider: authRepository, // implements AuthTokenProvider too
    onUnauthorized: authNotifier.forceLogout,
  );
  final flowRepository = FlowRepositoryImpl(apiClient: apiClient);

  runApp(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        flowRepositoryProvider.overrideWithValue(flowRepository),
        authRepositoryProvider.overrideWithValue(authRepository),
        authNotifierProvider.overrideWith((ref) => authNotifier),
      ],
      // Root scope for the flow, auth and client-selection providers overridden above.
      child: SduiDemoApp(flowRepository: flowRepository),
    ),
  );
}

/// Reactively swaps between [LoginScreen] and [ClientSelectionScreen]
/// based on `authNotifierProvider` — see NOTES.md's Phase 1. The `key` on
/// [MaterialApp] itself (not just on `home`) is deliberate, not
/// decorative: `MaterialApp.home` only establishes the *initial* route of
/// its internal `Navigator` — changing it on a later rebuild does **not**
/// re-push anything if the agent has already navigated deeper (a
/// well-known Flutter gotcha). Keying the whole `MaterialApp` by a coarse
/// "logged in vs. not" category forces Flutter to discard and rebuild the
/// entire element subtree — Navigator, full back-stack and all — exactly
/// when that category changes, which is what actually resets navigation
/// back to a bare `LoginScreen` on logout (including a forced one, from
/// `ApiClientImpl.onUnauthorized`) or forward to `ClientSelectionScreen`
/// on login, regardless of how many screens were pushed in between.
/// `AuthLoggingIn`/`AuthFailed` share `AuthLoggedOut`'s key on purpose —
/// they're substates of "still on the login screen," and `LoginScreen`
/// itself watches the provider to render them, so the whole app must not
/// remount (and lose the typed username/password) between them.
class SduiDemoApp extends ConsumerWidget {
  final FlowRepository flowRepository;

  const SduiDemoApp({super.key, required this.flowRepository});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    return MaterialApp(
      key: ValueKey(_navigationEpoch(authState)),
      title: 'SDUI demo',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      // Debug builds only (a compile-time constant — see main()).
      builder: kDebugMode ? (context, child) => NetworkLogShakeListener(log: debugNetworkLog, child: child!) : null,
      home: switch (authState) {
        AuthCheckingStorage() => const Scaffold(body: Center(child: CircularProgressIndicator())),
        AuthLoggedOut() || AuthLoggingIn() || AuthFailed() => const LoginScreen(),
        AuthPasswordChangeRequired() => const ChangePasswordScreen(),
        // A Builder, so _startFlow gets a context BELOW MaterialApp's
        // Navigator. This build method's own `context` is above it — pushing
        // with that one crashed ("context that does not include a
        // Navigator") the first time a workflow was tapped on a device.
        AuthLoggedIn() => Builder(
            builder: (homeContext) => ClientSelectionScreen(
              onSelected: (clientId, workflowId) => _startFlow(homeContext, clientId, workflowId),
            ),
          ),
      },
    );
  }

  String _navigationEpoch(AuthState state) => switch (state) {
        AuthCheckingStorage() => 'checking',
        AuthLoggedOut() || AuthLoggingIn() || AuthFailed() => 'loggedOut',
        // Its own epoch: `home` switching between LoginScreen and this is a
        // real screen change, which only a remount reliably shows (see
        // this class's doc comment). Its own submitting/error substates
        // stay in this epoch, so typed passwords survive them.
        AuthPasswordChangeRequired() => 'passwordChange',
        AuthLoggedIn() => 'loggedIn',
      };

  Future<void> _startFlow(BuildContext context, String clientId, String workflowId) async {
    final manifest = FlowManifest(workflowId: workflowId, clientId: clientId);
    // A cheap, local-only check (no network) for whether there's a saved
    // case to offer resuming — the fuller "resume, refreshing if stale"
    // flow (LoadFlowCaseUseCase) only runs once the agent actually chooses
    // to resume, inside FlowScreen — see NOTES.md for why the check is
    // split this way.
    final savedCaseState = await flowRepository.loadSavedCaseState(manifest.workflowId);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => savedCaseState != null
            ? ResumeChoiceScreen(manifest: manifest, savedCaseState: savedCaseState)
            : FlowScreen(manifest: manifest),
      ),
    );
  }
}
