import 'package:flutter/material.dart';

import 'package:sdui_demo/features/liveness/presentation/liveness_launcher.dart';
import 'package:sdui_demo/features/native_capture/domain/captured_media.dart';
import 'package:sdui_demo/features/native_capture/domain/media_storage_repository.dart';
import 'package:sdui_demo/features/stac_rendering/presentation/knet_stac_scope.dart';
import 'package:sdui_demo/features/stac_rendering/presentation/stac_stage_screen.dart';
import 'package:sdui_demo/services/api_client.dart';

import '../../support/fake_api_client.dart';

class FakeMediaStorageRepository implements MediaStorageRepository {
  final List<String> persistedCopies = [];
  final List<List<int>> persistedBytes = [];
  final List<String> deleted = [];
  int _n = 0;

  @override
  Future<CapturedMedia> persistCopy({required String sourcePath, required String prefix, required CaptureType type}) async {
    persistedCopies.add(sourcePath);
    return CapturedMedia(filePath: '/fake/captures/${prefix}_${++_n}.jpg', type: type, capturedAt: DateTime(2026));
  }

  @override
  Future<CapturedMedia> persistBytes({
    required List<int> bytes,
    required String prefix,
    required CaptureType type,
    String ext = 'png',
  }) async {
    persistedBytes.add(bytes);
    return CapturedMedia(filePath: '/fake/captures/${prefix}_${++_n}.$ext', type: type, capturedAt: DateTime(2026));
  }

  @override
  Future<void> deleteFile(String filePath) async => deleted.add(filePath);
}

/// Pumps a [StacStageScreen] for [widgetJson]; [submitted] collects what
/// Continue hands to `onSubmit`.
Widget stacStageApp({
  required Map<String, dynamic> widgetJson,
  required List<Map<String, dynamic>> submitted,
  ApiClient? apiClient,
  Map<String, dynamic> initialValues = const {},
  MediaStorageRepository? media,
  PickPhoto? pickPhoto,
  CaptureLiveness? captureLiveness,
  String clientId = 'client-1',
  String caseId = 'case-1',
  String workflowId = 'workflow-1',
}) {
  return MaterialApp(
    home: StacStageScreen(
      title: 'Stage',
      progressLabel: 'Step 01',
      widgetJson: widgetJson,
      initialValues: initialValues,
      onSubmit: (values, {remembered = const {}}) => submitted.add(values),
      apiClient: apiClient ?? FakeApiClient(),
      clientId: clientId,
      caseId: caseId,
      workflowId: workflowId,
      mediaRepository: media ?? FakeMediaStorageRepository(),
      pickPhoto: pickPhoto,
      captureLiveness: captureLiveness,
    ),
  );
}
