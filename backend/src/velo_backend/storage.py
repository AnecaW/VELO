import contextlib
import json
import sqlite3
import time
from pathlib import Path

class Database:
    def __init__(self, settings):
        self.settings = settings
        self.path = settings.data_dir / "velo.sqlite3"
        settings.data_dir.mkdir(parents=True, exist_ok=True)
        self.cipher = settings.cipher()
        self.migrate()

    @contextlib.contextmanager
    def connect(self, write=False):
        con = sqlite3.connect(self.path, timeout=10)
        con.row_factory = sqlite3.Row
        con.execute("PRAGMA foreign_keys=ON")
        con.execute("PRAGMA busy_timeout=10000")
        try:
            if write: con.execute("BEGIN IMMEDIATE")
            yield con
            con.commit()
        except Exception:
            con.rollback()
            raise
        finally: con.close()

    def migrate(self):
        directory = Path(__file__).resolve().parents[2] / "migrations"
        with self.connect() as con:
            con.execute("PRAGMA journal_mode=WAL")
        with self.connect(True) as con:
            con.execute("CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)")
            for migration in sorted(directory.glob("*.sql")):
                version = int(migration.name.split("_")[0])
                if not con.execute("SELECT 1 FROM schema_migrations WHERE version=?", (version,)).fetchone():
                    # Atomic DDL and version record, including on interrupted initialization.
                    escaped = migration.read_text().replace("\x00", "")
                    for statement in escaped.split(';'):
                        if statement.strip():con.execute(statement)
                    con.execute('INSERT INTO schema_migrations VALUES(?,?)',(version,int(time.time())))

    def seal(self, value):
        return self.cipher.encrypt(json.dumps(value, allow_nan=False, separators=(",", ":")).encode())

    def open(self, value):
        return json.loads(self.cipher.decrypt(value))

    def cleanup(self):
        now = int(time.time())
        with self.connect(True) as con:
            con.execute("DELETE FROM cache WHERE expires_at<=?", (now,))
            con.execute("DELETE FROM oauth_states WHERE expires_at<=?", (now,))
            con.execute("DELETE FROM sessions WHERE expires_at<=?", (now,))
            con.execute("DELETE FROM password_resets WHERE expires_at<=?", (now,))
            con.execute("DELETE FROM refresh_tokens WHERE expires_at<=?", (now,))
            con.execute("DELETE FROM invites WHERE expires_at<=?", (now,))
            con.execute("DELETE FROM attempts WHERE until_at<=?", (now,))
            con.execute("DELETE FROM sync_history WHERE created_at<?", (now-30*86400,))
            con.execute("UPDATE jobs SET result=NULL WHERE updated_at<?", (now-86400,))

    def history(self, user, provider, status, message):
        import uuid
        with self.connect(True) as con:
            con.execute("INSERT INTO sync_history VALUES(?,?,?,?,?,?)", (uuid.uuid4().hex,user,provider,status,message,int(time.time())))
