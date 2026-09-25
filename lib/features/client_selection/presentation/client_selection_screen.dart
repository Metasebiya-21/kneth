import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_dtos.dart';
import '../../../services/app_exception.dart';
import '../../../widgets/app_error_view.dart';
import '../../flow/presentation/flow_notifier.dart';

/// Agent-facing entry point, shown before [FlowScreen] ever starts: pick a
/// client, then a workflow for that client, then hand both ids to
/// [onSelected] — which is what actually constructs the `FlowManifest` and
/// moves on (see main.dart). This screen makes no decision about *what*
/// happens after a workflow is picked; it only answers "which client, which
/// workflow."
///
/// Presentation-only — no `domain/`, no `data/`, no feature-owned
/// repository. Investigated rather than assumed (see NOTES.md's Phase 2):
/// `fetchClients`/`fetchWorkflows` already live on the shared `ApiClient`
/// interface, not on anything this feature would own, and there is no real
/// decision-making here to relocate into a use case — listing and picking
/// is mechanical forwarding, the same test every other feature in this
/// migration applied before deciding whether to add a layer. This mirrors
/// `StacFlowStageScreen`, which already reads `ApiClient` directly from
/// presentation/ for the same reason: no domain abstraction is being hidden
/// by interposing one.
///
/// Reads `apiClientProvider` directly (no nested `ProviderScope` of its
/// own) — the same deliberate deviation flow's own screens make: this
/// screen's dependency doesn't vary per instance, so it uses the root
/// override from main.dart, exactly like `FlowScreen`/
/// `StacFlowStageScreen` already do.
class ClientSelectionScreen extends ConsumerStatefulWidget {
  final void Function(String clientId, String workflowId) onSelected;

  const ClientSelectionScreen({super.key, required this.onSelected});

  @override
  ConsumerState<ClientSelectionScreen> createState() => _ClientSelectionScreenState();
}

class _ClientSelectionScreenState extends ConsumerState<ClientSelectionScreen> {
  List<ClientSummaryDto>? _clients;
  AppException? _clientsError;

  ClientSummaryDto? _selectedClient;
  List<WorkflowSummaryDto>? _workflows;
  AppException? _workflowsError;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    setState(() {
      _clients = null;
      _clientsError = null;
    });
    try {
      final clients = await ref.read(apiClientProvider).fetchClients();
      if (!mounted) return;
      setState(() => _clients = clients);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _clientsError = e);
    }
  }

  Future<void> _selectClient(ClientSummaryDto client) async {
    setState(() {
      _selectedClient = client;
      _workflows = null;
      _workflowsError = null;
    });
    try {
      final workflows = await ref.read(apiClientProvider).fetchWorkflows(client.id);
      if (!mounted) return;
      setState(() => _workflows = workflows);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _workflowsError = e);
    }
  }

  void _backToClients() {
    setState(() {
      _selectedClient = null;
      _workflows = null;
      _workflowsError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedClient = _selectedClient;
    return Scaffold(
      appBar: AppBar(
        title: Text(selectedClient == null ? 'Select a client' : selectedClient.name),
        leading: selectedClient == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _backToClients),
      ),
      body: selectedClient == null ? _buildClientsBody() : _buildWorkflowsBody(selectedClient),
    );
  }

  Widget _buildClientsBody() {
    final error = _clientsError;
    if (error != null) {
      return Center(child: AppErrorView(error: error, onRetry: _loadClients));
    }
    final clients = _clients;
    if (clients == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (clients.isEmpty) {
      return const Center(child: Text('No clients are assigned to this agent yet.'));
    }
    return ListView.builder(
      itemCount: clients.length,
      itemBuilder: (context, index) {
        final client = clients[index];
        return ListTile(
          title: Text(client.name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _selectClient(client),
        );
      },
    );
  }

  Widget _buildWorkflowsBody(ClientSummaryDto client) {
    final error = _workflowsError;
    if (error != null) {
      return Center(child: AppErrorView(error: error, onRetry: () => _selectClient(client)));
    }
    final workflows = _workflows;
    if (workflows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (workflows.isEmpty) {
      return const Center(child: Text('No workflows are configured for this client yet.'));
    }
    return ListView.builder(
      itemCount: workflows.length,
      itemBuilder: (context, index) {
        final workflow = workflows[index];
        return ListTile(
          title: Text(workflow.name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => widget.onSelected(client.id, workflow.id),
        );
      },
    );
  }
}
