import importlib.util,io,json,os,threading,unittest
from pathlib import Path
from unittest.mock import patch
from urllib.request import Request,urlopen
from urllib.error import HTTPError
os.environ.update(STRAVA_CLIENT_ID='123',STRAVA_CLIENT_SECRET='test-only',PUBLIC_URL='https://private.example',SESSION_SECRET='test-session-key-with-at-least-32-characters')
spec=importlib.util.spec_from_file_location('broker',Path(__file__).with_name('strava_oauth.py'));broker=importlib.util.module_from_spec(spec);spec.loader.exec_module(broker)
class BrokerTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.server=broker.ThreadingHTTPServer(('127.0.0.1',0),broker.Handler);threading.Thread(target=cls.server.serve_forever,daemon=True).start();cls.base='http://127.0.0.1:'+str(cls.server.server_port)
 @classmethod
 def tearDownClass(cls):cls.server.shutdown();cls.server.server_close()
 def setUp(self):broker.PENDING.clear();self.state='s'*43;self.verifier='v'*64
 def post(self,path,data):return urlopen(Request(self.base+path,data=json.dumps(data).encode(),headers={'Content-Type':'application/json'}),timeout=5)
 def start(self):
  with self.post('/start',{'client_id':'123','state':self.state,'code_challenge':broker.challenge(self.verifier),'scopes':['activity:read']}) as r:return json.load(r)
 def callback(self,tail='code=single-code&scope=activity%3Aread'):
  return urlopen(self.base+'/callback?state='+self.state+'&'+tail).read().decode()
 def grant(self):self.start();return self.callback()
 def exchange(self,**values):return self.post('/exchange',{'state':self.state,'handoff':broker.PENDING[self.state]['handoff'],'code_verifier':self.verifier,**values})
 def test_official_authorization_and_no_secret(self):
  result=self.start();self.assertTrue(result['authorization_url'].startswith('https://www.strava.com/oauth/authorize?'));self.assertNotIn('client_secret',str(result));self.assertNotIn(self.verifier,str(result))
 def test_unknown_callback_state_rejected(self):
  with self.assertRaises(HTTPError):self.callback()
 def test_callback_contains_only_opaque_handoff(self):
  page=self.grant();self.assertIn('ultimatebike://oauth/strava',page);self.assertNotIn('single-code',page);self.assertNotIn('access_token',page)
 def test_denial_returns_to_app_and_erases_state(self):
  self.start();page=self.callback('error=access_denied');self.assertIn('access_denied',page);self.assertNotIn(self.state,broker.PENDING)
 def test_duplicate_state_rejected(self):
  self.start()
  with self.assertRaises(HTTPError):self.callback('state=forged&code=c&scope=activity%3Aread')
 def test_exchange_requires_verifier(self):
  self.grant()
  with self.assertRaises(HTTPError):self.exchange(code_verifier='wrong'*16)
  self.assertIn(self.state,broker.PENDING)
 def test_expired_handoff_rejected(self):
  self.grant();broker.PENDING[self.state]['expires']=0
  with self.assertRaises(HTTPError):self.exchange()
 def test_success_is_single_use_with_exact_granted_scopes(self):
  self.grant()
  token={'access_token':'test-access','refresh_token':'test-refresh','expires_at':2000000000,'athlete':{'id':7,'firstname':'Test','private_unused':'omit'}}
  with patch.object(broker,'urlopen',return_value=io.StringIO(json.dumps(token))):
   with self.exchange() as r:result=json.load(r)
  self.assertEqual(result['scope'],'activity:read');self.assertEqual(result['athlete'],{'id':7,'firstname':'Test'});self.assertTrue(broker.valid(result['session']));self.assertNotIn('client_secret',result);self.assertNotIn(self.state,broker.PENDING)
 def test_forged_refresh_session_rejected(self):
  with self.assertRaises(HTTPError) as c:self.post('/refresh',{'refresh_token':'r','session':'forged'})
  self.assertEqual(c.exception.code,403)
 def test_refresh_rotates_token_without_new_athlete_data(self):
  with patch.object(broker,'urlopen',return_value=io.StringIO(json.dumps({'access_token':'new','refresh_token':'rotated','expires_at':2000000000}))):
   with self.post('/refresh',{'refresh_token':'r','session':broker.credential()}) as r:result=json.load(r)
  self.assertEqual(result['refresh_token'],'rotated')
 def test_oversized_request_rejected(self):
  with self.assertRaises(HTTPError) as c:self.post('/start',{'x':'a'*9000})
  self.assertEqual(c.exception.code,413)
 def test_expired_session_rejected(self):
  with patch.object(broker.time,'time',return_value=1):session=broker.credential()
  self.assertFalse(broker.valid(session))
if __name__=='__main__':unittest.main(verbosity=2)
