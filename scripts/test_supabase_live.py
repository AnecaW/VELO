"""Live hosted integration/security checks. Disposable users are always removed."""
import argparse
import json
from pathlib import Path
import secrets
import urllib.request
import urllib.error
import uuid
from supabase_admin import Management, ROOT


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--token-file', required=True)
    args = parser.parse_args()
    manager = Management(args.token_file)
    config = json.loads((ROOT / 'config/supabase.json').read_text())
    origin, key = config['SUPABASE_URL'], config['SUPABASE_PUBLISHABLE_KEY']
    users = []
    checks = 0

    def call(path, body=None, token=None, method=None):
        headers = {'apikey': key, 'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        request = urllib.request.Request(origin + path, headers=headers,
            data=json.dumps(body).encode() if body is not None else None, method=method)
        try:
            response = urllib.request.urlopen(request, timeout=40)
        except urllib.error.HTTPError as error:
            response = error
        raw = response.read()
        try:
            result = json.loads(raw) if raw else None
        except ValueError:
            result = None
        return response.code, result

    def check(value, label):
        nonlocal checks
        assert value, label
        checks += 1
        print('PASS:', label)

    def edge(path, token=None, method='GET', body=None):
        return call('/functions/v1/velo-api', {'path': path, 'method': method, 'body': body}, token)

    try:
        status,config=call('/functions/v1/velo-api/config')
        check(status==200 and config['password_reset_enabled'] is False,'password reset remains disabled without mail configuration')
        password = secrets.token_urlsafe(24)
        for _ in range(2):
            email = 'velo-test-' + uuid.uuid4().hex + '@example.invalid'
            status, account = call('/auth/v1/signup', {'email': email, 'password': password})
            check(status == 200 and bool(account.get('access_token')), 'registration with immediate session')
            users.append(account)
        a, b = users
        aid, bid = a['user']['id'], b['user']['id']
        status, _ = call('/auth/v1/token?grant_type=password', {'email': a['user']['email'], 'password': 'incorrect-password'})
        check(status == 400, 'incorrect password rejected')
        status, signed_in = call('/auth/v1/token?grant_type=password', {'email': a['user']['email'], 'password': password})
        check(status == 200 and signed_in['user']['id'] == aid, 'email/password login')
        token = signed_in['access_token']
        status, _ = call('/auth/v1/user', token=token)
        check(status == 200, 'session retrieves authenticated user')
        doc = {'p_kind': 'routes', 'p_id': 'A/B? café', 'p_payload': {'name': 'Own route'}, 'p_expected_revision': None}
        status, saved = call('/rest/v1/rpc/velo_write_document', doc, token)
        check(status == 200 and saved.get('revision', 0) > 0, 'PostgreSQL document insert')
        status, page = call('/rest/v1/rpc/velo_documents_page', {'p_kind': 'routes', 'p_after': 0}, token)
        check(status == 200 and len(page['items']) == 1, 'owner reads document')
        status, page = call('/rest/v1/rpc/velo_documents_page', {'p_kind': 'routes', 'p_after': 0}, b['access_token'])
        check(status == 200 and page['items'] == [], 'second user cannot read first user data through RPC')
        status, rows = call('/rest/v1/velo_documents?user_id=eq.' + aid, token=b['access_token'])
        check(status == 200 and rows == [], 'RLS blocks cross-account direct reads')
        status, rows = call('/rest/v1/velo_documents')
        check(status in (401, 403), 'anonymous document reads denied')
        status, _ = call('/rest/v1/velo_documents', {'user_id': bid, 'kind': 'routes', 'id': 'bypass', 'payload': {}}, b['access_token'])
        check(status in (401, 403), 'direct writes cannot bypass revision RPC')
        status, _ = call('/rest/v1/velo_profiles', {'user_id': aid, 'display_name': 'spoof'}, b['access_token'])
        check(status in (401, 403), 'RLS prevents spoofed profile owner')
        status, _ = call('/rest/v1/rpc/velo_private_call', {'p_action': 'connection', 'p_args': {'user_id': aid}}, token)
        check(status in (401, 403, 404), 'provider secrets RPC denied to authenticated user')
        for ride_id in ('test-ride-one','test-ride-two'):
            ride={'v':1,'id':ride_id,'state':'saved','distance':0.1,'points':[[50,4,10,'2026-11-01T10:00:00Z',0,5,0,False],[50.001,4.001,10,'2026-11-01T10:01:00Z',2,5,0,False]]}
            status,_=call('/rest/v1/rpc/velo_write_document',{'p_kind':'rides','p_id':ride_id,'p_payload':ride,'p_expected_revision':None},token)
            check(status==200,'ride and separate track stored atomically')
        status,metadata=call('/rest/v1/velo_activities',token=token)
        check(status==200 and len(metadata)==2 and all('points' not in r['payload'] for r in metadata),'activity listing excludes heavy GPS geometry')
        status,tracks=call('/rest/v1/velo_tracks?user_id=eq.'+aid,token=b['access_token'])
        check(status==200 and tracks==[],'RLS isolates separate GPS tracks')
        status,page=call('/rest/v1/rpc/velo_documents_page',{'p_kind':'rides','p_after':0},token)
        check(status==200 and len(page['items'])==1 and page['has_more'] and len(page['items'][0]['payload']['points'])==2,'ride sync rehydrates tracks with bounded pagination')
        status,next_page=call('/rest/v1/rpc/velo_documents_page',{'p_kind':'rides','p_after':page['cursor']},token)
        check(status==200 and len(next_page['items'])==1 and not next_page['has_more'],'incremental track sync reaches next ride without duplication')
        status,_=call('/rest/v1/rpc/velo_write_document',{'p_kind':'sensor_configs','p_id':'test-sensor','p_payload':{'name':'Test fixture sensor','type':'heartRate'},'p_expected_revision':None},token)
        check(status==200,'sensor configuration persisted under owner')
        status,_=call('/rest/v1/rpc/velo_write_document',{'p_kind':'favorites','p_id':'test-place','p_payload':{'value':'Test fixture address'},'p_expected_revision':None},token)
        check(status==200,'favorite place persisted under owner')
        status, _ = call('/rest/v1/rpc/velo_write_document', {**doc, 'p_payload': {'name': 'overwrite'}}, token)
        check(status == 409, 'stale document overwrite rejected')
        status, deleted = call('/rest/v1/rpc/velo_write_document', {**doc, 'p_payload': None, 'p_expected_revision': saved['revision']}, token)
        check(status == 200 and deleted['revision'] > saved['revision'], 'revisioned deletion tombstone')
        status, _ = call('/rest/v1/rpc/velo_write_document', {**doc, 'p_expected_revision': saved['revision']}, token)
        check(status == 409, 'stale client cannot resurrect deleted document')
        status, _ = edge('/api/v1/jobs')
        check(status == 401, 'Edge Function rejects anonymous request')
        status, data = edge('/api/v1/integrations/strava', token)
        check(status == 200 and data['configured'] is False, 'missing Strava credentials reported honestly')
        status, _ = edge('/api/v1/navigation/search?q=Brussels', token)
        check(status == 503, 'missing navigation credential handled')
        status, _ = call('/functions/v1/velo-worker', {}, token)
        check(status == 401, 'ordinary user cannot invoke scheduler')
        status, _ = edge('/api/v1/me', token, 'DELETE', {'password': 'incorrect-password'})
        check(status == 401, 'account deletion requires current password')
        status, refreshed = call('/auth/v1/token?grant_type=refresh_token', {'refresh_token': signed_in['refresh_token']})
        check(status == 200 and bool(refreshed['access_token']), 'Supabase session refresh')
        status, _ = call('/auth/v1/logout?scope=local', {}, refreshed['access_token'])
        check(status in (200, 204), 'logout revokes session')
        status, _ = call('/auth/v1/token?grant_type=refresh_token', {'refresh_token': refreshed['refresh_token']})
        check(status == 400, 'revoked refresh token rejected')
        status, _ = edge('/api/v1/me', b['access_token'], 'DELETE', {'password': password})
        check(status == 200, 'real Edge account deletion')
        result = manager.query("select count(*)::int n from auth.users where id='" + bid + "'::uuid")
        check(result[0]['n'] == 0, 'deleted auth account and cascading data removed')
        print('Live checks passed:', checks)
    finally:
        for account in users:
            manager.query("delete from auth.users where id='" + str(uuid.UUID(account['user']['id'])) + "'::uuid")
        print('Disposable users cleaned up:', len(users))


if __name__ == '__main__':
    main()
