-- DEMO/TEST SEED ONLY -- never run against a shared, staging or production database.
-- Adds the selfie-check stage: a TENANT NATIVE_CAPTURE stage with native_handler `liveness_capture`
-- (the backend serializes it to a `kneth_liveness_capture` widget). Its key, `selfie_liveness`, is also
-- what the app maps to the `profile_picture` document kind for the captured final image
-- (lib/features/sync/domain/document_kind_mapping.dart). NOTES.md, "Device-attested liveness".
-- Run once, on top of tool/seed_stac_fixtures.sql (and the other tool/seed_stac_*.sql):
--   docker cp tool/seed_stac_liveness.sql postgres:/tmp/ && \
--   docker exec postgres psql -U onboarding -d onboarding -v ON_ERROR_STOP=1 -f /tmp/seed_stac_liveness.sql
-- then delete the resolved-config cache key (redis: config:resolved:*) and run tool/record_stac_fixtures.sh.
BEGIN;
INSERT INTO config.stages(id,key,scope,workflow_id,stage_order,screen_type,skip_gap_check,created_at,updated_at,native_handler)
SELECT gen_random_uuid(),'selfie_liveness','TENANT',workflow_id,9,'NATIVE_CAPTURE',false,now(),now(),'liveness_capture'
FROM config.stages WHERE key='location';
COMMIT;
