"""Bounded-memory authenticated backups, excluding provider data and credentials."""
import hashlib
import contextlib
import os
import sqlite3
import struct
import tempfile
import time
from pathlib import Path

MAGIC=b'VELO-BACKUP-1\n'

def create_backup(db,destination):
    destination=Path(destination);destination.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=db.settings.data_dir) as temporary:
        copy=Path(temporary)/'sanitized.sqlite3'
        with db.connect() as source:
            target=sqlite3.connect(copy)
            source.backup(target)
        target.execute('PRAGMA secure_delete=ON')
        for table in ('password_resets','refresh_tokens','connections','cache','cursors','oauth_states','sessions','invites','attempts','quota'):
            target.execute(f'DELETE FROM {table}')
        target.execute("DELETE FROM jobs WHERE kind!='upload'")
        target.execute("UPDATE jobs SET status=CASE WHEN status='complete' THEN 'complete' ELSE 'needs_review' END,result=NULL,error=NULL,lease_until=0")
        target.execute('DELETE FROM sync_history')
        target.commit();target.execute('VACUUM');target.close()
        partial=destination.with_suffix(destination.suffix+'.partial')
        sha=hashlib.sha256();index=0
        try:
            with copy.open('rb') as source,partial.open('wb') as sink:
                sink.write(MAGIC)
                while chunk:=source.read(65536):
                    sha.update(chunk)
                    token=db.cipher.encrypt(b'D'+struct.pack('>Q',index)+chunk)
                    sink.write(struct.pack('>I',len(token)));sink.write(token);index+=1
                token=db.cipher.encrypt(b'E'+struct.pack('>Q',index)+sha.digest())
                sink.write(struct.pack('>I',len(token)));sink.write(token);sink.flush();os.fsync(sink.fileno())
            partial.replace(destination)
            try:destination.chmod(0o600)
            except OSError:pass
        finally:partial.unlink(missing_ok=True)
    return destination

def restore_backup(settings,source,confirm=False):
    if not confirm:raise ValueError('Restore requires --confirm and stopped API/worker containers')
    settings.data_dir.mkdir(parents=True,exist_ok=True);cipher=settings.cipher()
    with tempfile.TemporaryDirectory(dir=settings.data_dir) as temporary:
        restored=Path(temporary)/'restore.sqlite3';sha=hashlib.sha256();index=0;finished=False
        with Path(source).open('rb') as stream,restored.open('wb') as sink:
            if stream.read(len(MAGIC))!=MAGIC:raise ValueError('Unknown backup format')
            while length:=stream.read(4):
                if len(length)!=4:raise ValueError('Truncated backup')
                size=struct.unpack('>I',length)[0]
                if not 1<=size<=100000:raise ValueError('Invalid backup block')
                token=stream.read(size)
                if len(token)!=size:raise ValueError('Truncated backup')
                block=cipher.decrypt(token)
                if block[:1]==b'E':
                    if len(block)!=41 or struct.unpack('>Q',block[1:9])[0]!=index or block[9:]!=sha.digest() or stream.read(1):raise ValueError('Backup integrity check failed')
                    finished=True;break
                if block[:1]!=b'D' or struct.unpack('>Q',block[1:9])[0]!=index:raise ValueError('Invalid backup block order')
                sha.update(block[9:]);sink.write(block[9:]);index+=1
        if not finished:raise ValueError('Incomplete backup')
        with contextlib.closing(sqlite3.connect(restored)) as con:
            if con.execute('PRAGMA integrity_check').fetchone()[0]!='ok':raise ValueError('Invalid SQLite backup')
            con.execute('SELECT version FROM schema_migrations').fetchall()
        target=settings.data_dir/'velo.sqlite3'
        # Caller must stop API + worker first; never replace a live WAL database.
        for suffix in ('-wal','-shm'):
            path=Path(str(target)+suffix)
            if path.exists():raise ValueError('Live WAL database detected; stop API and worker before restore')
        restored.replace(target)
        try:target.chmod(0o600)
        except OSError:pass

def backup_loop(db,directory,interval=86400,retention=7):
    while True:
        now=time.strftime('%Y%m%dT%H%M%SZ',time.gmtime())
        create_backup(db,Path(directory)/f'velo-{now}.velobackup')
        for old in sorted(Path(directory).glob('velo-*.velobackup'))[:-retention]:old.unlink()
        time.sleep(interval)
