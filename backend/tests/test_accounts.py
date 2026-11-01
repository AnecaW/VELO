import time
from test_api import setup, PASSWORD

def register(client,email='rider@example.test'):
    return client.post('/api/v1/accounts/register', json={'email':email,'password':PASSWORD})

def test_email_login_rotation_replay_logout(setup):
    client,db,*_=setup
    result=register(client)
    assert result.status_code==201
    tokens=result.json()
    assert tokens['expires_at'] <= time.time()+901
    login=client.post('/api/v1/accounts/login',json={'email':'RIDER@example.test','password':PASSWORD})
    assert login.status_code==200
    assert client.post('/api/v1/accounts/login',json={'email':'rider@example.test','password':'wrong-password-123'}).status_code==401
    rotated=client.post('/api/v1/accounts/refresh',json={'refresh_token':tokens['refresh_token']})
    assert rotated.status_code==200
    fresh=rotated.json()
    assert fresh['refresh_token']!=tokens['refresh_token']
    assert client.get('/api/v1/me',headers={'Authorization':'Bearer '+tokens['access_token']}).status_code==401
    assert client.post('/api/v1/accounts/refresh',json={'refresh_token':tokens['refresh_token']}).status_code==401
    assert client.get('/api/v1/me',headers={'Authorization':'Bearer '+fresh['access_token']}).status_code==401
    latest=login.json()
    assert client.post('/api/v1/accounts/logout',json={'refresh_token':latest['refresh_token']}).status_code==200
    assert client.post('/api/v1/accounts/refresh',json={'refresh_token':latest['refresh_token']}).status_code==401

def test_password_change_invalidates_all_sessions(setup):
    client,db,*_=setup
    tokens=register(client).json()
    header={'Authorization':'Bearer '+tokens['access_token']}
    changed=client.post('/api/v1/accounts/password',headers=header,json={'current_password':PASSWORD,'new_password':'new-password-for-test-123'})
    assert changed.status_code==200
    assert client.get('/api/v1/me',headers=header).status_code==401
    assert client.post('/api/v1/accounts/refresh',json={'refresh_token':tokens['refresh_token']}).status_code==401
    assert client.post('/api/v1/accounts/login',json={'email':'rider@example.test','password':'new-password-for-test-123'}).status_code==200
    with db.connect() as con:
        assert con.execute("SELECT password_hash FROM users WHERE email='rider@example.test'").fetchone()[0].startswith('$argon2id$')

def test_registration_limit_and_reset_configuration(setup):
    client,*_=setup
    assert client.post('/api/v1/accounts/password-reset',json={'email':'unknown@example.test'}).status_code==503
    for n in range(5):assert register(client,f'rider{n}@example.test').status_code==201
    assert register(client,'blocked@example.test').status_code==429

def test_refresh_expiry_and_migrations(setup):
    client,db,*_=setup
    tokens=register(client).json()
    with db.connect(True) as con:con.execute('UPDATE refresh_tokens SET expires_at=0')
    assert client.post('/api/v1/accounts/refresh',json={'refresh_token':tokens['refresh_token']}).status_code==401
    db.migrate()
    with db.connect() as con:assert con.execute('SELECT MAX(version) FROM schema_migrations').fetchone()[0]==4


def test_configured_reset_is_generic_single_use_and_revokes_sessions(setup,monkeypatch):
    client,db,*_=setup
    tokens=register(client).json()
    db.settings.smtp_host='smtp.example.test';db.settings.smtp_from='velo@example.test'
    sent=[]
    monkeypatch.setattr('velo_backend.accounts.send_reset',lambda settings,email,token:sent.append(token))
    known=client.post('/api/v1/accounts/password-reset',json={'email':'rider@example.test'})
    unknown=client.post('/api/v1/accounts/password-reset',json={'email':'unknown@example.test'})
    assert known.status_code==unknown.status_code==200 and known.json()==unknown.json()
    assert len(sent)==1
    assert client.get('/account/reset',params={'token':sent[0]}).status_code==200
    response=client.post('/account/reset',data={'token':sent[0],'password':'new-test-password-123'})
    assert response.status_code==200
    assert client.post('/account/reset',data={'token':sent[0],'password':'new-test-password-123'}).status_code==400
    assert client.post('/api/v1/accounts/refresh',json={'refresh_token':tokens['refresh_token']}).status_code==401
