import httpx
from test_api import setup, other, grant


def test_incremental_deletions_and_stale_writes_are_isolated(setup):
    client,db,*_=setup
    second=other(client)
    payload={'theme':'oled'}
    first=client.put('/api/v1/data/settings/app',json={'payload':payload}).json()
    page=client.get('/api/v1/data/settings?include_deleted=true').json()
    assert page['items'][0]['deleted'] is False
    deleted=client.delete('/api/v1/data/settings/app',params={'expected_revision':first['revision']})
    assert deleted.status_code==200
    assert deleted.json()['revision']>first['revision']
    changes=client.get('/api/v1/data/settings',params={'include_deleted':True,'after':first['revision']}).json()
    assert len(changes['items'])==1 and changes['items'][0]['deleted'] is True
    assert changes['items'][0]['payload'] is None
    assert client.get('/api/v1/data/settings',headers=second,params={'include_deleted':True}).json()['items']==[]
    assert client.put('/api/v1/data/settings/app',json={'payload':payload,'expected_revision':first['revision']}).status_code==409
    restored=client.put('/api/v1/data/settings/app',json={'payload':payload,'expected_revision':deleted.json()['revision']})
    assert restored.status_code==200
    assert client.delete('/api/v1/data/settings/app',params={'expected_revision':first['revision']}).status_code==409
    assert client.get('/api/v1/data/settings').json()['items'][0]['payload']==payload


def test_unicode_route_names_are_supported(setup):
    client,*_=setup
    response=client.put('/api/v1/data/routes/Fietsroute%20caf%C3%A9',json={'payload':{'name':'Fietsroute cafe','points':[[51,4],[51.1,4.1]]}})
    assert response.status_code==200


def test_user_route_names_with_slashes_and_punctuation_round_trip(setup):
    client,*_=setup
    path='/api/v1/data/routes/Fietsroute%20A%2FB%3F'
    response=client.put(path,json={'payload':{'name':'Fietsroute A/B?','points':[[51,4],[51.1,4.1]]}})
    assert response.status_code==200
    assert client.get('/api/v1/data/routes').json()['items'][0]['id']=='Fietsroute A/B?'
    assert client.delete(path,params={'expected_revision':response.json()['revision']}).status_code==200
    assert client.get('/api/v1/data/routes').json()['items']==[]


def test_job_retry_is_owned_and_uncertain_upload_requires_confirmation(setup):
    client,db,*_=setup
    second=other(client);grant(client)
    job=client.get('/api/v1/jobs').json()[0]['id']
    with db.connect(True) as con:con.execute("UPDATE jobs SET status='needs_review' WHERE id=?",(job,))
    assert client.post(f'/api/v1/jobs/{job}/retry',headers=second,json={'confirmed_no_duplicate':True}).status_code==404
    assert client.post(f'/api/v1/jobs/{job}/retry',json={}).status_code==409
    assert client.post(f'/api/v1/jobs/{job}/retry',json={'confirmed_no_duplicate':True}).status_code==200
    assert client.get('/api/v1/jobs/'+job).json()['status']=='pending'
    assert client.post(f'/api/v1/jobs/{job}/retry',json={'confirmed_no_duplicate':True}).status_code==409


def test_navigation_missing_configuration_and_validation(setup):
    client,*_=setup
    assert client.get('/api/v1/navigation/search?q=Brussels',headers={'Authorization':''}).status_code==401
    response=client.get('/api/v1/navigation/search?q=Brussels')
    assert response.status_code==503 and response.json()['error']['code']=='navigation_unavailable'
    assert client.post('/api/v1/navigation/directions',json={'coordinates':[[181,51],[4,51]],'profile':'cycling-road'}).status_code==422


def test_navigation_proxy_keeps_credentials_on_server(setup,monkeypatch,caplog):
    client,db,*_=setup
    db.settings.ors_api_key='test-only-ors-provider-key'
    calls=[]
    original=httpx.Client
    def handle(request):
        calls.append(request)
        assert request.url.host=='api.openrouteservice.org'
        assert request.headers['Authorization']=='test-only-ors-provider-key'
        return httpx.Response(200,json={'features':[]})
    monkeypatch.setattr('velo_backend.navigation.httpx.Client',lambda **kwargs:original(transport=httpx.MockTransport(handle),**kwargs))
    caplog.set_level('INFO')
    response=client.get('/api/v1/navigation/search?q=PRIVATE-HOME-ADDRESS')
    assert response.status_code==200 and response.json()=={'features':[]}
    assert 'provider-key' not in response.text
    assert 'api_key' not in str(calls[0].url)
    assert 'PRIVATE-HOME-ADDRESS' not in caplog.text
    assert 'test-only-ors-provider-key' not in caplog.text
