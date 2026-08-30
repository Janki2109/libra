-- =============================================
-- Migration 007: Notifications, Staff,
-- Case Timeline, Case Notes, Audit Logs,
-- Court Data
-- =============================================

-- ─── NOTIFICATIONS ───────────────────────────
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    firm_id UUID,
    title VARCHAR(255) NOT NULL,
    message TEXT,
    type VARCHAR(50),
    reference_id UUID,
    reference_type VARCHAR(50),
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);
-- type: hearing_reminder, payment_reminder, case_update, document_upload, general

CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);

-- ─── STAFF ASSIGNMENTS ───────────────────────
CREATE TABLE staff_assignments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(50),
    assigned_by UUID REFERENCES users(id) ON DELETE SET NULL,
    assigned_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(case_id, user_id)
);

CREATE INDEX idx_staff_assignments_case_id ON staff_assignments(case_id);
CREATE INDEX idx_staff_assignments_user_id ON staff_assignments(user_id);

-- ─── CASE TIMELINE ───────────────────────────
CREATE TABLE case_timeline (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    event_type VARCHAR(100) NOT NULL,
    event_date TIMESTAMP NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_case_timeline_case_id ON case_timeline(case_id);

-- ─── CASE NOTES ──────────────────────────────
CREATE TABLE case_notes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    note TEXT NOT NULL,
    is_private BOOLEAN DEFAULT FALSE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_case_notes_case_id ON case_notes(case_id);

-- ─── AUDIT LOGS ──────────────────────────────
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    firm_id UUID,
    action VARCHAR(100) NOT NULL,
    module VARCHAR(50),
    reference_id UUID,
    old_values JSONB,
    new_values JSONB,
    ip_address VARCHAR(50),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_firm_id ON audit_logs(firm_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at);

-- ─── COURT DATA ──────────────────────────────
CREATE TABLE court_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    court_case_number VARCHAR(100),
    court_name VARCHAR(150),
    next_hearing_date DATE,
    case_status VARCHAR(100),
    last_order TEXT,
    cause_list_data JSONB,
    fetched_at TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_court_data_case_id ON court_data(case_id);
