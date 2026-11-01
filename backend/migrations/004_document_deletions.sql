CREATE TABLE document_tombstones(user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,kind TEXT NOT NULL,id TEXT NOT NULL,revision INTEGER NOT NULL,deleted_at INTEGER NOT NULL,PRIMARY KEY(user_id,kind,id));
CREATE INDEX tombstones_revision ON document_tombstones(user_id,kind,revision);
