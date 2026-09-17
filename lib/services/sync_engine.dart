import 'api_client.dart';
import 'sync_status.dart';

/// Uploads a completed case through [ApiClient], reporting progress as a
/// stream of [SyncStatus]. A real implementation would poll or listen for
/// server-sent events instead of a fixed step list, but callers only ever
/// see the stream, so that swap won't touch any UI code.
class SyncEngine {
  final ApiClient apiClient;

  const SyncEngine({required this.apiClient});

  Stream<SyncStatus> sync({
    required Map<String, dynamic> values,
    required List<String> mediaFilePaths,
  }) async* {
    const totalSteps = 3;
    try {
      yield const SyncUploading(step: 1, totalSteps: totalSteps, label: 'Uploading case data');
      await apiClient.uploadCaseData(values);

      yield const SyncUploading(step: 2, totalSteps: totalSteps, label: 'Uploading media');
      await apiClient.uploadMedia(mediaFilePaths);

      yield const SyncUploading(step: 3, totalSteps: totalSteps, label: 'Processing');
      await apiClient.finalizeCase();

      yield const SyncSucceeded();
    } catch (e) {
      yield SyncFailed(e.toString());
    }
  }
}
