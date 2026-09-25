import 'package:flutter_test/flutter_test.dart';

import 'package:sdui_demo/features/sync/domain/document_kind_mapping.dart';

void main() {
  test('individual kinds (and the consent_signature override) target the individual record', () {
    expect(documentTargetForStageId('identification_card'),
        const DocumentTarget('identification_card', DocumentOwner.individual));
    expect(documentTargetForStageId('profile_picture'), const DocumentTarget('profile_picture', DocumentOwner.individual));
    expect(documentTargetForStageId('consent_signature'), const DocumentTarget('signature', DocumentOwner.individual));
  });

  test('the liveness stage\'s image maps to profile_picture, an individual kind', () {
    expect(documentTargetForStageId('selfie_liveness'), const DocumentTarget('profile_picture', DocumentOwner.individual));
  });

  test('all five business kinds target the business record, each as its own stage id', () {
    for (final kind in [
      'trade_license',
      'business_image',
      'corporate_governance_document',
      'memorandum_of_association',
      'article_of_association',
    ]) {
      expect(documentTargetForStageId(kind), DocumentTarget(kind, DocumentOwner.business), reason: kind);
    }
  });

  test('a stage with no confirmed kind has no target (callers must fail loudly)', () {
    expect(documentTargetForStageId('some_unmapped_stage'), isNull);
    expect(documentKindForStageId('some_unmapped_stage'), isNull);
  });
}
