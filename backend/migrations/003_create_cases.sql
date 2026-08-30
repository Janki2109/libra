-- =============================================
-- Migration 003: Create Cases table
-- =============================================

CREATE TABLE cases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firm_id UUID NOT NULL,
    client_id UUID REFERENCES clients(id) ON DELETE SET NULL,
    assigned_lawyer_id UUID REFERENCES users(id) ON DELETE SET NULL,
    case_number VARCHAR(100),
    case_title VARCHAR(255) NOT NULL,
    case_type VARCHAR(100),
    court_name VARCHAR(150),
    court_location VARCHAR(150),
    judge_name VARCHAR(100),
    opposite_party VARCHAR(150),
    opposite_lawyer VARCHAR(150),
    filing_date DATE,
    status VARCHAR(50) DEFAULT 'active',
    priority VARCHAR(20) DEFAULT 'normal',
    description TEXT,
    remarks TEXT,
    closed_at TIMESTAMP,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- status: active, pending, closed, won, lost, settled
-- priority: low, normal, high, urgent

CREATE INDEX idx_cases_firm_id ON cases(firm_id);
CREATE INDEX idx_cases_client_id ON cases(client_id);
CREATE INDEX idx_cases_assigned_lawyer_id ON cases(assigned_lawyer_id);
CREATE INDEX idx_cases_status ON cases(status);
CREATE INDEX idx_cases_case_number ON cases(case_number);
