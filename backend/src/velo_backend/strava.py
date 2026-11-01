import email.utils
import json
import time
from datetime import datetime, timezone
import httpx

class ProviderError(Exception):
    def __init__(self, message, retry=300, authentication=False, uncertain=False):
        self.message,self.retry,self.authentication,self.uncertain=message,retry,authentication,uncertain
        super().__init__(message)

class Strava:
    def __init__(self, db, client=None):
        self.db,self.settings=db,db.settings
        self.client=client or httpx.Client(timeout=25, follow_redirects=False)

    def exchange(self, code):
        if not self.settings.strava_ready: raise ProviderError("Strava is niet geconfigureerd op deze server.",3600)
        return self._oauth({"grant_type":"authorization_code","code":code})

    def _oauth(self, fields):
        try:
            response=self.client.post("https://www.strava.com/oauth/token",data={"client_id":self.settings.strava_client_id,"client_secret":self.settings.strava_client_secret,**fields})
        except httpx.HTTPError: raise ProviderError("Strava-tokenservice tijdelijk niet bereikbaar.") from None
        if response.status_code in (400,401,403):raise ProviderError("Strava-toestemming is verlopen of ingetrokken. Verbind opnieuw.",authentication=True)
        if response.status_code!=200:raise ProviderError("Strava-tokenservice heeft het verzoek niet voltooid.")
        try:
            result=response.json()
            if not all(isinstance(result.get(k),str) and result[k] for k in ("access_token","refresh_token")) or not isinstance(result.get("expires_at"),int):raise ValueError()
            return result
        except (ValueError,TypeError):raise ProviderError("Ongeldig antwoord van Strava-tokenservice.") from None

    def connection(self,user):
        with self.db.connect() as con:return con.execute("SELECT * FROM connections WHERE user_id=? AND provider='strava'",(user,)).fetchone()

    def token(self,user,force=False):
        row=self.connection(user)
        if not row or row['status']!='connected':raise ProviderError("Strava niet verbonden.",authentication=True)
        token=self.db.open(row['tokens'])
        if not force and token.get('expires_at',0)>time.time()+60:return token['access_token']
        try: refreshed=self._oauth({'grant_type':'refresh_token','refresh_token':token['refresh_token']})
        except ProviderError as e:
            if e.authentication:self.invalidate(user)
            raise
        with self.db.connect(True) as con:
            con.execute("UPDATE connections SET tokens=? WHERE user_id=? AND provider='strava'",(self.db.seal(refreshed),user))
        return refreshed['access_token']

    def invalidate(self,user):
        with self.db.connect(True) as con:
            con.execute("UPDATE connections SET status='needs_reconnect',tokens=?,error=? WHERE user_id=? AND provider='strava'",(self.db.seal({}),'Strava-toestemming ontbreekt. Verbind opnieuw.',user))
            con.execute("DELETE FROM cache WHERE user_id=? AND provider='strava'",(user,))

    def take_quota(self):
        now=int(time.time())
        with self.db.connect(True) as con:
            con.execute("INSERT OR IGNORE INTO quota(provider) VALUES('strava')")
            row=con.execute("SELECT * FROM quota WHERE provider='strava'").fetchone()
            if row['next_at']>now:raise ProviderError('Strava API-limiet bereikt. Wacht op de volgende toegestane poging.',row['next_at']-now)
            if row['lease_until']>now:raise ProviderError('Een ander Strava-verzoek is bezig.',max(2,row['lease_until']-now))
            con.execute("UPDATE quota SET lease_until=? WHERE provider='strava'",(now+90,))

    def record_quota(self,response):
        now=int(time.time());next_at=now
        for prefix in ('x-ratelimit','x-readratelimit'):
            try:
                limits=[int(x) for x in response.headers[prefix+'-limit'].split(',')]
                usage=[int(x) for x in response.headers[prefix+'-usage'].split(',')]
                if usage[0]>=limits[0]:next_at=max(next_at,(now//900+1)*900)
                if usage[1]>=limits[1]:next_at=max(next_at,(now//86400+1)*86400)
            except (KeyError,ValueError,IndexError):pass
        if response.status_code==429:
            retry=response.headers.get('retry-after','')
            try:next_at=max(next_at,now+max(1,int(retry)))
            except ValueError:
                try:next_at=max(next_at,int(email.utils.parsedate_to_datetime(retry).timestamp()))
                except (TypeError,ValueError,OverflowError):next_at=max(next_at,(now//900+1)*900)
        with self.db.connect(True) as con:con.execute("UPDATE quota SET next_at=MAX(next_at,?) WHERE provider='strava'",(next_at,))
        return max(1,next_at-now)

    def request(self,user,method,path,**kwargs):
        self.take_quota()
        try:
            token=self.token(user)
            try:
                response=self.client.request(method,'https://www.strava.com/api/v3/'+path,headers={'Authorization':'Bearer '+token},**kwargs)
                if response.status_code==401:
                    token=self.token(user,force=True)
                    response=self.client.request(method,'https://www.strava.com/api/v3/'+path,headers={'Authorization':'Bearer '+token},**kwargs)
            except httpx.HTTPError:raise ProviderError('Strava-netwerkverzoek niet voltooid.',uncertain=method=='POST') from None
            retry=self.record_quota(response)
            if response.status_code in (401,403):self.invalidate(user);raise ProviderError('Strava-toegang is ingetrokken of mist rechten.',authentication=True)
            if response.status_code==429:raise ProviderError('Strava API-limiet bereikt.',retry)
            if response.status_code>=500:raise ProviderError('Strava tijdelijk niet bereikbaar.',uncertain=method=='POST')
            if response.status_code not in (200,201,404):raise ProviderError('Strava heeft het verzoek geweigerd (HTTP '+str(response.status_code)+').',retry=3600)
            return response
        finally:
            with self.db.connect(True) as con:con.execute("UPDATE quota SET lease_until=0 WHERE provider='strava'")

    def revoke(self,user):
        row=self.connection(user)
        if not row:return True
        try:
            token=self.token(user)
            result=self.client.post('https://www.strava.com/oauth/deauthorize',headers={'Authorization':'Bearer '+token})
            return result.status_code in (200,401)
        except (ProviderError,httpx.HTTPError):return False

    def cache(self,user,kind,id,payload):
        now=int(time.time())
        with self.db.connect(True) as con:
            # Do not resurrect data after a disconnect concurrent with a network call.
            if not con.execute("SELECT 1 FROM connections WHERE user_id=? AND provider='strava' AND status='connected'",(user,)).fetchone():raise ProviderError('Account ontkoppeld.',authentication=True)
            con.execute("INSERT INTO cache VALUES(?,'strava',?,?,?,?,?) ON CONFLICT(user_id,provider,kind,id) DO UPDATE SET payload=excluded.payload,synced_at=excluded.synced_at,expires_at=excluded.expires_at",(user,kind,str(id),self.db.seal(payload),now,now+86400))

    def sync(self,user):
        row=self.connection(user)
        if not row:raise ProviderError('Strava niet verbonden.',authentication=True)
        preferences=json.loads(row['preferences']);scopes=set(row['scope'].split(','));now=int(time.time())
        if not preferences.get('enabled',True):return False
        if not any(preferences.get(k,False) for k in ('activities','routes')):return False
        if preferences.get('activities'):
            if not scopes & {'activity:read','activity:read_all'}:raise ProviderError('Activiteiten lezen vereist opnieuw toestemming.',authentication=True)
            with self.db.connect() as con:cursor=con.execute("SELECT cursor FROM cursors WHERE user_id=? AND provider='strava' AND kind='activities'",(user,)).fetchone()
            # Bound backfill and keep a cursor overlap. Cache is never an archive.
            after=max(now-7*86400,(cursor['cursor']-300) if cursor and now-cursor['cursor']<20*3600 else 0)
            complete=False
            for page in range(1,5):
                response=self.request(user,'GET','athlete/activities',params={'after':after,'before':now,'page':page,'per_page':50})
                values=response.json()
                if not isinstance(values,list):raise ProviderError('Ongeldige Strava-activiteitenlijst.')
                for item in values:
                    if not isinstance(item.get('id'),int) or not all(isinstance(item.get(k),(int,float)) and not isinstance(item[k],bool) and item[k]>=0 for k in ('distance','moving_time','elapsed_time')):
                        raise ProviderError('Onvolledige Strava-activiteit; synchronisatiecursor niet verplaatst.')
                    try:datetime.fromisoformat(item['start_date'].replace('Z','+00:00'))
                    except (KeyError,ValueError,AttributeError):raise ProviderError('Strava-activiteit mist starttijd.') from None
                    self.cache(user,'activities',item['id'],item)
                if len(values)<50:complete=True;break
            if not complete:raise ProviderError('Backfilllimiet bereikt; cursor blijft behouden.',3600)
            with self.db.connect(True) as con:con.execute("INSERT INTO cursors VALUES(?,'strava','activities',?) ON CONFLICT(user_id,provider,kind) DO UPDATE SET cursor=excluded.cursor",(user,now))
        if preferences.get('routes'):
            if not scopes & {'read','read_all'}:raise ProviderError('Routes lezen vereist aanvullende toestemming.',authentication=True)
            values=self.request(user,'GET',f"athletes/{row['athlete_id']}/routes",params={'per_page':10,'page':1}).json()
            if not isinstance(values,list):raise ProviderError('Ongeldige Strava-routelijst.')
            for item in values[:10]:
                id=str(item.get('id_str',item.get('id','')))
                if not id.isdigit():raise ProviderError('Ongeldige Strava-route-ID.')
                response=self.request(user,'GET',f'routes/{id}/export_gpx')
                if response.status_code==404:
                    with self.db.connect(True) as con:con.execute("DELETE FROM cache WHERE user_id=? AND provider='strava' AND kind='routes' AND id=?",(user,id))
                    continue
                if len(response.content)>10*1024*1024:raise ProviderError('Strava-route overschrijdt 10 MB.')
                self.cache(user,'routes',id,{'id':id,'name':item.get('name','Route zonder naam'),'gpx':response.text})
        with self.db.connect(True) as con:con.execute("UPDATE connections SET last_sync=?,error=NULL,next_sync=? WHERE user_id=? AND provider='strava'",(now,now+self.settings.sync_interval,user))
        return True
