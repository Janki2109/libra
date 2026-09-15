-- =============================================
-- Migration 030: Content Management
--
-- No content management system existed anywhere in this app. Legal
-- Articles, FAQs, Banners, Announcements and Promotional Content share the
-- same real shape (title, body, optional image, optional CTA, an audience,
-- an optional publish/expiry window, a status) — one content_items table
-- with a content_type discriminator avoids five near-identical tables, the
-- same "reuse instead of duplicating a near-identical structure" approach
-- migration 007's audit_logs / this app's other tables already follow.
--
-- Terms & Conditions and Privacy Policy are different in kind (they need a
-- real version history, never overwritten) so they get their own table.
--
-- Images follow this app's existing file-storage convention — documents
-- and avatar_url are already stored as data URIs / plain URLs directly in
-- Postgres (see documents.file_content, users.avatar_url); there is no
-- Firebase Storage/S3 integration anywhere in this backend to reuse, so
-- image_url here follows that same existing pattern rather than inventing
-- a new upload pipeline.
-- =============================================

CREATE TABLE IF NOT EXISTS content_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_type VARCHAR(20) NOT NULL
        CHECK (content_type IN ('article','faq','banner','announcement','promotion')),
    title VARCHAR(300) NOT NULL,
    subtitle VARCHAR(500),
    body TEXT,
    category VARCHAR(60),
    image_url TEXT,
    cta_text VARCHAR(100),
    cta_action VARCHAR(300),
    tags TEXT[],
    target_audience VARCHAR(20) NOT NULL DEFAULT 'all'
        CHECK (target_audience IN ('all','lawyer','client','student')),
    priority VARCHAR(10) DEFAULT 'normal' CHECK (priority IN ('normal','high')),
    display_order INT NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','scheduled','published','unpublished','archived')),
    publish_at TIMESTAMP,
    expire_at TIMESTAMP,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    published_by UUID REFERENCES users(id) ON DELETE SET NULL,
    published_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_content_items_type ON content_items(content_type);
CREATE INDEX IF NOT EXISTS idx_content_items_status ON content_items(status);
CREATE INDEX IF NOT EXISTS idx_content_items_category ON content_items(category);
CREATE INDEX IF NOT EXISTS idx_content_items_audience ON content_items(target_audience);
CREATE INDEX IF NOT EXISTS idx_content_items_created_at ON content_items(created_at);
CREATE INDEX IF NOT EXISTS idx_content_items_published_at ON content_items(published_at);

-- Terms & Conditions / Privacy Policy: append-only version history. Exactly
-- one row per doc_type may have status='published' at a time — enforced by
-- a partial unique index rather than application logic alone, so a race
-- between two Super Admin publishes can't leave two "current" versions.
CREATE TABLE IF NOT EXISTS legal_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doc_type VARCHAR(20) NOT NULL CHECK (doc_type IN ('terms','privacy')),
    version VARCHAR(20) NOT NULL,
    content TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    published_by UUID REFERENCES users(id) ON DELETE SET NULL,
    published_at TIMESTAMP,
    UNIQUE (doc_type, version)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_legal_documents_one_published
    ON legal_documents(doc_type) WHERE status = 'published';
CREATE INDEX IF NOT EXISTS idx_legal_documents_type ON legal_documents(doc_type);
