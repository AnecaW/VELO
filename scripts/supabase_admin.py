"""Deploy to hosted Supabase without Docker. Never print credentials or config bodies."""
import argparse
import json
import os
from pathlib import Path
import urllib.request
import urllib.error
import uuid

PROJECT = 'pdooxhljbutbsotbjbrt'
ROOT = Path(__file__).resolve().parents[1]


class Management:
    def __init__(self, token_file, project=PROJECT):
        self.token = Path(token_file).read_text(encoding='utf-8-sig').strip()
        self.project = project

    def request(self, path, body=None, method=None, content_type='application/json'):
        data = json.dumps(body).encode() if body is not None and not isinstance(body, bytes) else body
        req = urllib.request.Request('https://api.supabase.com/v1/projects/' + self.project + path,
            data=data, method=method, headers={'Authorization': 'Bearer ' + self.token, 'Content-Type': content_type})
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            # The server may include submitted SQL or settings in errors. Keep them private.
            raise RuntimeError(f'Supabase management request failed: HTTP {error.code} at {path}') from None

    def query(self, sql):
        return self.request('/database/query', {'query': sql})

    def deploy(self, slug):
        root = ROOT / 'supabase/functions'
        boundary = uuid.uuid4().hex
        blocks = []
        metadata = {'entrypoint_path': slug + '/index.ts', 'verify_jwt': False, 'name': slug}
        blocks.append(f'--{boundary}\r\nContent-Disposition: form-data; name="metadata"\r\nContent-Type: application/json\r\n\r\n'.encode() + json.dumps(metadata).encode() + b'\r\n')
        for file in sorted(root.rglob('*')):
            if file.suffix not in ('.ts', '.json') or file.name.endswith('_test.ts'):
                continue
            name = file.relative_to(root).as_posix()
            blocks.append(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{name}"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode() + file.read_bytes() + b'\r\n')
        blocks.append(f'--{boundary}--\r\n'.encode())
        result = self.request('/functions/deploy?slug=' + slug, b''.join(blocks), content_type='multipart/form-data; boundary=' + boundary)
        print('Function deployed:', slug, result.get('status'), 'version', result.get('version'))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['deploy', 'migrate', 'configure-auth'])
    parser.add_argument('--token-file', default=os.environ.get('SUPABASE_ACCESS_TOKEN_FILE', str(Path.home() / '.codex/secrets/velo-supabase-access-token.txt')))
    args = parser.parse_args()
    api = Management(args.token_file)
    if args.command == 'deploy':
        for slug in ('velo-api', 'velo-worker', 'velo-webhook'):
            api.deploy(slug)
    elif args.command == 'configure-auth':
        current = api.request('/config/auth')
        missing = [k for k in ('smtp_host','smtp_port','smtp_user','smtp_pass','smtp_admin_email','smtp_sender_name') if not current.get(k)]
        if missing: raise RuntimeError('Missing Supabase SMTP fields: '+', '.join(missing))
        api.request('/config/auth', {'mailer_autoconfirm': False, 'external_email_enabled': True,
            'disable_signup': False, 'password_min_length': 12, 'jwt_exp': 900,
            'site_url': 'ultimatebike://auth/callback', 'uri_allow_list': 'ultimatebike://auth/callback'}, 'PATCH')
        templates = {}
        for key in ('mailer_templates_confirmation_content', 'mailer_templates_recovery_content'):
            content = current.get(key) or '<p><a href="{{ .ConfirmationURL }}">Open VELO op je Android-toestel</a></p>'
            if '.Token' not in content:
                content += '<p>Lees je deze mail op een ander toestel? Vul deze code in VELO in: <strong>{{ .Token }}</strong></p><p>De link opent de Android-app. Deel je code met niemand.</p>'
            templates[key] = content
        api.request('/config/auth', templates, 'PATCH')
        api.request('/secrets',[{'name':'VELO_PASSWORD_RESET_ENABLED','value':'true'}])
        print('Email/password signup enabled; confirmation required; recovery enabled; SMTP credentials kept on Supabase.')
    else:
        existing = {row['version'] for row in api.request('/database/migrations')}
        for path in sorted((ROOT / 'supabase/migrations').glob('*.sql')):
            version, name = path.stem.split('_', 1)
            if version in existing:
                continue
            # Explicitly record the checked-in version atomically with its SQL.
            sql = path.read_text(encoding='utf-8').strip()
            if sql.lower().startswith('begin;'):
                sql = sql[6:]
            if sql.lower().endswith('commit;'):
                sql = sql[:-7]
            name = name.replace("'", "''")
            api.query('begin;\n' + sql + f"\ninsert into supabase_migrations.schema_migrations(version,name,statements) values('{version}','{name}',array[]::text[]);\ncommit;")
            print('Migration applied:', version)


if __name__ == '__main__':
    main()
