import base64
import hashlib
import json
import time
from urllib.parse import parse_qs,urlsplit
import httpx
import pytest
from cryptography.fernet import Fernet,InvalidToken
from fastapi.testclient import TestClient
from velo_backend.api import create_app
from velo_backend.config import Settings
from velo_backend.storage import Database
from velo_backend.strava import Strava,ProviderError
from velo_backend.jobs import Worker,enqueue
from velo_backend.backup import create_backup,restore_backup

PASSWORD='Only-a-test-password-123'
BOOTSTRAP='test-bootstrap-'+('x'*32)
GPX='<gpx version="1.1"><trk><name>TEST ONLY</name><trkseg><trkpt lat="51" lon="4"/><trkpt lat="51.01" lon="4.01"/></trkseg></trk></gpx>'

@pytest.fixture
def setup(tmp_path):
    settings=Settings(tmp_path/'data','https://velo.example.test',Fernet.generate_key().decode(),BOOTSTRAP,strava_client_id='12345',strava_client_secret='test-secret-not-production')
    db=Database(settings);calls=[];mode={'rate':False,'offline':False,'incomplete':False,'refresh':False,'upload_unknown':False}
    def handle(request):
        calls.append(request)
        assert request.url.scheme=='https' and request.url.host=='www.strava.com'
        if mode['offline']:raise httpx.ConnectError('test-only',request=request)
        if request.url.path=='/oauth/token':
            body=parse_qs(request.content.decode())
            assert body['client_secret']==['test-secret-not-production']
            if body['grant_type']==['refresh_token']:
                if mode['refresh']:return httpx.Response(400,json={'message':'revoked'})
                return httpx.Response(200,json={'access_token':'rotated-access','refresh_token':'rotated-refresh','expires_at':int(time.time())+3600})
            id=202 if body.get('code')==['second'] else 101
            return httpx.Response(200,json={'access_token':f'test-access-{id}','refresh_token':f'test-refresh-{id}','expires_at':int(time.time())+3600,'athlete':{'id':id,'firstname':'Not stored'}})
        if request.url.path=='/oauth/deauthorize':return httpx.Response(200,json={'access_token':'revoked'})
        if mode['rate']:return httpx.Response(429,json={},headers={'Retry-After':'3600'})
        if request.url.path.endswith('/athlete/activities'):
            if mode['incomplete']:return httpx.Response(200,json=[{'id':1}])
            id=202 if '202' in request.headers.get('Authorization','') else 101
            return httpx.Response(200,json=[{'id':id,'name':'TEST ONLY','start_date':'2026-11-01T10:00:00Z','distance':1000,'moving_time':200,'elapsed_time':220,'sport_type':'Ride'}])
        if '/routes/' in request.url.path and request.url.path.endswith('/export_gpx'):return httpx.Response(200,text=GPX)
        if request.url.path.endswith('/routes'):return httpx.Response(200,json=[{'id':123,'name':'TEST ONLY'}])
        if request.method=='POST' and request.url.path.endswith('/uploads'):
            if mode['upload_unknown']:return httpx.Response(503,json={})
            return httpx.Response(201,json={'id':888,'activity_id':999})
        return httpx.Response(200,json={'id':101,'name':'TEST ONLY','distance':1000,'moving_time':200,'elapsed_time':220,'start_date':'2026-11-01T10:00:00Z'})
    provider=Strava(db,httpx.Client(transport=httpx.MockTransport(handle)))
    app=create_app(settings,provider);client=TestClient(app)
    token=client.post('/api/v1/auth/register',json={'username':'owner','password':PASSWORD,'invitation':BOOTSTRAP}).json()['access_token']
    client.headers['Authorization']='Bearer '+token
    yield client,db,provider,calls,mode,settings
    provider.client.close();client.close()

def other(client):
    invitation=client.post('/api/v1/admin/invitations').json()['invitation']
    result=client.post('/api/v1/auth/register',json={'username':'other','password':PASSWORD,'invitation':invitation})
    assert result.status_code==201
    return {'Authorization':'Bearer '+result.json()['access_token']}

def connect(client,code='first',headers=None,scopes=None):
    state=base64.urlsafe_b64encode(hashlib.sha256((code+str(time.time_ns())).encode()).digest()).decode().rstrip('=')
    verifier='v'*64;challenge=base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
    start=client.post('/api/v1/integrations/strava/authorize',headers=headers,json={'state':state,'code_challenge':challenge,'scopes':scopes or ['activity:read','read','activity:write']})
    assert start.status_code==200,start.text
    url=start.json()['authorization_url'];assert url.startswith('https://www.strava.com/oauth/authorize?')
    callback=client.get('/oauth/strava/callback',params={'state':state,'code':code,'scope':','.join(scopes or ['activity:read','read','activity:write'])})
    assert callback.status_code==200
    import html,re
    target=html.unescape(re.search(r'href="([^"]+)"',callback.text)[1]);query=parse_qs(urlsplit(target).query)
    return {'state':state,'handoff':query['handoff'][0],'code_verifier':verifier}

def grant(client,code='first',headers=None):
    confirmation=connect(client,code,headers)
    result=client.post('/api/v1/integrations/strava/confirm',headers=headers,json=confirmation)
    assert result.status_code==200,result.text
    return result.json()

def ride():return {'v':1,'id':'ride-test','state':'saved','distance':1,'elapsed':220000,'moving':200000,'paused':20000,'gain':0,'loss':0,'points':[[51,4,0,'2026-11-01T10:00:00Z'],[51.01,4.01,0,'2026-11-01T10:03:40Z']]}

def test_health_and_anonymous_auth(setup):
    client,*_=setup
    assert client.get('/healthz').json()['status']=='ok'
    assert client.get('/api/v1/me',headers={'Authorization':''}).status_code==401
    assert client.get('/api/v1/server').json()['callback_url']=='https://velo.example.test/oauth/strava/callback'

def test_single_use_invitation_and_admin_boundary(setup):
    client,*_=setup;header=other(client)
    assert client.post('/api/v1/admin/invitations',headers=header).status_code==403
    assert client.post('/api/v1/auth/register',json={'username':'intruder','password':PASSWORD,'invitation':BOOTSTRAP}).status_code==403

def test_login_logout_expiry_and_no_password_echo(setup):
    client,db,*_=setup
    invalid=client.post('/api/v1/auth/login',json={'username':'owner','password':'tiny'})
    assert invalid.status_code==422 and 'tiny' not in invalid.text
    for _ in range(5):assert client.post('/api/v1/auth/login',json={'username':'owner','password':'incorrect-password'}).status_code==401
    assert client.post('/api/v1/auth/login',json={'username':'owner','password':PASSWORD}).status_code==429
    assert client.post('/api/v1/auth/logout').status_code==200
    assert client.get('/api/v1/me').status_code==401

def test_document_isolation_idempotence_and_conflicts(setup):
    client,db,*_=setup;header=other(client)
    first=client.put('/api/v1/data/rides/ride-test',json={'payload':ride()})
    assert first.status_code==200
    assert client.put('/api/v1/data/rides/ride-test',json={'payload':ride()}).json()['unchanged']
    changed=ride();changed['distance']=2
    assert client.put('/api/v1/data/rides/ride-test',json={'payload':changed}).status_code==409
    assert client.put('/api/v1/data/rides/ride-test',json={'payload':changed,'expected_revision':first.json()['revision']}).status_code==200
    assert client.get('/api/v1/data/rides',headers=header).json()['items']==[]
    assert PASSWORD.encode() not in db.path.read_bytes()
    with db.connect() as con:assert b'2026-11-01' not in con.execute('SELECT payload FROM documents').fetchone()[0]

@pytest.mark.parametrize('payload',[{'v':1,'points':[[91,4,0,'2026-11-01']]},{'v':1,'points':[[51,181,0,'2026-11-01']]},{'v':1,'points':[[51,4,0,'invalid']]},{'v':1,'distance':-1,'points':[]}])
def test_invalid_gps_never_saved(setup,payload):
    client,*_=setup
    assert client.put('/api/v1/data/rides/bad',json={'payload':payload}).status_code==422
    assert client.get('/api/v1/data/rides').json()['items']==[]

def test_strava_data_not_accepted_as_own_backup(setup):
    client,*_=setup
    assert client.put('/api/v1/data/routes/strava:101:1',json={'payload':{'points':[[51,4],[51.1,4.1]]}}).status_code==422

def test_oauth_tokens_only_on_server_and_replay_rejected(setup):
    client,db,provider,calls,*_=setup
    confirmation=connect(client)
    assert not any(k in confirmation for k in ('access_token','refresh_token','code'))
    result=client.post('/api/v1/integrations/strava/confirm',json=confirmation)
    assert result.status_code==200 and result.json()['connected']
    assert 'test-access' not in result.text and 'test-refresh' not in result.text
    assert client.post('/api/v1/integrations/strava/confirm',json=confirmation).status_code==400
    with db.connect() as con:
        row=con.execute('SELECT tokens FROM connections').fetchone()
        assert b'test-access' not in row[0]
        assert db.open(row[0])['access_token']=='test-access-101'

def test_oauth_wrong_verifier_and_cross_user_handoff(setup):
    client,*_=setup;second=other(client);proof=connect(client)
    assert client.post('/api/v1/integrations/strava/confirm',headers=second,json=proof).status_code==400
    wrong={**proof,'code_verifier':'w'*64}
    assert client.post('/api/v1/integrations/strava/confirm',json=wrong).status_code==400
    assert client.post('/api/v1/integrations/strava/confirm',json=proof).status_code==200

def test_oauth_unknown_state_and_callback_replay(setup):
    client,*_=setup
    assert client.get('/oauth/strava/callback',params={'state':'unknown','code':'x','scope':'read'}).status_code==400
    proof=connect(client)
    assert client.get('/oauth/strava/callback',params={'state':proof['state'],'code':'x','scope':'read'}).status_code==400

def test_oauth_survives_restart(setup):
    client,db,provider,_,_,settings=setup;proof=connect(client)
    restarted=TestClient(create_app(settings,provider));restarted.headers.update(client.headers)
    assert restarted.post('/api/v1/integrations/strava/confirm',json=proof).status_code==200
    restarted.close()

def test_multiple_accounts_remain_separate(setup):
    client,db,provider,*_=setup;second=other(client)
    grant(client);grant(client,'second',second)
    worker=Worker(db,provider)
    while worker.tick():
        with db.connect() as con:
            if not con.execute("SELECT 1 FROM jobs WHERE status='pending' AND next_at<=?",(int(time.time()),)).fetchone():break
    own=client.get('/api/v1/integrations/strava/activities').json();other_data=client.get('/api/v1/integrations/strava/activities',headers=second).json()
    assert own[0]['data']['id']==101 and other_data[0]['data']['id']==202
    with db.connect() as con:assert con.execute('SELECT COUNT(*) FROM users').fetchone()[0]==2

def test_sync_jobs_deduplicate_and_activity_cache_is_not_own_ride(setup):
    client,db,provider,*_=setup;grant(client)
    a=client.post('/api/v1/integrations/strava/sync').json()['job_id'];b=client.post('/api/v1/integrations/strava/sync').json()['job_id'];assert a==b
    Worker(db,provider).tick();assert client.get('/api/v1/jobs/'+a).json()['status']=='complete'
    assert len(client.get('/api/v1/integrations/strava/activities').json())==1
    assert client.get('/api/v1/data/rides').json()['items']==[]

def test_job_status_does_not_leak_across_users(setup):
    client,*_=setup;second=other(client);grant(client);job=client.post('/api/v1/integrations/strava/sync').json()['job_id']
    assert client.get('/api/v1/jobs/'+job,headers=second).status_code==404

def test_partial_import_does_not_advance_cursor(setup):
    client,db,provider,_,mode,_=setup;grant(client);mode['incomplete']=True;Worker(db,provider).tick()
    with db.connect() as con:assert con.execute('SELECT COUNT(*) FROM cursors').fetchone()[0]==0

def test_rate_limit_retry_after_persisted(setup):
    client,db,provider,_,mode,_=setup;grant(client);mode['rate']=True;Worker(db,provider).tick()
    with db.connect() as con:
        row=con.execute('SELECT * FROM jobs').fetchone();assert row['status']=='pending' and row['next_at']>=int(time.time())+3500
        assert con.execute('SELECT next_at FROM quota').fetchone()[0]>=int(time.time())+3500

def test_refresh_rotation_is_server_only(setup):
    client,db,provider,*_=setup;grant(client);user=client.get('/api/v1/me').json()['id']
    with db.connect(True) as con:con.execute("UPDATE connections SET tokens=?",(db.seal({'access_token':'expired','refresh_token':'old','expires_at':1}),))
    assert provider.token(user)=='rotated-access'
    assert 'rotated' not in client.get('/api/v1/integrations/strava').text


def test_revoked_provider_refresh_clears_tokens_and_cache(setup):
    client,db,provider,_,mode,_=setup
    grant(client);Worker(db,provider).tick()
    user=client.get('/api/v1/me').json()['id']
    with db.connect(True) as con:con.execute('UPDATE connections SET tokens=?',(db.seal({'access_token':'expired','refresh_token':'revoked','expires_at':1}),))
    mode['refresh']=True
    with pytest.raises(ProviderError):provider.token(user)
    with db.connect() as con:
        row=con.execute('SELECT status,tokens FROM connections').fetchone()
        assert row['status']=='needs_reconnect' and db.open(row['tokens'])=={}
        assert con.execute('SELECT COUNT(*) FROM cache').fetchone()[0]==0


def test_expired_oauth_state_and_job_list_isolation(setup):
    client,db,*_=setup
    second=other(client)
    proof=connect(client)
    with db.connect(True) as con:con.execute('UPDATE oauth_states SET expires_at=0')
    assert client.post('/api/v1/integrations/strava/confirm',json=proof).status_code==400
    grant(client)
    assert client.get('/api/v1/jobs').json()
    assert client.get('/api/v1/jobs',headers=second).json()==[]

def test_upload_requires_optin_and_is_idempotent(setup):
    client,db,provider,calls,*_=setup;grant(client);client.put('/api/v1/data/rides/ride-test',json={'payload':ride()})
    assert client.post('/api/v1/integrations/strava/uploads/ride-test').status_code==403
    client.put('/api/v1/integrations/strava/preferences',json={'uploads':True})
    a=client.post('/api/v1/integrations/strava/uploads/ride-test').json()['job_id'];assert client.post('/api/v1/integrations/strava/uploads/ride-test').json()['job_id']==a
    worker=Worker(db,provider);worker.tick();worker.tick();assert client.get('/api/v1/jobs/'+a).json()['status']=='complete'
    assert len([r for r in calls if r.method=='POST' and r.url.path.endswith('/uploads')])==1
    client.post('/api/v1/integrations/strava/uploads/ride-test');worker.tick()
    assert len([r for r in calls if r.method=='POST' and r.url.path.endswith('/uploads')])==1

def test_uncertain_upload_never_blindly_retried(setup):
    client,db,provider,calls,mode,_=setup;grant(client);client.put('/api/v1/data/rides/ride-test',json={'payload':ride()});client.put('/api/v1/integrations/strava/preferences',json={'uploads':True})
    job=client.post('/api/v1/integrations/strava/uploads/ride-test').json()['job_id'];mode['upload_unknown']=True
    worker=Worker(db,provider);worker.tick();worker.tick();worker.tick()
    assert client.get('/api/v1/jobs/'+job).json()['status']=='needs_review'

def test_disconnect_always_deletes_server_tokens_and_cache(setup):
    client,db,provider,_,mode,_=setup;grant(client);Worker(db,provider).tick();mode['offline']=True
    result=client.delete('/api/v1/integrations/strava').json();assert result=={'disconnected':True,'revocation_confirmed':False}
    with db.connect() as con:
        assert con.execute('SELECT COUNT(*) FROM connections').fetchone()[0]==0
        assert con.execute('SELECT COUNT(*) FROM cache').fetchone()[0]==0

def test_backup_restore_excludes_provider_data_and_sessions(setup,tmp_path):
    client,db,provider,_,_,settings=setup;grant(client);Worker(db,provider).tick();client.put('/api/v1/data/rides/ride-test',json={'payload':ride()})
    backup=create_backup(db,tmp_path/'backup.velobackup');assert not backup.read_bytes().startswith(b'SQLite')
    restored_settings=Settings(tmp_path/'restore',settings.public_url,settings.encryption_keys,BOOTSTRAP)
    restore_backup(restored_settings,backup,True);restored=Database(restored_settings)
    with restored.connect() as con:
        assert con.execute('SELECT COUNT(*) FROM documents').fetchone()[0]==1
        for table in ('connections','cache','sessions','oauth_states'):assert con.execute('SELECT COUNT(*) FROM '+table).fetchone()[0]==0

def test_corrupt_backup_never_replaces_existing_database(setup,tmp_path):
    _,db,_,_,_,settings=setup;backup=create_backup(db,tmp_path/'good.velobackup');bad=tmp_path/'bad.velobackup';bad.write_bytes(backup.read_bytes()[:-50])
    target=Settings(tmp_path/'safe',settings.public_url,settings.encryption_keys,BOOTSTRAP);original=Database(target);before=original.path.read_bytes()
    with pytest.raises((ValueError,InvalidToken)):restore_backup(target,bad,True)
    assert original.path.read_bytes()==before

def test_missing_strava_configuration_never_claims_connected(tmp_path):
    settings=Settings(tmp_path,'https://velo.example.test',Fernet.generate_key().decode(),BOOTSTRAP)
    client=TestClient(create_app(settings));client.headers['Authorization']='Bearer '+client.post('/api/v1/auth/register',json={'username':'owner','password':PASSWORD,'invitation':BOOTSTRAP}).json()['access_token']
    assert client.get('/api/v1/integrations/strava').json()['connected'] is False
    assert client.post('/api/v1/integrations/strava/authorize',json={'state':'s'*43,'code_challenge':'c'*43,'scopes':['activity:read']}).status_code==409

def test_delete_account_cascades_owned_data(setup):
    client,db,*_=setup;client.put('/api/v1/data/settings/app',json={'payload':{'theme':'oled'}})
    assert client.request('DELETE','/api/v1/me',json={'password':PASSWORD}).status_code==200
    with db.connect() as con:
        assert con.execute('SELECT COUNT(*) FROM users').fetchone()[0]==0
        assert con.execute('SELECT COUNT(*) FROM documents').fetchone()[0]==0
    assert client.get('/api/v1/me').status_code==401
