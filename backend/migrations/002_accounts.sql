ALTER TABLE users ADD COLUMN email TEXT;
CREATE UNIQUE INDEX users_email ON users(email) WHERE email IS NOT NULL;
CREATE TABLE refresh_tokens(digest TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,access_digest TEXT NOT NULL,family TEXT NOT NULL,expires_at INTEGER NOT NULL,used INTEGER NOT NULL DEFAULT 0,created_at INTEGER NOT NULL);
CREATE INDEX refresh_family ON refresh_tokens(family);
