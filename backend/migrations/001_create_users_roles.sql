-- =============================================
-- LIBRA LAW PRACTICE
-- Migration 001: Create Roles + Users tables
-- Run this FIRST before anything else
-- =============================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── ROLES TABLE ─────────────────────────────
CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Insert default roles
INSERT INTO roles (name, description) VALUES
('super_admin', 'Platform owner with full access'),
('admin',       'Law firm admin with full firm access'),
('lawyer',      'Lawyer with assigned case access'),
('staff',       'Staff with limited access'),
('clerk',       'Clerk with document access only'),
('client',      'Client portal access only');

-- ─── USERS TABLE ─────────────────────────────
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    phone VARCHAR(20),
    password_hash TEXT NOT NULL,
    role_id UUID REFERENCES roles(id) ON DELETE SET NULL,
    firm_id UUID,
    avatar_url TEXT,
    bar_council_number VARCHAR(50),
    designation VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    email_verified BOOLEAN DEFAULT FALSE,
    otp_code VARCHAR(10),
    otp_expires_at TIMESTAMP,
    reset_token TEXT,
    reset_token_expires_at TIMESTAMP,
    last_login_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role_id ON users(role_id);
CREATE INDEX idx_users_firm_id ON users(firm_id);
CREATE INDEX idx_users_is_active ON users(is_active);
