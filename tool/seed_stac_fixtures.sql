-- Seeds the two fixtures the Stac parity checks run against (STAC_MIGRATION_SCOPING.md
-- section 12) into the local onboarding-platform dev database, ON TOP of the
-- Phase 5 seed (NOTES.md): a conditional `company_name` on association_details, and a
-- new `location` stage (eager `region`, live cascading `district`, a regex-validated
-- text field, a date field) with real reference data. Run once:
--   docker cp tool/seed_stac_fixtures.sql postgres:/tmp/ && \
--   docker exec postgres psql -U onboarding -d onboarding -v ON_ERROR_STOP=1 -f /tmp/seed_stac_fixtures.sql
-- then delete the resolved-config cache key (see NOTES.md Phase 5) and run
-- tool/record_stac_fixtures.sh.
BEGIN;
-- reference data (real region/district UUIDs: the live-options route requires a UUID dependency value)
INSERT INTO reference_data.regions(id,name) VALUES (gen_random_uuid(),'Addis Ababa'),(gen_random_uuid(),'Oromia');
INSERT INTO reference_data.districts(id,region_id,name)
  SELECT gen_random_uuid(), r.id, d FROM reference_data.regions r, unnest(ARRAY['Bole','Kirkos','Yeka']) d WHERE r.name='Addis Ababa';
INSERT INTO reference_data.districts(id,region_id,name)
  SELECT gen_random_uuid(), r.id, d FROM reference_data.regions r, unnest(ARRAY['Adama','Jimma']) d WHERE r.name='Oromia';

-- conditional company_name on the existing association_details stage
INSERT INTO config.fields(id,stage_id,key,field_type,input_mode,options,dynamic_config,validation,depends_on,conditional_dependency,created_at,updated_at,resolves_at_fetch_time)
SELECT gen_random_uuid(), id, 'company_name','TEXT','FREE',NULL,NULL,'{"max_length": 60}'::jsonb,'["association_type"]'::jsonb,
 '{"if":[{"field":"association_type","op":"eq","value":"Group"}],"then":{"isRequired":true,"isHidden":false},"else":{"isRequired":false,"isHidden":true}}'::jsonb,
 now(),now(),false FROM config.stages WHERE key='association_details';

-- new location stage
INSERT INTO config.stages(id,key,scope,workflow_id,stage_order,screen_type,skip_gap_check,created_at,updated_at,native_handler)
SELECT gen_random_uuid(),'location','TENANT',workflow_id,4,'GENERIC_FORM',false,now(),now(),NULL FROM config.stages WHERE key='association_details';

INSERT INTO config.fields(id,stage_id,key,field_type,input_mode,options,dynamic_config,validation,regex,depends_on,conditional_dependency,created_at,updated_at,resolves_at_fetch_time)
SELECT gen_random_uuid(), s.id, v.key, v.ft, v.im, NULL, v.dc::jsonb, NULL, v.rx, v.dep::jsonb, NULL, now(), now(), v.res
FROM config.stages s, (VALUES
 ('region','SELECT','DYNAMIC','{"endpoint":"/reference-data/regions","method":"GET"}',NULL,'[]',true),
 ('district','SELECT','DYNAMIC','{"endpoint":"/reference-data/regions/{region}/districts","method":"GET"}',NULL,'["region"]',false),
 ('postal_code','TEXT','FREE',NULL,'^[0-9]{4}$','[]',false),
 ('registration_date','TEXT','DATE',NULL,NULL,'[]',false)
) AS v(key,ft,im,dc,rx,dep,res) WHERE s.key='location';

-- overlays for the client (required / hidden / order)
INSERT INTO config.field_policy_overlays(id,field_id,client_id,is_required,is_hidden,display_order,created_at,updated_at)
SELECT gen_random_uuid(), f.id, 'e8ce7cac-22fb-4858-8328-bd62297c7e75', v.req, v.hid, v.ord, now(), now()
FROM config.fields f JOIN config.stages s ON s.id=f.stage_id
JOIN (VALUES
 ('association_details','association_type',false,false,1),
 ('association_details','company_name',false,true,2),
 ('location','region',true,false,1),
 ('location','district',true,false,2),
 ('location','postal_code',true,false,3),
 ('location','registration_date',false,false,4)
) AS v(stage,key,req,hid,ord) ON v.stage=s.key AND v.key=f.key;
COMMIT;
