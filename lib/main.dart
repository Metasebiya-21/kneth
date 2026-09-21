import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/data/keycloak_auth_repository_impl.dart';
import 'features/auth/presentation/auth_notifier.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/client_selection/presentation/client_selection_screen.dart';
import 'features/flow/data/flow_repository_impl.dart';
import 'features/flow/domain/flow_manifest.dart';
import 'features/flow/domain/flow_repository.dart';
import 'features/flow/presentation/flow_notifier.dart';
import 'features/flow/presentation/flow_screen.dart';
import 'features/flow/presentation/resume_choice_screen.dart';
import 'services/api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Real Keycloak login, wired for real now (NOTES.md's Phase 1) — not a
  // commented-out alternative the way ApiClientImpl is below. Base URL
  // matches onboarding-platform's own .env.example default; realm/
  // clientId default to their own settings.py defaults too
  // ('onboarding'/'onboarding-platform'), confirmed against the actual
  // realm export, not guessed (see auth_repository.dart's doc comment).
  final authRepository = KeycloakAuthRepositoryImpl(keycloakBaseUrl: 'http://localhost:8080');
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
  // MockApiClient is what actually runs. ApiClientImpl (below, unused) is
  // the real implementation, built against onboarding-platform's confirmed
  // contract — see NOTES.md's "Building ApiClientImpl" section, including
  // what's still missing before it works end to end. Switching to it is a
  // deliberate one-line code change, on purpose — not a config flag that
  // could flip unintentionally. Not wired as live-but-unused code here
  // since an unused import/constructor would itself fail
  // `flutter analyze`:
  //
  //   import 'services/api_client_impl.dart';
  //   import 'services/api_http_client.dart';
  //   ...
  //   final apiClient = ApiClientImpl(
  //     httpClient: ApiHttpClient(baseUrl: 'http://localhost:8000'),
  //     authTokenProvider: authRepository, // implements AuthTokenProvider too
  //     onUnauthorized: authNotifier.forceLogout,
  //   );
  final apiClient = MockApiClient();
  final flowRepository = FlowRepositoryImpl(apiClient: apiClient);

  runApp(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        flowRepositoryProvider.overrideWithValue(flowRepository),
        authRepositoryProvider.overrideWithValue(authRepository),
        authNotifierProvider.overrideWith((ref) => authNotifier),
      ],
      // Also required by kifiya_rendering_engine's DynamicForm (a Riverpod
      // ConsumerWidget). Each GENERIC_FORM stage additionally nests its own
      // scoped override — see RenderingEngineStageScreen.
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
      home: switch (authState) {
        AuthCheckingStorage() => const Scaffold(body: Center(child: CircularProgressIndicator())),
        AuthLoggedOut() || AuthLoggingIn() || AuthFailed() => const LoginScreen(),
        AuthLoggedIn() => ClientSelectionScreen(
            onSelected: (clientId, workflowId) => _startFlow(context, clientId, workflowId),
          ),
      },
    );
  }

  String _navigationEpoch(AuthState state) => switch (state) {
        AuthCheckingStorage() => 'checking',
        AuthLoggedOut() || AuthLoggingIn() || AuthFailed() => 'loggedOut',
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
