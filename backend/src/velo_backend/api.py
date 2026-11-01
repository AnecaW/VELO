import base64
import hashlib
import hmac
import html
import json
import math
import re
import secrets
import sqlite3
import time
import uuid
import logging
from datetime import datetime
from urllib.parse import urlencode
from fastapi import FastAPI, Request, Depends, Header
from fastapi.responses import JSONResponse, HTMLResponse, Response
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, Field, ConfigDict
from .config import Settings
from .storage import Database
from .security import digest,password_hash,password_valid,session
from .accounts import install_accounts
from .navigation import install_navigation
from .strava import Strava,ProviderError
from .jobs import enqueue,gpx

class Problem(Exception):
    def __init__(self,status,message,code='request_failed'):self.status,self.message,self.code=status,message,code
class Model(BaseModel):model_config=ConfigDict(extra='forbid')
class Credentials(Model):
    username:str=Field(min_length=3,max_length=64,pattern=r'^[A-Za-z0-9_.-]+$')
    password:str=Field(min_length=12,max_length=256)
class Register(Credentials): invitation:str=Field(default='',max_length=256)
class Authorization(Model):
    state:str=Field(pattern=r'^[A-Za-z0-9_=-]{32,128}$')
    code_challenge:str=Field(pattern=r'^[A-Za-z0-9_-]{43}$')
    scopes:list[str]=Field(min_length=1,max_length=5)
class Confirmation(Model):
    state:str=Field(max_length=128)
    handoff:str=Field(max_length=128)
    code_verifier:str=Field(pattern=r'^[A-Za-z0-9_-]{43,128}$')
class Preferences(Model):
    enabled:bool=True
    automatic:bool=False
    activities:bool=True
    routes:bool=False
    uploads:bool=False
class Document(Model):
    payload:dict
    expected_revision:int|None=Field(default=None,ge=0)
class Password(Model):password:str=Field(max_length=256)
class RetryJob(Model): confirmed_no_duplicate:bool=False

KINDS={'settings','rides','routes','training_plans','profiles','training_profile','training_results'}
SCOPES={'activity:read','activity:read_all','activity:write','read','read_all'}

def validate_document(kind,id,payload):
    if kind not in KINDS or not re.fullmatch(r'[^\x00-\x1f\x7f]{1,512}',id) or id.startswith('strava:') or payload.get('source')=='Strava':raise Problem(422,'Ongeldige lokale gegevens of externe API-cache.','invalid_document')
    try:
        if len(json.dumps(payload,allow_nan=False).encode())>10*1024*1024:raise ValueError()
        if kind=='rides':
            if payload.get('id')!=id:raise ValueError()
            if payload.get('v')!=1 or not isinstance(payload.get('points'),list):raise ValueError()
            for key in ('distance','elapsed','moving','paused','gain','loss'):
                if key in payload and (isinstance(payload[key],bool) or not isinstance(payload[key],(int,float)) or not math.isfinite(payload[key]) or payload[key]<0):raise ValueError()
            for point in payload['points']:
                if len(point)<4 or not all(isinstance(n,(int,float)) and not isinstance(n,bool) and math.isfinite(n) for n in point[:3]) or abs(point[0])>90 or abs(point[1])>180:raise ValueError()
                datetime.fromisoformat(point[3].replace('Z','+00:00'))
        if kind=='routes':
            if len(payload['points'])<2:raise ValueError()
            for p in payload['points']:
                if not all(isinstance(n,(int,float)) and math.isfinite(n) for n in p[:2]) or abs(p[0])>90 or abs(p[1])>180:raise ValueError()
        if kind=='training_plans':
            steps=payload['steps']
            if not steps or any(not isinstance(s['seconds'],int) or s['seconds']<=0 or not 1<=s['rpe']<=10 for s in steps):raise ValueError()
    except (ValueError,TypeError,KeyError,IndexError,AttributeError):raise Problem(422,'Gegevensvalidatie mislukt. Er is niets opgeslagen.','invalid_document') from None

def create_app(settings=None,provider=None):
    # HTTP client request logs can contain geocoding queries or OAuth details.
    logging.getLogger('httpx').setLevel(logging.WARNING)
    logging.getLogger('httpcore').setLevel(logging.WARNING)
    settings=settings or Settings.environment();settings.validate();db=Database(settings)
    strava=provider or Strava(db)
    app=FastAPI(title='VELO Self-Hosted API',version='3.1.0',docs_url=None,redoc_url=None,openapi_url=None)
    app.state.db,app.state.strava=db,strava
    dummy=password_hash(secrets.token_urlsafe(32))

    @app.exception_handler(Problem)
    async def problem(request,e):return JSONResponse({'error':{'code':e.code,'message':e.message}},status_code=e.status)
    @app.exception_handler(RequestValidationError)
    async def invalid(request,e):return JSONResponse({'error':{'code':'validation','message':'Ongeldige invoer. Controleer de velden.'}},status_code=422)
    @app.exception_handler(ProviderError)
    async def provider_error(request,e):return JSONResponse({'error':{'code':'reconnect' if e.authentication else 'provider_unavailable','message':e.message}},status_code=409 if e.authentication else 503,headers={'Retry-After':str(max(1,e.retry))})

    @app.middleware('http')
    async def headers(request,call_next):
        try:size=int(request.headers.get('content-length','0'))
        except ValueError:return JSONResponse({'error':{'message':'Ongeldige verzoekgrootte.'}},400)
        if size>12*1024*1024:return JSONResponse({'error':{'message':'Maximaal 12 MB per verzoek.'}},413)
        # Reject unbounded streamed uploads; the Android client sends Content-Length.
        if request.method in ('POST','PUT','PATCH') and 'content-length' not in request.headers:return JSONResponse({'error':{'message':'Content-Length vereist.'}},411)
        if request.url.path in ('/api/v1/auth/register','/api/v1/auth/login'):
            now=int(time.time());key=digest('legacy-auth:'+(request.client.host if request.client else 'unknown'))
            with db.connect(True) as con:
                row=con.execute('SELECT * FROM attempts WHERE key=?',(key,)).fetchone()
                count=row['count']+1 if row and row['until_at']>now else 1
                until=row['until_at'] if row and row['until_at']>now else now+900
                con.execute('INSERT OR REPLACE INTO attempts VALUES(?,?,?)',(key,count,until))
            if count>20:return JSONResponse({'error':{'code':'rate_limit','message':'Te veel pogingen. Probeer later opnieuw.'}},429)
        started=time.monotonic()
        try:response=await call_next(request)
        except Exception:
            logging.getLogger('velo').error('request_failed method=%s',request.method)
            return JSONResponse({'error':{'code':'internal','message':'Serverfout. Probeer later opnieuw.'}},500)
        logging.getLogger('velo').info('request method=%s status=%s duration_ms=%d',request.method,response.status_code,int((time.monotonic()-started)*1000))
        response.headers.update({'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'none'; frame-ancestors 'none'"})
        return response

    def user(authorization:str|None=Header(default=None)):
        if not authorization or not authorization.startswith('Bearer '):raise Problem(401,'Meld je aan bij je VELO-server.','unauthorized')
        with db.connect() as con:row=con.execute("SELECT u.*,s.digest AS session_digest FROM users u JOIN sessions s ON s.user_id=u.id WHERE s.digest=? AND s.expires_at>?",(digest(authorization[7:]),int(time.time()))).fetchone()
        if not row:raise Problem(401,'VELO-sessie verlopen. Meld opnieuw aan.','unauthorized')
        return dict(row)

    def admin(current=Depends(user)):
        if current['role']!='admin':raise Problem(403,'Alleen de serverbeheerder heeft toegang.','forbidden')
        return current

    @app.get('/healthz')
    def health():
        with db.connect() as con:con.execute('SELECT 1').fetchone()
        return {'status':'ok','version':'3.1.0'}

    @app.get('/api/v1/server')
    def server():
        with db.connect() as con:first=not bool(con.execute("SELECT 1 FROM server_state WHERE key='bootstrap_consumed'").fetchone())
        return {'name':'VELO','version':'3.1.0','registration_requires':'bootstrap' if first else 'invitation','strava_configured':settings.strava_ready,'strava_client_id':settings.strava_client_id,'callback_url':settings.public_url+'/oauth/strava/callback'}

    @app.post('/api/v1/auth/register',status_code=201)
    def register(body:Register):
        now=int(time.time());username=body.username.lower()
        with db.connect(True) as con:
            first=not bool(con.execute("SELECT 1 FROM server_state WHERE key='bootstrap_consumed'").fetchone())
            if first:
                if not settings.bootstrap_token or not hmac.compare_digest(body.invitation,settings.bootstrap_token):raise Problem(403,'Een geldige server-bootstrapcode is vereist.','invitation_required')
            else:
                invite=con.execute('SELECT digest FROM invites WHERE digest=? AND expires_at>?',(digest(body.invitation),now)).fetchone()
                if not invite:raise Problem(403,'Een geldige uitnodiging is vereist.','invitation_required')
            id=uuid.uuid4().hex
            try:con.execute('INSERT INTO users(id,username,password_hash,role,created_at) VALUES(?,?,?,?,?)',(id,username,password_hash(body.password),'admin' if first else 'user',now))
            except sqlite3.IntegrityError:raise Problem(409,'Deze gebruikersnaam kan niet worden geregistreerd.','conflict') from None
            if first:con.execute("INSERT INTO server_state VALUES('bootstrap_consumed','1')")
            else:con.execute('DELETE FROM invites WHERE digest=?',(digest(body.invitation),))
        return {**session(db,id),'user':{'id':id,'username':username,'role':'admin' if first else 'user'}}

    @app.post('/api/v1/auth/login')
    def login(body:Credentials,request:Request):
        now=int(time.time());key=digest(body.username.lower()+':'+(request.client.host if request.client else 'unknown'))
        with db.connect(True) as con:
            row=con.execute('SELECT * FROM attempts WHERE key=?',(key,)).fetchone()
            if row and row['until_at']>now and row['count']>=5:raise Problem(429,'Te veel aanmeldpogingen. Probeer over een kwartier opnieuw.','rate_limit')
            count=row['count']+1 if row and row['until_at']>now else 1
            con.execute('INSERT INTO attempts VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET count=excluded.count,until_at=excluded.until_at',(key,count,now+900))
            account=con.execute('SELECT * FROM users WHERE username=?',(body.username.lower(),)).fetchone()
        if not password_valid(body.password,account['password_hash'] if account else dummy):raise Problem(401,'Gebruikersnaam of wachtwoord is onjuist.','invalid_credentials')
        with db.connect(True) as con:con.execute('DELETE FROM attempts WHERE key=?',(key,))
        return {**session(db,account['id']),'user':{'id':account['id'],'username':account['username'],'role':account['role']}}

    @app.post('/api/v1/auth/logout')
    def logout(current=Depends(user)):
        with db.connect(True) as con:
            con.execute('DELETE FROM refresh_tokens WHERE access_digest=?',(current['session_digest'],))
            con.execute('DELETE FROM sessions WHERE digest=?',(current['session_digest'],))
        return {'logged_out':True}

    @app.get('/api/v1/me')
    def me(current=Depends(user)):return {k:current[k] for k in ('id','username','email','role','created_at')}

    @app.post('/api/v1/admin/invitations',status_code=201)
    def invite(current=Depends(admin)):
        token=secrets.token_urlsafe(32);expiry=int(time.time())+86400
        with db.connect(True) as con:con.execute('INSERT INTO invites VALUES(?,?,?)',(digest(token),expiry,current['id']))
        return {'invitation':token,'expires_at':expiry}

    @app.get('/api/v1/admin/status')
    def admin_status(current=Depends(admin)):
        with db.connect() as con:users=con.execute('SELECT COUNT(*) FROM users').fetchone()[0];version=con.execute('SELECT MAX(version) FROM schema_migrations').fetchone()[0]
        return {'users':users,'schema_version':version,'strava_configured':settings.strava_ready,'callback_url':settings.public_url+'/oauth/strava/callback'}

    @app.delete('/api/v1/me')
    def delete_account(body:Password,current=Depends(user)):
        if not password_valid(body.password,current['password_hash']):raise Problem(401,'Wachtwoord onjuist.','invalid_credentials')
        revoked=strava.revoke(current['id'])
        with db.connect(True) as con:con.execute('DELETE FROM users WHERE id=?',(current['id'],))
        return {'deleted':True,'strava_revocation_confirmed':revoked}

    def connection_info(current):
        row=strava.connection(current['id'])
        return {'connected':bool(row and row['status']=='connected'),'status':row['status'] if row else 'disconnected','athlete':{'id':int(row['athlete_id'])} if row else None,'scope':row['scope'] if row else '', 'last_sync':row['last_sync'] if row else None,'error':row['error'] if row else None,'preferences':json.loads(row['preferences']) if row else Preferences().model_dump(),'configured':settings.strava_ready}

    @app.get('/api/v1/integrations/strava')
    def strava_info(current=Depends(user)):return connection_info(current)

    @app.post('/api/v1/integrations/strava/authorize')
    def authorize(body:Authorization,current=Depends(user)):
        if not settings.strava_ready:raise Problem(409,'Configureer Strava client-ID en client secret uitsluitend op je server.','not_configured')
        if not set(body.scopes)<=SCOPES:raise Problem(422,'Ongeldige Strava-rechten.','invalid_scope')
        with db.connect(True) as con:
            con.execute('DELETE FROM oauth_states WHERE expires_at<?',(int(time.time()),))
            if con.execute('SELECT COUNT(*) FROM oauth_states WHERE user_id=?',(current['id'],)).fetchone()[0]>=5:raise Problem(429,'Te veel openstaande autorisaties. Probeer later opnieuw.','rate_limit')
            try:con.execute('INSERT INTO oauth_states(state,user_id,challenge,scopes,expires_at) VALUES(?,?,?,?,?)',(body.state,current['id'],body.code_challenge,','.join(body.scopes),int(time.time())+600))
            except sqlite3.IntegrityError:raise Problem(409,'Deze autorisatie is al gestart. Start opnieuw.','conflict') from None
        return {'authorization_url':'https://www.strava.com/oauth/authorize?'+urlencode({'client_id':settings.strava_client_id,'redirect_uri':settings.public_url+'/oauth/strava/callback','response_type':'code','approval_prompt':'force','state':body.state,'scope':','.join(body.scopes)})}

    @app.get('/oauth/strava/callback',response_class=HTMLResponse)
    def callback(request:Request):
        query=request.query_params
        if any(len(query.getlist(k))!=1 for k in query):raise Problem(400,'Dubbele OAuth-parameters.','invalid_callback')
        state=query.get('state','');now=int(time.time())
        with db.connect(True) as con:
            row=con.execute("SELECT * FROM oauth_states WHERE state=? AND expires_at>? AND status='pending'",(state,now)).fetchone()
            if not row:raise Problem(400,'Autorisatie verlopen of al gebruikt. Start opnieuw.','invalid_state')
            con.execute("UPDATE oauth_states SET status='exchanging' WHERE state=?",(state,))
        granted=set(re.split('[, ]+',query.get('scope','')))-{''};requested=set(row['scopes'].split(','));error=None
        if query.get('error') or not query.get('code') or not granted<=requested|{'read'}:error='Strava-toestemming geweigerd of ongeldig.'
        else:
            try:
                token=strava.exchange(query['code']);athlete=token.get('athlete',{}).get('id')
                if not isinstance(athlete,int):raise ProviderError('Strava-antwoord mist een account-ID.')
                safe={k:token[k] for k in ('access_token','refresh_token','expires_at')}
                with db.connect(True) as con:
                    old=con.execute("SELECT athlete_id,preferences FROM connections WHERE user_id=? AND provider='strava'",(row['user_id'],)).fetchone()
                    if old and old['athlete_id']!=str(athlete):raise Problem(409,'Ontkoppel eerst het bestaande Strava-account.','account_mismatch')
                    preferences=old['preferences'] if old else json.dumps(Preferences().model_dump())
                    con.execute("INSERT INTO connections(user_id,provider,athlete_id,tokens,scope,connected_at,preferences) VALUES(?,'strava',?,?,?,?,?) ON CONFLICT(user_id,provider) DO UPDATE SET tokens=excluded.tokens,scope=excluded.scope,status='connected',error=NULL",(row['user_id'],str(athlete),db.seal(safe),','.join(sorted(granted)),now,preferences))
            except (ProviderError,sqlite3.IntegrityError,Problem):error='Koppeling niet voltooid. Controleer Strava-toegang en of het account al gekoppeld is.'
        handoff=secrets.token_urlsafe(32)
        with db.connect(True) as con:con.execute('UPDATE oauth_states SET status=?,handoff_digest=? WHERE state=?',('error' if error else 'ready',digest(handoff),state))
        target='ultimatebike://oauth/strava?'+urlencode({'state':state,'handoff':handoff})
        return HTMLResponse('<!doctype html><meta name="viewport" content="width=device-width"><title>VELO</title><h1>Terug naar VELO</h1><p>'+('Koppeling niet voltooid.' if error else 'Strava heeft je toestemming verwerkt. Tokens blijven op je eigen server.')+'</p><p><a href="'+html.escape(target,quote=True)+'">Open VELO</a></p>')

    @app.post('/api/v1/integrations/strava/confirm')
    def confirm(body:Confirmation,current=Depends(user)):
        proof=base64.urlsafe_b64encode(hashlib.sha256(body.code_verifier.encode()).digest()).decode().rstrip('=')
        with db.connect(True) as con:
            row=con.execute('SELECT * FROM oauth_states WHERE state=? AND user_id=? AND expires_at>?',(body.state,current['id'],int(time.time()))).fetchone()
            if not row or row['status'] not in ('ready','error') or not hmac.compare_digest(row['challenge'],proof) or not hmac.compare_digest(row['handoff_digest'] or '',digest(body.handoff)):raise Problem(400,'Ongeldige of verlopen accountbevestiging.','invalid_handoff')
            con.execute('DELETE FROM oauth_states WHERE state=?',(body.state,))
        if row['status']=='error':raise Problem(409,'Strava-toestemming geweigerd of koppeling niet voltooid.','oauth_rejected')
        enqueue(db,current['id'])
        return connection_info(current)

    @app.put('/api/v1/integrations/strava/preferences')
    def preferences(body:Preferences,current=Depends(user)):
        with db.connect(True) as con:
            if not con.execute("SELECT 1 FROM connections WHERE user_id=? AND provider='strava'",(current['id'],)).fetchone():raise Problem(409,'Verbind eerst Strava.','not_connected')
            con.execute("UPDATE connections SET preferences=?,next_sync=? WHERE user_id=? AND provider='strava'",(body.model_dump_json(),int(time.time()),current['id']))
        return connection_info(current)

    @app.delete('/api/v1/integrations/strava')
    def disconnect(current=Depends(user)):
        revoked=strava.revoke(current['id'])
        with db.connect(True) as con:
            for table in ('connections','cache','cursors','jobs','sync_history'):con.execute(f"DELETE FROM {table} WHERE user_id=? AND provider='strava'",(current['id'],))
            con.execute('DELETE FROM oauth_states WHERE user_id=?',(current['id'],))
        return {'disconnected':True,'revocation_confirmed':revoked}

    @app.post('/api/v1/integrations/strava/sync',status_code=202)
    def sync(current=Depends(user)):
        if not connection_info(current)['connected']:raise Problem(409,'Strava niet verbonden.','not_connected')
        return {'job_id':enqueue(db,current['id']),'status':'pending'}

    @app.get('/api/v1/integrations/strava/activities')
    def activities(current=Depends(user)):
        db.cleanup()
        with db.connect() as con:rows=con.execute("SELECT * FROM cache WHERE user_id=? AND provider='strava' AND kind='activities' ORDER BY id DESC",(current['id'],)).fetchall()
        return [{'data':db.open(r['payload']),'synced_at':r['synced_at'],'expires_at':r['expires_at']} for r in rows]

    @app.get('/api/v1/integrations/strava/activities/{id}')
    def activity_detail(id:int,current=Depends(user)):
        with db.connect() as con:row=con.execute("SELECT * FROM cache WHERE user_id=? AND provider='strava' AND kind='activities' AND id=? AND expires_at>?",(current['id'],str(id),int(time.time()))).fetchone()
        if not row:raise Problem(404,'Activiteit niet in je actuele Strava-cache.','not_found')
        response=strava.request(current['id'],'GET',f'activities/{id}')
        if response.status_code==404:
            with db.connect(True) as con:con.execute("DELETE FROM cache WHERE user_id=? AND provider='strava' AND kind='activities' AND id=?",(current['id'],str(id)))
            raise Problem(404,'Activiteit verwijderd bij Strava.','not_found')
        result=response.json();strava.cache(current['id'],'activities',id,result);return result

    @app.get('/api/v1/integrations/strava/routes')
    def routes(current=Depends(user)):
        db.cleanup()
        with db.connect() as con:rows=con.execute("SELECT * FROM cache WHERE user_id=? AND provider='strava' AND kind='routes'",(current['id'],)).fetchall()
        return [{'data':db.open(r['payload']),'synced_at':r['synced_at'],'expires_at':r['expires_at']} for r in rows]

    @app.delete('/api/v1/integrations/strava/cache')
    def clear_cache(current=Depends(user)):
        with db.connect(True) as con:
            con.execute("DELETE FROM cache WHERE user_id=? AND provider='strava'",(current['id'],));con.execute("DELETE FROM cursors WHERE user_id=? AND provider='strava'",(current['id'],))
        return {'deleted':True}

    @app.post('/api/v1/integrations/strava/uploads/{ride_id}',status_code=202)
    def upload(ride_id:str,current=Depends(user)):
        info=connection_info(current)
        if not info['connected'] or not info['preferences'].get('enabled',True) or not info['preferences'].get('uploads') or 'activity:write' not in info['scope'].split(','):raise Problem(403,'Uploaden vereist een verbonden account, toestemming en uploadrechten.','upload_disabled')
        with db.connect() as con:row=con.execute("SELECT payload FROM documents WHERE user_id=? AND kind='rides' AND id=?",(current['id'],ride_id)).fetchone()
        if not row:raise Problem(404,'Sla de eigen rit eerst op je VELO-server op.','not_found')
        try:gpx(db.open(row['payload']))
        except ProviderError:raise Problem(422,'Deze rit heeft geen bruikbaar eigen GPS-spoor.','invalid_track') from None
        return {'job_id':enqueue(db,current['id'],'upload',ride_id),'status':'queued'}

    @app.get('/api/v1/jobs')
    def jobs(current=Depends(user)):
        with db.connect() as con:rows=con.execute('SELECT * FROM jobs WHERE user_id=? ORDER BY updated_at DESC LIMIT 100',(current['id'],)).fetchall()
        return [{**{k:r[k] for k in ('id','provider','kind','job_key','status','attempts','next_at','error','updated_at')},'result':db.open(r['result']) if r['result'] else None} for r in rows]

    @app.get('/api/v1/jobs/{id}')
    def job(id:str,current=Depends(user)):
        with db.connect() as con:row=con.execute('SELECT * FROM jobs WHERE id=? AND user_id=?',(id,current['id'])).fetchone()
        if not row:raise Problem(404,'Taak niet gevonden.','not_found')
        return {k:row[k] for k in ('id','provider','kind','status','attempts','next_at','error','updated_at')}

    @app.get('/api/v1/sync/history')
    def history(current=Depends(user)):
        with db.connect() as con:rows=con.execute('SELECT provider,status,message,created_at FROM sync_history WHERE user_id=? ORDER BY created_at DESC LIMIT 100',(current['id'],)).fetchall()
        return [dict(r) for r in rows]

    @app.post('/api/v1/jobs/{id}/retry')
    def retry_job(id:str,body:RetryJob,current=Depends(user)):
        with db.connect(True) as con:
            row=con.execute('SELECT * FROM jobs WHERE id=? AND user_id=?',(id,current['id'])).fetchone()
            if not row:raise Problem(404,'Taak niet gevonden.','not_found')
            if row['status'] not in ('failed','needs_review'):raise Problem(409,'Deze taak kan niet opnieuw worden gestart.','invalid_job_state')
            if row['status']=='needs_review' and not body.confirmed_no_duplicate:raise Problem(409,'Controleer eerst bij Strava of deze rit al bestaat.','confirmation_required')
            con.execute("UPDATE jobs SET status='pending',next_at=?,lease_until=0,error=NULL,updated_at=? WHERE id=?",(int(time.time()),int(time.time()),id))
        return {'queued':True}

    @app.get('/api/v1/data/{kind}')
    def list_data(kind:str,after:int=0,include_deleted:bool=False,current=Depends(user)):
        if kind not in KINDS:raise Problem(404,'Gegevenstype niet gevonden.','not_found')
        if include_deleted:
            with db.connect() as con:
                rows=con.execute('SELECT id,payload,revision,updated_at,0 AS deleted FROM documents WHERE user_id=? AND kind=? AND revision>? UNION ALL SELECT id,NULL AS payload,revision,deleted_at AS updated_at,1 AS deleted FROM document_tombstones WHERE user_id=? AND kind=? AND revision>? ORDER BY revision LIMIT 100',(current['id'],kind,after,current['id'],kind,after)).fetchall()
            return {'items':[{'id':r['id'],'payload':None if r['deleted'] else db.open(r['payload']),'revision':r['revision'],'updated_at':r['updated_at'],'deleted':bool(r['deleted'])} for r in rows],'cursor':rows[-1]['revision'] if rows else after,'has_more':len(rows)==100}
        with db.connect() as con:rows=con.execute('SELECT * FROM documents WHERE user_id=? AND kind=? AND revision>? ORDER BY revision LIMIT 100',(current['id'],kind,after)).fetchall()
        return {'items':[{'id':r['id'],'payload':db.open(r['payload']),'revision':r['revision'],'updated_at':r['updated_at']} for r in rows],'cursor':rows[-1]['revision'] if rows else after,'has_more':len(rows)==100}

    @app.put('/api/v1/data/{kind}/{id:path}')
    def put_data(kind:str,id:str,body:Document,current=Depends(user)):
        validate_document(kind,id,body.payload)
        with db.connect(True) as con:
            old=con.execute('SELECT * FROM documents WHERE user_id=? AND kind=? AND id=?',(current['id'],kind,id)).fetchone()
            deleted=con.execute('SELECT revision FROM document_tombstones WHERE user_id=? AND kind=? AND id=?',(current['id'],kind,id)).fetchone()
            if deleted and body.expected_revision!=deleted['revision']:raise Problem(409,'Deze gegevens zijn op een ander toestel verwijderd.','revision_conflict')
            if old and db.open(old['payload'])==body.payload:return {'id':id,'revision':old['revision'],'unchanged':True}
            if old and body.expected_revision!=old['revision']:raise Problem(409,'Servergegevens zijn gewijzigd. Los het conflict op voordat je overschrijft.','revision_conflict')
            counter=con.execute("SELECT value FROM server_state WHERE key='document_revision'").fetchone();revision=int(counter['value'])+1 if counter else 1
            con.execute("INSERT INTO server_state VALUES('document_revision',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",(str(revision),))
            con.execute('INSERT INTO documents VALUES(?,?,?,?,?,?) ON CONFLICT(user_id,kind,id) DO UPDATE SET payload=excluded.payload,revision=excluded.revision,updated_at=excluded.updated_at',(current['id'],kind,id,db.seal(body.payload),revision,int(time.time())))
            con.execute('DELETE FROM document_tombstones WHERE user_id=? AND kind=? AND id=?',(current['id'],kind,id))
        return {'id':id,'revision':revision,'unchanged':False}

    @app.delete('/api/v1/data/{kind}/{id:path}')
    def delete_data(kind:str,id:str,expected_revision:int|None=None,current=Depends(user)):
        if kind not in KINDS:raise Problem(404,'Gegevenstype niet gevonden.','not_found')
        with db.connect(True) as con:
            old=con.execute('SELECT revision FROM documents WHERE user_id=? AND kind=? AND id=?',(current['id'],kind,id)).fetchone()
            tombstone=con.execute('SELECT revision FROM document_tombstones WHERE user_id=? AND kind=? AND id=?',(current['id'],kind,id)).fetchone()
            if not old:return {'deleted':True,'revision':tombstone['revision'] if tombstone else None,'local_device_data_unchanged':True}
            if expected_revision is not None and expected_revision!=old['revision']:raise Problem(409,'Gegevens zijn op een ander toestel gewijzigd.','revision_conflict')
            counter=con.execute("SELECT value FROM server_state WHERE key='document_revision'").fetchone();revision=int(counter['value'])+1 if counter else 1
            con.execute("INSERT INTO server_state VALUES('document_revision',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",(str(revision),))
            con.execute('DELETE FROM documents WHERE user_id=? AND kind=? AND id=?',(current['id'],kind,id))
            con.execute('INSERT INTO document_tombstones VALUES(?,?,?,?,?) ON CONFLICT(user_id,kind,id) DO UPDATE SET revision=excluded.revision,deleted_at=excluded.deleted_at',(current['id'],kind,id,revision,int(time.time())))
        return {'deleted':True,'revision':revision,'local_device_data_unchanged':True}
    install_accounts(app, db, user, Problem)
    install_navigation(app, db, user, Problem)
    return app
