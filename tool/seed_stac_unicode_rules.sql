-- DEMO/TEST SEED ONLY -- never run against a shared, staging or production database. It
-- deliberately contains OPTIONAL fields with a regex (and min length) so the parity tests can
-- exercise "an optional field is validated once typed"; those rules reject realistic input
-- on purpose (see NOTES.md, "Optional-field regex audit").
-- Adds the `unicode_rules` stage (Amharic / code-point fixtures) to the real dev workflow, on top of
-- tool/seed_stac_fixtures.sql and tool/seed_stac_length_rules.sql. STAC_MIGRATION_SCOPING.md section 14.
-- Run once, then delete the resolved-config cache key and run tool/record_stac_fixtures.sh.
BEGIN;
INSERT INTO config.stages(id,key,scope,workflow_id,stage_order,screen_type,skip_gap_check,created_at,updated_at,native_handler)
SELECT gen_random_uuid(),'unicode_rules','TENANT',workflow_id,6,'GENERIC_FORM',false,now(),now(),NULL
FROM config.stages WHERE key='length_rules';

INSERT INTO config.fields(id,stage_id,key,field_type,input_mode,options,dynamic_config,validation,regex,depends_on,conditional_dependency,created_at,updated_at,resolves_at_fetch_time)
SELECT gen_random_uuid(), s.id, v.key, 'TEXT', 'FREE', NULL, NULL, v.val::jsonb, v.rx, '[]'::jsonb, NULL, now(), now(), false
FROM config.stages s, (VALUES
  -- Unicode-aware name: any letter/mark/space, 2..8 characters
  ('am_name',     '{"min_length": 2, "max_length": 8}', '^[\p{L}\p{M}\s/''.-]{1,64}$'),
  -- exactly one code point (a supplementary-plane emoji is ONE)
  ('single_char', NULL,                                 '^.$'),
  -- optional, but with BOTH a regex and a minimum length
  ('opt_code',    '{"min_length": 3}',                  '^[0-9]+$')
) AS v(key,val,rx) WHERE s.key='unicode_rules';

INSERT INTO config.field_policy_overlays(id,field_id,client_id,is_required,is_hidden,display_order,created_at,updated_at)
SELECT gen_random_uuid(), f.id, 'e8ce7cac-22fb-4858-8328-bd62297c7e75', v.req, false, v.ord, now(), now()
FROM config.fields f JOIN config.stages s ON s.id=f.stage_id
JOIN (VALUES ('am_name',true,1),('single_char',false,2),('opt_code',false,3)) AS v(key,req,ord) ON v.key=f.key
WHERE s.key='unicode_rules';
COMMIT;
