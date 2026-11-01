"""Small, least-privilege release updater for a private Portainer environment.

Only public, immutable release images from the configured repository are accepted.
No Docker socket is mounted. Certificate pinning happens BEFORE authentication.
The updater runs separately, so it can roll back an unhealthy application image.
"""
import hashlib
import http.client
import json
import logging
import os
import re
import ssl
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlencode, urlsplit
from .config import secret

log=logging.getLogger('velo.updater')

@dataclass
class UpdateSettings:
    portainer_url: str
    certificate_sha256: str
    api_key: str = field(repr=False)
    endpoint_id: int = 0
    agent_url: str = ''
    stack_id: int = 0
    stack_name: str = 'velo'
    repository: str = 'AnecaW/VELO'
    state_dir: Path = Path('/data')
    interval: int = 600
    health_timeout: int = 180

    def validate(self):
        origin=urlsplit(self.portainer_url)
        if origin.scheme!='https' or not origin.hostname or origin.username or origin.query or origin.fragment or origin.path not in ('','/'):
            raise ValueError('A Portainer HTTPS origin is required')
        if not re.fullmatch('[0-9a-f]{64}',self.certificate_sha256) or not self.api_key:
            raise ValueError('A confirmed certificate fingerprint and API key are required')
        if self.endpoint_id<=0 or self.stack_id<=0 or not self.agent_url:
            raise ValueError('An explicit target environment, Agent and stack are required')
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',self.repository):
            raise ValueError('Invalid release repository')

    @classmethod
    def environment(cls):
        result=cls(os.getenv('PORTAINER_URL','').rstrip('/'),os.getenv('PORTAINER_CERT_SHA256','').lower(),secret('PORTAINER_API_KEY'),int(os.getenv('VELO_DEPLOY_ENVIRONMENT_ID','0')),os.getenv('VELO_DEPLOY_AGENT_URL',''),int(os.getenv('VELO_DEPLOY_STACK_ID','0')),os.getenv('VELO_DEPLOY_STACK_NAME','velo'),os.getenv('VELO_UPDATE_REPOSITORY','AnecaW/VELO'),Path(os.getenv('VELO_UPDATER_STATE_DIR','/data')),max(60,int(os.getenv('VELO_UPDATE_INTERVAL','600'))))
        result.validate()
        return result

class Portainer:
    def __init__(self,settings):self.settings=settings
    def request(self,method,path,body=None,raw=False):
        origin=urlsplit(self.settings.portainer_url)
        connection=http.client.HTTPSConnection(origin.hostname,origin.port or 443,context=ssl._create_unverified_context(),timeout=240)
        try:
            connection.connect()
            actual=hashlib.sha256(connection.sock.getpeercert(binary_form=True)).hexdigest()
            if actual!=self.settings.certificate_sha256:
                raise ValueError('Portainer certificate fingerprint mismatch')
            # A credential is never sent until the certificate is verified.
            connection.request(method,path,body=json.dumps(body).encode() if body is not None else None,headers={'X-API-Key':self.settings.api_key,'Content-Type':'application/json'})
            response=connection.getresponse();data=response.read()
            if response.status>=400:raise RuntimeError(f'Portainer request failed: HTTP {response.status}')
            return data if raw else (json.loads(data) if data else None)
        finally:connection.close()

def latest_release(settings):
    request=urllib.request.Request(f'https://api.github.com/repos/{settings.repository}/releases?per_page=20',headers={'Accept':'application/vnd.github+json','User-Agent':'VELO-self-hosted-updater'})
    with urllib.request.urlopen(request,timeout=20) as response:releases=json.load(response)
    # API result order is not a release-order guarantee (for example after tag
    # publication races). Never select an older manifest just because it is first.
    for release in sorted(releases,key=lambda r:r.get('published_at') or r.get('created_at') or '',reverse=True):
        if release.get('draft') or release.get('prerelease'):continue
        tag=release.get('tag_name','')
        if not re.fullmatch(r'backend-[0-9a-f]{40}',tag):continue
        asset=next((a for a in release.get('assets',[]) if a['name']=='velo-backend-release.json'),None)
        if asset is None:continue
        url=asset['browser_download_url']
        expected=f'https://github.com/{settings.repository}/releases/download/{tag}/velo-backend-release.json'
        if url!=expected:raise ValueError('Unexpected release asset origin')
        with urllib.request.urlopen(url,timeout=20) as response:
            content=response.read(16385)
        if len(content)>16384:raise ValueError('Release manifest too large')
        manifest=json.loads(content)
        owner=settings.repository.split('/')[0].lower()
        if not re.fullmatch(r'ghcr\.io/'+re.escape(owner)+r'/velo-backend@sha256:[0-9a-f]{64}',manifest.get('image','')):
            raise ValueError('Unexpected image repository or mutable image reference')
        if manifest.get('source_commit')!=tag.removeprefix('backend-'):
            raise ValueError('Release source does not match its tag')
        return {'image':manifest['image'],'reference':'refs/tags/'+tag}
    return None

class Updater:
    def __init__(self,settings,client=None,release=None):
        settings.validate();self.settings=settings
        self.client=client or Portainer(settings)
        self.release=release or (lambda:latest_release(settings))
        settings.state_dir.mkdir(parents=True,exist_ok=True)

    def _path(self,name):return self.settings.state_dir/name
    def _write(self,name,value):
        destination=self._path(name);temporary=destination.with_suffix('.partial')
        temporary.write_text(json.dumps(value),encoding='utf-8');temporary.replace(destination)

    def _target(self):
        settings=self.settings
        endpoint=self.client.request('GET',f'/api/endpoints/{settings.endpoint_id}')
        if endpoint.get('URL')!=settings.agent_url or endpoint.get('Type')!=2:
            raise ValueError('Deployment environment does not match the configured Agent')
        stack=self.client.request('GET',f'/api/stacks/{settings.stack_id}')
        if stack.get('Name')!=settings.stack_name or stack.get('EndpointId')!=settings.endpoint_id:
            raise ValueError('Stack identity mismatch')
        repository=stack.get('GitConfig',{}).get('URL','').removesuffix('.git').rstrip('/')
        if repository.lower()!=('https://github.com/'+settings.repository).lower():
            raise ValueError('Stack repository mismatch')
        return stack

    def _containers(self):
        filters=json.dumps({'label':[f'com.docker.compose.project={self.settings.stack_name}']})
        return self.client.request('GET',f'/api/endpoints/{self.settings.endpoint_id}/docker/containers/json?'+urlencode({'all':'1','filters':filters}))

    def _backup(self):
        containers=self._containers()
        backup=next((c for c in containers if c.get('Labels',{}).get('com.docker.compose.service')=='backup' and c.get('State')=='running'),None)
        if backup is None:raise RuntimeError('A running backup service is required before update')
        name=datetime.now(timezone.utc).strftime('velo-%Y%m%dT%H%M%SZ-preupdate.velobackup')
        prefix=f'/api/endpoints/{self.settings.endpoint_id}/docker'
        result=self.client.request('POST',f"{prefix}/containers/{backup['Id']}/exec",{'AttachStdout':True,'AttachStderr':True,'Tty':False,'Cmd':['python','-m','velo_backend.cli','backup','--file','/backups/'+name]})
        self.client.request('POST',f"{prefix}/exec/{result['Id']}/start",{'Detach':False,'Tty':False},raw=True)
        state=self.client.request('GET',f"{prefix}/exec/{result['Id']}/json")
        if state.get('Running') or state.get('ExitCode')!=0:raise RuntimeError('Pre-update backup failed')

    def _deploy(self,stack,image,reference):
        environment=[dict(item) for item in stack.get('Env',[]) if item['name']!='VELO_IMAGE']
        environment.append({'name':'VELO_IMAGE','value':image})
        self.client.request('PUT',f'/api/stacks/{self.settings.stack_id}/git/redeploy?endpointId={self.settings.endpoint_id}',{'Env':environment,'RepositoryReferenceName':reference,'PullImage':True,'Prune':False})

    def _healthy(self,expected_image):
        deadline=time.monotonic()+self.settings.health_timeout
        while time.monotonic()<deadline:
            found={}
            for container in self._containers():
                service=container.get('Labels',{}).get('com.docker.compose.service')
                if service not in ('api','worker','backup'):continue
                inspected=self.client.request('GET',f"/api/endpoints/{self.settings.endpoint_id}/docker/containers/{container['Id']}/json")
                found[service]=inspected.get('State',{}).get('Health',{}).get('Status')=='healthy' and inspected.get('State',{}).get('Running') is True and inspected.get('Config',{}).get('Image')==expected_image
            if all(found.get(service) for service in ('api','worker','backup')):return True
            time.sleep(5)
        return False

    def _finish(self,stack,pending):
        if self._healthy(pending['image']):
            self._path('pending.json').unlink(missing_ok=True)
            return 'updated'
        self._deploy(stack,pending['previous_image'],pending['previous_reference'])
        restored=self._healthy(pending['previous_image'])
        self._write('blocked.json',{'image':pending['image']})
        self._path('pending.json').unlink(missing_ok=True)
        if not restored:raise RuntimeError('Rollback health check failed; operator action required')
        return 'rolled_back'

    def run_once(self):
        stack=self._target()
        if self._path('pending.json').exists():
            return self._finish(stack,json.loads(self._path('pending.json').read_text()))
        candidate=self.release()
        if candidate is None:return 'no_release'
        current=next((v['value'] for v in stack.get('Env',[]) if v['name']=='VELO_IMAGE'),None)
        if current==candidate['image']:return 'unchanged'
        if self._path('blocked.json').exists() and json.loads(self._path('blocked.json').read_text()).get('image')==candidate['image']:return 'blocked'
        if not current or not re.fullmatch(r'ghcr\.io/[a-z0-9_.-]+/velo-backend@sha256:[0-9a-f]{64}',current):
            raise ValueError('Current image must be pinned before enabling automatic updates')
        previous=stack['GitConfig'].get('ReferenceName')
        if not previous:raise ValueError('Current Git reference is missing')
        self._backup()
        pending={**candidate,'previous_image':current,'previous_reference':previous}
        self._write('pending.json',pending)
        try:self._deploy(stack,candidate['image'],candidate['reference'])
        except Exception:
            # A timed-out request may still have reached Portainer. Reconcile health
            # and observed image on the next run rather than blindly retrying.
            raise RuntimeError('Deployment request interrupted; reconciliation pending') from None
        return self._finish(stack,pending)

def run():
    logging.basicConfig(level=logging.INFO,format='%(asctime)s %(levelname)s %(name)s %(message)s')
    updater=Updater(UpdateSettings.environment())
    heartbeat=Path('/tmp/updater-heartbeat');heartbeat.touch()
    delay=updater.settings.interval
    while True:
        try:
            outcome=updater.run_once();heartbeat.touch();delay=updater.settings.interval
            log.log(logging.ERROR if outcome=='rolled_back' else logging.INFO,'automatic_update_%s',outcome)
        except Exception:
            log.error('automatic_update_deferred; check connectivity, permissions and the pinned certificate')
            delay=min(3600,max(60,delay*2))
        time.sleep(delay)
