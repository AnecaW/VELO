import argparse
import json
import secrets
import time
from pathlib import Path
from cryptography.fernet import Fernet

def main():
    parser=argparse.ArgumentParser(prog='velo-backend')
    parser.add_argument('command',choices=['serve','worker','backup','backup-loop','restore','generate-secrets','rotate-key','create-admin'])
    parser.add_argument('--file');parser.add_argument('--confirm',action='store_true')
    args=parser.parse_args()
    if args.command=='generate-secrets':
        # Explicit operator command, never executed automatically or by CI logs.
        print('VELO_ENCRYPTION_KEYS='+Fernet.generate_key().decode());print('VELO_BOOTSTRAP_TOKEN='+secrets.token_urlsafe(32));return
    from .config import Settings
    import logging
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(name)s %(message)s')
    settings=Settings.environment()
    if args.command=='serve':
        import uvicorn
        uvicorn.run('velo_backend.api:create_app',factory=True,host='0.0.0.0',port=8000,workers=1,access_log=False,proxy_headers=False,limit_concurrency=4)
        return
    if args.command=='restore':
        from .backup import restore_backup
        if not args.file:parser.error('--file required')
        restore_backup(settings,args.file,args.confirm);print('Backup restored. External accounts require reconnecting.');return
    from .storage import Database
    db=Database(settings)
    if args.command=='create-admin':
        import getpass
        from .accounts import EmailCredentials
        from .security import password_hash
        import uuid
        email=input('Administrator email: ')
        password=getpass.getpass('Password (12+ characters): ')
        if password != getpass.getpass('Repeat password: '):parser.error('Passwords differ')
        body=EmailCredentials(email=email,password=password)
        with db.connect(True) as con:
            if con.execute("SELECT 1 FROM users WHERE role='admin'").fetchone():parser.error('Administrator already exists')
            identifier=uuid.uuid4().hex
            con.execute('INSERT INTO users(id,username,email,password_hash,role,created_at) VALUES(?,?,?,?,?,?)',(identifier,identifier,body.email,password_hash(body.password),'admin',int(time.time())))
            con.execute("INSERT OR REPLACE INTO server_state VALUES('bootstrap_consumed','1')")
        print('Administrator created.')
    elif args.command=='worker':
        from .strava import Strava
        from .jobs import Worker
        worker=Worker(db,Strava(db))
        while True:
            try:worked=worker.tick()
            except Exception:worked=False;print('Worker iteration deferred; check database availability.',flush=True)
            Path('/tmp/worker-heartbeat').touch()
            if not worked:time.sleep(settings.worker_interval)
    elif args.command=='backup-loop':
        from .backup import backup_loop
        backup_loop(db,'/backups')
    elif args.command=='backup':
        from .backup import create_backup
        if not args.file:parser.error('--file required')
        create_backup(db,args.file);print('Encrypted backup created; external API data excluded.')
    elif args.command=='rotate-key':
        # Environment keys: new key first, previous keys after it. Back up first.
        for table,column,keys in [('documents','payload',['user_id','kind','id']),('connections','tokens',['user_id','provider']),('cache','payload',['user_id','provider','kind','id']),('jobs','result',['id'])]:
            with db.connect(True) as con:
                for row in con.execute(f'SELECT * FROM {table} WHERE {column} IS NOT NULL').fetchall():
                    fresh=db.cipher.rotate(row[column]);where=' AND '.join(k+'=?' for k in keys)
                    con.execute(f'UPDATE {table} SET {column}=? WHERE {where}',(fresh,*[row[k] for k in keys]))
        print('Encrypted values rotated. Retain old keys until old backups expire.')

if __name__=='__main__':main()
