CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'organization_type') THEN
    CREATE TYPE organization_type AS ENUM (
      'hospital',
      'clinic',
      'home_visit_clinic',
      'visiting_nurse_station',
      'nursing_facility',
      'pharmacy',
      'home_care_office',
      'other'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'inquiry_status') THEN
    CREATE TYPE inquiry_status AS ENUM (
      'new',
      'reviewing',
      'qualified',
      'converted',
      'closed',
      'spam'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'case_status') THEN
    CREATE TYPE case_status AS ENUM (
      'draft',
      'intake',
      'scoping',
      'sourcing',
      'interviewing',
      'offer',
      'placed',
      'on_hold',
      'closed_won',
      'closed_lost'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'priority_level') THEN
    CREATE TYPE priority_level AS ENUM (
      'low',
      'medium',
      'high',
      'urgent',
      'critical'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'profession_type') THEN
    CREATE TYPE profession_type AS ENUM (
      'physician',
      'nurse',
      'pharmacist',
      'therapist',
      'care_worker',
      'care_manager',
      'medical_clerk',
      'other'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'employment_type') THEN
    CREATE TYPE employment_type AS ENUM (
      'full_time',
      'part_time',
      'temporary',
      'dispatch',
      'contract',
      'locum',
      'other'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'availability_status') THEN
    CREATE TYPE availability_status AS ENUM (
      'immediate',
      'within_2_weeks',
      'within_1_month',
      'future',
      'unavailable'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'match_stage') THEN
    CREATE TYPE match_stage AS ENUM (
      'shortlisted',
      'contacted',
      'screening',
      'interview',
      'offer',
      'placed',
      'declined',
      'archived'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'task_status') THEN
    CREATE TYPE task_status AS ENUM (
      'open',
      'in_progress',
      'done',
      'cancelled'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'contact_channel') THEN
    CREATE TYPE contact_channel AS ENUM (
      'email',
      'phone',
      'line',
      'web_form',
      'other'
    );
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  legal_name VARCHAR(255),
  organization_type organization_type NOT NULL DEFAULT 'other',
  corporate_number VARCHAR(20),
  website_url TEXT,
  prefecture VARCHAR(50),
  city VARCHAR(100),
  address_line1 VARCHAR(255),
  postal_code VARCHAR(20),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS organization_contacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  role_title VARCHAR(255),
  email CITEXT,
  phone VARCHAR(50),
  preferred_contact_channel contact_channel DEFAULT 'email',
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS facilities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  facility_name VARCHAR(255) NOT NULL,
  facility_type organization_type NOT NULL DEFAULT 'other',
  prefecture VARCHAR(50),
  city VARCHAR(100),
  address_line1 VARCHAR(255),
  postal_code VARCHAR(20),
  service_area TEXT,
  bed_count INTEGER CHECK (bed_count IS NULL OR bed_count >= 0),
  patient_volume_monthly INTEGER CHECK (patient_volume_monthly IS NULL OR patient_volume_monthly >= 0),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS inquiries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_name VARCHAR(255) NOT NULL,
  contact_name VARCHAR(255) NOT NULL,
  email CITEXT NOT NULL,
  phone VARCHAR(50),
  organization_type organization_type DEFAULT 'other',
  prefecture VARCHAR(50),
  inquiry_type VARCHAR(100),
  urgency_level priority_level DEFAULT 'medium',
  message TEXT NOT NULL,
  desired_support TEXT[],
  status inquiry_status NOT NULL DEFAULT 'new',
  source_channel contact_channel NOT NULL DEFAULT 'web_form',
  converted_organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
  converted_case_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS staffing_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  primary_contact_id UUID REFERENCES organization_contacts(id) ON DELETE SET NULL,
  source_inquiry_id UUID UNIQUE REFERENCES inquiries(id) ON DELETE SET NULL,
  title VARCHAR(255) NOT NULL,
  summary TEXT NOT NULL,
  background TEXT,
  case_status case_status NOT NULL DEFAULT 'intake',
  priority_level priority_level NOT NULL DEFAULT 'medium',
  compliance_risk VARCHAR(100),
  owner_name VARCHAR(255),
  target_start_date DATE,
  required_by_date DATE,
  latest_contacted_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'inquiries_converted_case_id_fkey'
  ) THEN
    ALTER TABLE inquiries
      ADD CONSTRAINT inquiries_converted_case_id_fkey
      FOREIGN KEY (converted_case_id) REFERENCES staffing_cases(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS staffing_requirements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES staffing_cases(id) ON DELETE CASCADE,
  facility_id UUID REFERENCES facilities(id) ON DELETE SET NULL,
  profession_type profession_type NOT NULL,
  specialty VARCHAR(255),
  sub_specialty VARCHAR(255),
  employment_type employment_type NOT NULL DEFAULT 'full_time',
  headcount INTEGER NOT NULL DEFAULT 1 CHECK (headcount > 0),
  min_experience_years INTEGER CHECK (min_experience_years IS NULL OR min_experience_years >= 0),
  license_requirements TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  must_have_skills TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  preferred_skills TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  shift_pattern VARCHAR(255),
  work_days TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  compensation_min INTEGER CHECK (compensation_min IS NULL OR compensation_min >= 0),
  compensation_max INTEGER CHECK (compensation_max IS NULL OR compensation_max >= 0),
  compensation_unit VARCHAR(50) DEFAULT 'monthly',
  work_prefecture VARCHAR(50),
  work_city VARCHAR(100),
  urgency_reason TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (
    compensation_min IS NULL
    OR compensation_max IS NULL
    OR compensation_min <= compensation_max
  )
);

CREATE TABLE IF NOT EXISTS candidate_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name VARCHAR(255) NOT NULL,
  full_name_kana VARCHAR(255),
  email CITEXT,
  phone VARCHAR(50),
  profession_type profession_type NOT NULL,
  primary_specialty VARCHAR(255),
  years_experience INTEGER CHECK (years_experience IS NULL OR years_experience >= 0),
  current_prefecture VARCHAR(50),
  current_city VARCHAR(100),
  desired_prefectures TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  desired_employment_types TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  licenses TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  skills TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  availability_status availability_status NOT NULL DEFAULT 'future',
  min_compensation INTEGER CHECK (min_compensation IS NULL OR min_compensation >= 0),
  profile_summary TEXT,
  source_channel contact_channel DEFAULT 'other',
  consent_to_contact BOOLEAN NOT NULL DEFAULT FALSE,
  last_contacted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS case_matches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES staffing_cases(id) ON DELETE CASCADE,
  requirement_id UUID NOT NULL REFERENCES staffing_requirements(id) ON DELETE CASCADE,
  candidate_id UUID NOT NULL REFERENCES candidate_profiles(id) ON DELETE CASCADE,
  stage match_stage NOT NULL DEFAULT 'shortlisted',
  match_score NUMERIC(5,2) CHECK (match_score IS NULL OR (match_score >= 0 AND match_score <= 100)),
  match_reason TEXT,
  owner_note TEXT,
  declined_reason TEXT,
  introduced_at TIMESTAMPTZ,
  interview_at TIMESTAMPTZ,
  placement_start_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (requirement_id, candidate_id)
);

CREATE TABLE IF NOT EXISTS follow_up_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES staffing_cases(id) ON DELETE CASCADE,
  requirement_id UUID REFERENCES staffing_requirements(id) ON DELETE SET NULL,
  match_id UUID REFERENCES case_matches(id) ON DELETE SET NULL,
  assigned_to VARCHAR(255),
  title VARCHAR(255) NOT NULL,
  description TEXT,
  due_at TIMESTAMPTZ,
  status task_status NOT NULL DEFAULT 'open',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS case_activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id UUID NOT NULL REFERENCES staffing_cases(id) ON DELETE CASCADE,
  activity_type VARCHAR(100) NOT NULL,
  summary TEXT NOT NULL,
  detail JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_by VARCHAR(255),
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_organizations_type ON organizations(organization_type);
CREATE INDEX IF NOT EXISTS idx_facilities_org ON facilities(organization_id);
CREATE INDEX IF NOT EXISTS idx_inquiries_status ON inquiries(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_staffing_cases_status ON staffing_cases(case_status, priority_level, required_by_date);
CREATE INDEX IF NOT EXISTS idx_staffing_cases_org ON staffing_cases(organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_staffing_requirements_case ON staffing_requirements(case_id, profession_type, is_active);
CREATE INDEX IF NOT EXISTS idx_staffing_requirements_license_gin ON staffing_requirements USING GIN (license_requirements);
CREATE INDEX IF NOT EXISTS idx_staffing_requirements_must_have_gin ON staffing_requirements USING GIN (must_have_skills);
CREATE INDEX IF NOT EXISTS idx_candidate_profiles_profession ON candidate_profiles(profession_type, availability_status);
CREATE INDEX IF NOT EXISTS idx_candidate_profiles_licenses_gin ON candidate_profiles USING GIN (licenses);
CREATE INDEX IF NOT EXISTS idx_candidate_profiles_skills_gin ON candidate_profiles USING GIN (skills);
CREATE INDEX IF NOT EXISTS idx_candidate_profiles_prefectures_gin ON candidate_profiles USING GIN (desired_prefectures);
CREATE INDEX IF NOT EXISTS idx_case_matches_case_stage ON case_matches(case_id, stage, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_follow_up_tasks_status_due ON follow_up_tasks(status, due_at);
CREATE INDEX IF NOT EXISTS idx_case_activities_case_time ON case_activities(case_id, occurred_at DESC);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_organizations_updated_at ON organizations;
CREATE TRIGGER trg_organizations_updated_at
BEFORE UPDATE ON organizations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_organization_contacts_updated_at ON organization_contacts;
CREATE TRIGGER trg_organization_contacts_updated_at
BEFORE UPDATE ON organization_contacts
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_facilities_updated_at ON facilities;
CREATE TRIGGER trg_facilities_updated_at
BEFORE UPDATE ON facilities
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_inquiries_updated_at ON inquiries;
CREATE TRIGGER trg_inquiries_updated_at
BEFORE UPDATE ON inquiries
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_staffing_cases_updated_at ON staffing_cases;
CREATE TRIGGER trg_staffing_cases_updated_at
BEFORE UPDATE ON staffing_cases
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_staffing_requirements_updated_at ON staffing_requirements;
CREATE TRIGGER trg_staffing_requirements_updated_at
BEFORE UPDATE ON staffing_requirements
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_candidate_profiles_updated_at ON candidate_profiles;
CREATE TRIGGER trg_candidate_profiles_updated_at
BEFORE UPDATE ON candidate_profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_case_matches_updated_at ON case_matches;
CREATE TRIGGER trg_case_matches_updated_at
BEFORE UPDATE ON case_matches
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_follow_up_tasks_updated_at ON follow_up_tasks;
CREATE TRIGGER trg_follow_up_tasks_updated_at
BEFORE UPDATE ON follow_up_tasks
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE VIEW v_case_pipeline_summary AS
SELECT
  sc.id,
  sc.title,
  sc.case_status,
  sc.priority_level,
  sc.required_by_date,
  o.name AS organization_name,
  COUNT(DISTINCT sr.id) AS requirement_count,
  COUNT(DISTINCT cm.id) AS match_count,
  COUNT(DISTINCT cm.id) FILTER (WHERE cm.stage IN ('interview', 'offer', 'placed')) AS progressed_match_count,
  COUNT(DISTINCT ft.id) FILTER (WHERE ft.status IN ('open', 'in_progress')) AS open_task_count
FROM staffing_cases sc
JOIN organizations o ON o.id = sc.organization_id
LEFT JOIN staffing_requirements sr ON sr.case_id = sc.id
LEFT JOIN case_matches cm ON cm.case_id = sc.id
LEFT JOIN follow_up_tasks ft ON ft.case_id = sc.id
GROUP BY sc.id, o.name;

CREATE OR REPLACE VIEW v_candidate_match_readiness AS
SELECT
  cp.id,
  cp.full_name,
  cp.profession_type,
  cp.primary_specialty,
  cp.availability_status,
  cp.current_prefecture,
  cp.desired_prefectures,
  cp.licenses,
  cp.skills,
  COUNT(cm.id) FILTER (WHERE cm.stage <> 'archived') AS active_match_count
FROM candidate_profiles cp
LEFT JOIN case_matches cm ON cm.candidate_id = cp.id
GROUP BY cp.id;
