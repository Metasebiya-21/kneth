"""Emits Stac JSON for the fixtures of the OLD tests being ported (flow_screen_test,
dynamic_cascade_integration_test), using the backend's REAL serializer
(app.case.adapters.inbound.stac_manifest) — not hand-written."""
import json, sys
from app.case.domain.ports import ManifestField, ManifestStage
from app.case.adapters.inbound.stac_manifest import manifest_stage_to_stac

def f(key, ft, im, **kw):
    return ManifestField(key=key, field_type=ft, input_mode=im, is_required=kw.pop("req", False),
                         is_hidden=kw.pop("hidden", False), depends_on=kw.pop("dep", []),
                         conditional_dependency=kw.pop("cond", None), **kw)

stages = {
    # dynamic_cascade_integration_test's _cascadeStage
    "location": ManifestStage(key="location", scope="TENANT", screen_type="GENERIC_FORM", skip_gap_check=False, fields=[
        f("region", "SELECT", "ENUM", req=True, order=1,
          options=[{"label": "Addis Ababa", "value": "addis_ababa"}, {"label": "Oromia", "value": "oromia"}]),
        f("district", "SELECT", "DYNAMIC", req=True, order=2, dep=["region"],
          dynamic_config={"endpoint": "/options/regions/{region}/districts", "method": "GET"}),
    ]),
    # flow_screen_test's stages
    "stage_a": ManifestStage(key="stage_a", scope="TENANT", screen_type="GENERIC_FORM", skip_gap_check=False, fields=[]),
    "stage_b": ManifestStage(key="stage_b", scope="TENANT", screen_type="NATIVE_CAPTURE", skip_gap_check=False, fields=[],
                             native_handler="unrecognized_handler"),
}
# FakeApiClient's default three-stage flow (test/support/fake_api_client.dart): a form stage with a
# required field, a photo stage, and a form stage with an optional field.
default_flow = [
    ManifestStage(key="stage_a", scope="TENANT", screen_type="GENERIC_FORM", skip_gap_check=False,
                  fields=[f("name", "TEXT", "FREE", req=True, order=1)]),
    ManifestStage(key="stage_b", scope="TENANT", screen_type="NATIVE_CAPTURE", skip_gap_check=False, fields=[],
                  native_handler="photo_capture"),
    ManifestStage(key="stage_c", scope="TENANT", screen_type="GENERIC_FORM", skip_gap_check=False,
                  fields=[f("email", "TEXT", "FREE", order=1)]),
]
out = {k: manifest_stage_to_stac(v) for k, v in stages.items()}
out["fake_default_stages"] = [manifest_stage_to_stac(v) for v in default_flow]
json.dump(out, sys.stdout, indent=2)
