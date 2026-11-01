import copy
import hashlib
import io
import json
import pytest
from velo_backend.updater import UpdateSettings,Portainer,Updater,latest_release

OLD='ghcr.io/anecaw/velo-backend@sha256:'+'1'*64
NEW='ghcr.io/anecaw/velo-backend@sha256:'+'2'*64
REF='refs/tags/backend-'+'a'*40

def settings(tmp_path):
    return UpdateSettings('https://portainer.example.test:9443','0'*64,'test-api-key-not-production',4,'tcp://agent.example.test:9001',25,state_dir=tmp_path)

class FakePortainer:
    def __init__(self):
        self.stack={'Id':25,'Name':'velo','EndpointId':4,'GitConfig':{'URL':'https://github.com/AnecaW/VELO','ReferenceName':'refs/heads/main'},'Env':[{'name':'VELO_IMAGE','value':OLD},{'name':'VELO_ENCRYPTION_KEYS','value':'test-private-encryption-key'}]}
        self.calls=[];self.backup_failed=False;self.agent='tcp://agent.example.test:9001'
    def request(self,method,path,body=None,raw=False):
        self.calls.append((method,path,body))
        if path=='/api/endpoints/4':return {'URL':self.agent,'Type':2}
        if path=='/api/stacks/25':return copy.deepcopy(self.stack)
        if '/containers/json?' in path:return [{'Id':'backup','State':'running','Labels':{'com.docker.compose.service':'backup'}}]
        if path.endswith('/containers/backup/exec'):return {'Id':'exec-test'}
        if path.endswith('/exec/exec-test/start'):return b''
        if path.endswith('/exec/exec-test/json'):return {'Running':False,'ExitCode':1 if self.backup_failed else 0}
        if method=='PUT':
            self.stack['Env']=copy.deepcopy(body['Env']);self.stack['GitConfig']['ReferenceName']=body['RepositoryReferenceName'];return {}
        raise AssertionError(path)

def test_certificate_mismatch_never_sends_api_key(tmp_path,monkeypatch):
    sent=[]
    class Socket:
        def getpeercert(self,binary_form):return b'unrecognized certificate'
    class Connection:
        sock=Socket()
        def __init__(self,*args,**kwargs):pass
        def connect(self):pass
        def request(self,*args,**kwargs):sent.append(kwargs)
        def close(self):pass
    monkeypatch.setattr('velo_backend.updater.http.client.HTTPSConnection',Connection)
    with pytest.raises(ValueError,match='fingerprint'):Portainer(settings(tmp_path)).request('GET','/api/stacks')
    assert sent==[]

def test_wrong_agent_prevents_any_mutation(tmp_path):
    client=FakePortainer();client.agent='tcp://wrong-agent.example.test:9001'
    updater=Updater(settings(tmp_path),client,lambda:{'image':NEW,'reference':REF})
    with pytest.raises(ValueError,match='Agent'):updater.run_once()
    assert all(method=='GET' for method,_,_ in client.calls)

def test_update_backs_up_preserves_secrets_and_never_prunes(tmp_path):
    client=FakePortainer();updater=Updater(settings(tmp_path),client,lambda:{'image':NEW,'reference':REF})
    updater._healthy=lambda image:image==NEW
    assert updater.run_once()=='updated'
    command=next(body['Cmd'] for method,path,body in client.calls if path.endswith('/containers/backup/exec'))
    assert command[:5]==['python','-m','velo_backend.cli','backup','--file']
    deployment=next(body for method,path,body in client.calls if method=='PUT')
    assert deployment['Prune'] is False and deployment['PullImage'] is True
    assert {'name':'VELO_ENCRYPTION_KEYS','value':'test-private-encryption-key'} in deployment['Env']
    assert not (tmp_path/'pending.json').exists()
    assert updater.run_once()=='unchanged'

def test_failed_backup_prevents_deployment(tmp_path):
    client=FakePortainer();client.backup_failed=True
    updater=Updater(settings(tmp_path),client,lambda:{'image':NEW,'reference':REF})
    with pytest.raises(RuntimeError,match='backup failed'):updater.run_once()
    assert not any(method=='PUT' for method,_,_ in client.calls)

def test_unhealthy_release_rolls_back_and_blocks_repeated_attempts(tmp_path):
    client=FakePortainer();updater=Updater(settings(tmp_path),client,lambda:{'image':NEW,'reference':REF})
    updater._healthy=lambda image:image==OLD
    assert updater.run_once()=='rolled_back'
    deployments=[body for method,path,body in client.calls if method=='PUT']
    assert len(deployments)==2
    assert deployments[-1]['RepositoryReferenceName']=='refs/heads/main'
    assert {'name':'VELO_IMAGE','value':OLD} in deployments[-1]['Env']
    assert updater.run_once()=='blocked'
    assert 'test-private-encryption-key' not in (tmp_path/'blocked.json').read_text()

def test_pending_update_is_reconciled_after_updater_restart(tmp_path):
    client=FakePortainer();updater=Updater(settings(tmp_path),client,lambda:None)
    updater._write('pending.json',{'image':NEW,'previous_image':OLD,'previous_reference':'refs/heads/main','reference':REF})
    updater._healthy=lambda image:image==OLD
    assert updater.run_once()=='rolled_back'

def test_release_manifest_rejects_foreign_image(tmp_path,monkeypatch):
    tag='backend-'+'a'*40
    releases=[{'tag_name':tag,'assets':[{'name':'velo-backend-release.json','browser_download_url':f'https://github.com/AnecaW/VELO/releases/download/{tag}/velo-backend-release.json'}]}]
    payloads=iter([releases,{'source_commit':'a'*40,'image':'ghcr.io/foreign/velo-backend@sha256:'+'a'*64}])
    monkeypatch.setattr('velo_backend.updater.urllib.request.urlopen',lambda *args,**kwargs:io.BytesIO(json.dumps(next(payloads)).encode()))
    with pytest.raises(ValueError,match='image repository'):latest_release(settings(tmp_path))


def test_release_selection_uses_publication_time_not_api_array_order(tmp_path,monkeypatch):
    releases=[]
    for letter,hour in [('a','12'),('b','13')]:
        tag='backend-'+letter*40
        releases.append({'tag_name':tag,'published_at':f'2026-11-01T{hour}:00:00Z','assets':[{'name':'velo-backend-release.json','browser_download_url':f'https://github.com/AnecaW/VELO/releases/download/{tag}/velo-backend-release.json'}]})
    calls=[]
    def open_url(request,**kwargs):
        url=request.full_url if hasattr(request,'full_url') else request
        calls.append(url)
        return io.BytesIO(json.dumps(releases if len(calls)==1 else {'source_commit':'b'*40,'image':NEW}).encode())
    monkeypatch.setattr('velo_backend.updater.urllib.request.urlopen',open_url)
    candidate=latest_release(settings(tmp_path))
    assert candidate['reference']=='refs/tags/backend-'+'b'*40
    assert 'backend-'+'b'*40 in calls[1]
