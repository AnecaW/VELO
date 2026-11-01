"""Private Strava OAuth broker. Put behind HTTPS; never log request URLs/bodies.
The client secret stays here. No access/refresh tokens are persisted server-side.
S256 protects the broker-to-app handoff; Strava itself has no documented PKCE.
"""
import os, json, time, secrets, hmac, hashlib, base64, html, threading, re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlencode, urlparse, parse_qs
from urllib.request import Request, urlopen
from urllib.error import HTTPError

PENDING = {}
LOCK = threading.RLock()
CLIENT = os.environ['STRAVA_CLIENT_ID']
SECRET = os.environ['STRAVA_CLIENT_SECRET']
PUBLIC = os.environ['PUBLIC_URL'].rstrip('/')
SESSION = os.environ['SESSION_SECRET'].encode()
APP_RETURN = 'ultimatebike://oauth/strava'
assert urlparse(PUBLIC).scheme == 'https' and len(SESSION) >= 32
ALLOWED = {'activity:read', 'activity:read_all', 'activity:write', 'read', 'read_all'}

def credential():
    value = f'{int(time.time()) + 365*86400}:{secrets.token_urlsafe(24)}'
    return value + ':' + hmac.new(SESSION,value.encode(),hashlib.sha256).hexdigest()

def valid(value):
    try:
        payload, signature = value.rsplit(':',1)
        return int(payload.split(':')[0]) > time.time() and hmac.compare_digest(signature,hmac.new(SESSION,payload.encode(),hashlib.sha256).hexdigest())
    except (ValueError,AttributeError): return False

def challenge(verifier):
    return base64.urlsafe_b64encode(hashlib.sha256(verifier.encode('ascii')).digest()).decode().rstrip('=')

def expire():
    for state,item in list(PENDING.items()):
        if item['expires'] < time.time(): PENDING.pop(state,None)

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def response(self,status,body,kind='application/json'):
        data=(json.dumps(body) if kind=='application/json' else body).encode()
        self.send_response(status)
        for key,value in {'Content-Type':kind,'Cache-Control':'no-store','Pragma':'no-cache','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'",'Content-Length':str(len(data))}.items(): self.send_header(key,value)
        self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        parsed=urlparse(self.path);q=parse_qs(parsed.query)
        if parsed.path == '/config':
            return self.response(200,{'client_id':CLIENT,'callback':PUBLIC+'/callback','version':2})
        if parsed.path != '/callback': return self.response(404,{'error':'Not found'})
        if any(len(v)!=1 for v in q.values()): return self.response(400,{'error':'Duplicate callback parameters'})
        state=q.get('state',[''])[0]
        with LOCK:
            expire();item=PENDING.get(state)
            if not item or item.get('completed'): return self.response(400,{'error':'Invalid, reused or expired state'})
            item['completed']=True
            if 'error' in q:
                PENDING.pop(state,None)
                target=APP_RETURN+'?'+urlencode({'state':state,'error':'access_denied'})
            else:
                code=q.get('code',[''])[0];scopes=set(q.get('scope',[''])[0].replace(' ', ',').split(','))- {''}
                if not code or not scopes.issubset(ALLOWED|{'profile:read_all'}):
                    PENDING.pop(state,None);return self.response(400,{'error':'Invalid authorization response'})
                item.update(code=code,scope=','.join(sorted(scopes)),handoff=secrets.token_urlsafe(32))
                target=APP_RETURN+'?'+urlencode({'state':state,'handoff':item['handoff']})
        # User gesture opens the custom scheme reliably in Android browsers.
        # Only the opaque, verifier-bound handoff is exposed, never tokens or code.
        return self.response(200,'<!doctype html><meta name="viewport" content="width=device-width"><title>Bike Computer</title><h1>Terug naar je fietscomputer</h1><p>Strava heeft je keuze verwerkt.</p><p><a href="'+html.escape(target,quote=True)+'">Open Ultimate Bike Computer</a></p><p>Deze overdracht verloopt na tien minuten.</p>','text/html; charset=utf-8')
    def do_POST(self):
        try:
            length=int(self.headers.get('Content-Length','0'))
            if length<=0 or length>8192: return self.response(413,{'error':'Invalid request size'})
            body=json.loads(self.rfile.read(length))
            if not isinstance(body,dict):return self.response(400,{'error':'Invalid request'})
            if self.path == '/start':
                state=body.get('state','');proof=body.get('code_challenge','');scopes=body.get('scopes',[])
                if body.get('client_id')!=CLIENT or not re.fullmatch(r'[A-Za-z0-9_=-]{32,128}',state) or not re.fullmatch(r'[A-Za-z0-9_-]{43}',proof) or not isinstance(scopes,list) or not scopes or not set(scopes).issubset(ALLOWED):
                    return self.response(400,{'error':'Invalid configuration or request'})
                with LOCK:
                    expire()
                    if state in PENDING or len(PENDING)>=100:return self.response(429,{'error':'Try later'})
                    PENDING[state]={'expires':time.time()+600,'challenge':proof}
                auth='https://www.strava.com/oauth/authorize?'+urlencode({'client_id':CLIENT,'response_type':'code','redirect_uri':PUBLIC+'/callback','approval_prompt':'force','scope':','.join(scopes),'state':state})
                return self.response(200,{'authorization_url':auth})
            data={'client_id':CLIENT,'client_secret':SECRET}
            scope=None
            if self.path=='/exchange':
                with LOCK:
                    expire();item=PENDING.get(body.get('state'))
                    verifier=body.get('code_verifier','')
                    if not item or not item.get('code') or not re.fullmatch(r'[A-Za-z0-9_-]{43,128}',verifier) or not secrets.compare_digest(item.get('handoff',''),body.get('handoff','x')) or not secrets.compare_digest(item['challenge'],challenge(verifier)):
                        return self.response(400,{'error':'Invalid state, handoff or verifier'})
                    PENDING.pop(body['state'],None)
                scope=item['scope'];data.update(grant_type='authorization_code',code=item['code'])
            elif self.path=='/refresh' and valid(body.get('session')):
                data.update(grant_type='refresh_token',refresh_token=body['refresh_token'])
            else:return self.response(403,{'error':'Unauthorized'})
            request=Request('https://www.strava.com/oauth/token',data=urlencode(data).encode(),method='POST')
            with urlopen(request,timeout=20) as response:token=json.load(response)
            result={k:token[k] for k in ['access_token','refresh_token','expires_at']}
            if scope is not None:
                athlete=token['athlete'];result['athlete']={k:athlete[k] for k in ['id','firstname','lastname'] if k in athlete};result['scope']=scope
            result['session']=body.get('session') or credential()
            self.response(200,result)
        except HTTPError as e:
            self.response(401 if e.code in (400,401,403) else 503,{'error':'Authorization expired' if e.code in (400,401,403) else 'Strava temporarily unavailable'})
        except (ValueError,KeyError,TypeError,UnicodeError):self.response(400,{'error':'Invalid OAuth request or response'})
        except Exception:self.response(503,{'error':'OAuth service unavailable'})

if __name__=='__main__':
    ThreadingHTTPServer(('127.0.0.1',int(os.environ.get('PORT','8080'))),Handler).serve_forever()
