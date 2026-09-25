-- DEMO/TEST SEED ONLY -- never run against a shared, staging or production database.
-- Adds the pieces a combined KYC+KYB submission with a BUSINESS document needs, on top of
-- tool/seed_stac_fixtures.sql (and the other tool/seed_stac_*.sql). NOTES.md, "Business document upload".
--   * `business_info`: a GLOBAL stage whose keys (business_type, business_name, tin) are the ones
--     SubmitCaseUseCase routes to CreateBusinessRecordUseCase (so submit returns business_record_id).
--     GLOBAL stages apply to every workflow of every client, so this changes the shared dev flow.
--   * `trade_license`: a TENANT NATIVE_CAPTURE/photo_capture stage. Its key is also the DocumentKind
--     the app uploads it as (a business kind -> POST /identity/business-records/{id}/documents/trade_license).
-- Run once:
--   docker cp tool/seed_stac_business_docs.sql postgres:/tmp/ && \
--   docker exec postgres psql -U onboarding -d onboarding -v ON_ERROR_STOP=1 -f /tmp/seed_stac_business_docs.sql
-- then delete the resolved-config cache key (redis: config:resolved:*) and run tool/record_stac_fixtures.sh.
BEGIN;
INSERT INTO config.stages(id,key,scope,workflow_id,stage_order,screen_type,skip_gap_check,created_at,updated_at,native_handler)
VALUES (gen_random_uuid(),'business_info','GLOBAL',NULL,7,'GENERIC_FORM',false,now(),now(),NULL);

INSERT INTO config.stages(id,key,scope,workflow_id,stage_order,screen_type,skip_gap_check,created_at,updated_at,native_handler)
SELECT gen_random_uuid(),'trade_license','TENANT',workflow_id,8,'NATIVE_CAPTURE',false,now(),now(),'photo_capture'
FROM config.stages WHERE key='location';

INSERT INTO config.fields(id,stage_id,key,field_type,input_mode,options,dynamic_config,validation,regex,depends_on,conditional_dependency,created_at,updated_at,resolves_at_fetch_time)
SELECT gen_random_uuid(), s.id, v.key, v.ft, v.im, v.opts::jsonb, NULL, NULL, NULL, '[]'::jsonb, NULL, now(), now(), false
FROM config.stages s, (VALUES
  ('business_type', 'SELECT', 'ENUM', '["registered","unregistered"]'),
  ('business_name', 'TEXT',   'FREE', NULL),
  ('tin',           'TEXT',   'FREE', NULL)
) AS v(key,ft,im,opts) WHERE s.key='business_info';

INSERT INTO config.field_policy_overlays(id,field_id,client_id,is_required,is_hidden,display_order,created_at,updated_at)
SELECT gen_random_uuid(), f.id, 'e8ce7cac-22fb-4858-8328-bd62297c7e75', v.req, false, v.ord, now(), now()
FROM config.fields f JOIN config.stages s ON s.id=f.stage_id
JOIN (VALUES ('business_type',true,1),('business_name',true,2),('tin',false,3)) AS v(key,req,ord) ON v.key=f.key
WHERE s.key='business_info';
COMMIT;
