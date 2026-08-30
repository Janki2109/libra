-- =============================================
-- Migration 004: Create Hearings table
-- =============================================

CREATE TABLE hearings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    case_id UUID REFERENCES cases(id) ON DELETE CASCADE,
    firm_id UUID NOT NULL,
    hearing_date DATE NOT NULL,
    hearing_time TIME,
    court_name VARCHAR(150),
    court_room VARCHAR(50),
    judge_name VARCHAR(100),
    purpose VARCHAR(255),
    notes TEXT,
    next_date DATE,
    status VARCHAR(50) DEFAULT 'scheduled',
    reminder_sent BOOLEAN DEFAULT FALSE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- status: scheduled, completed, adjourned, cancelled

CREATE INDEX idx_hearings_case_id ON hearings(case_id);
CREATE INDEX idx_hearings_firm_id ON hearings(firm_id);
CREATE INDEX idx_hearings_hearing_date ON hearings(hearing_date);
CREATE INDEX idx_hearings_status ON hearings(status);
