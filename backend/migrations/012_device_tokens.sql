-- FCM device tokens. A user can be signed in on more than one device, so this
-- is a one-to-many table rather than a column on users. Deleting the user
-- cleans up their tokens; a token is unique across all users because a device
-- token can only ever be currently valid for the one app instance that has it.
CREATE TABLE IF NOT EXISTS device_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL UNIQUE,
    platform VARCHAR(20),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id ON device_tokens(user_id);
