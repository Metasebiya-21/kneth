-- Adds the `length_rules` stage (min_length / max_length fixtures) to the real
-- dev workflow, on top of tool/seed_stac_fixtures.sql. Backs the length-bound
-- parity checks (STAC_MIGRATION_SCOPING.md section 13). Run once:
--   docker cp tool/seed_stac_length_rules.sql postgres:/tmp/ && \
--   docker exec postgres psql -U onboarding -d onboarding -v ON_ERROR_STOP=1 -f /tmp/seed_stac_length_rules.sql
-- then delete the resolved-config cache key and run tool/record_stac_fixtures.sh.
BEGIN;
INSERT INTO config.stages(id,key,scope,workflow_id,stage_order,screen_type,skip_gap_check,created_at,updated_at,native_handler)
SELECT gen_random_uuid(),'length_rules','TENANT',workflow_id,5,'GENERIC_FORM',false,now(),now(),NULL
FROM config.stages WHERE key='location';

INSERT INTO config.fields(id,stage_id,key,field_type,input_mode,options,dynamic_config,validation,regex,depends_on,conditional_dependency,created_at,updated_at,resolves_at_fetch_time)
SELECT gen_random_uuid(), s.id, v.key, 'TEXT', 'FREE', NULL, NULL, v.val::jsonb, NULL, '[]'::jsonb, NULL, now(), now(), false
FROM config.stages s, (VALUES
  ('reference_code', '{"min_length": 3, "max_length": 6}'),
  ('tin_number',     '{"min_length": 5, "max_length": 10}'),
  ('notes',          NULL)
) AS v(key,val) WHERE s.key='length_rules';

INSERT INTO config.field_policy_overlays(id,field_id,client_id,is_required,is_hidden,display_order,created_at,updated_at)
SELECT gen_random_uuid(), f.id, 'e8ce7cac-22fb-4858-8328-bd62297c7e75', v.req, false, v.ord, now(), now()
FROM config.fields f JOIN config.stages s ON s.id=f.stage_id
JOIN (VALUES ('reference_code',true,1),('tin_number',false,2),('notes',false,3)) AS v(key,req,ord)
  ON v.key=f.key WHERE s.key='length_rules';
COMMIT;
