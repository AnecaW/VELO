import json
import time
import uuid
from xml.etree.ElementTree import Element,SubElement,tostring
from .strava import ProviderError

def enqueue(db,user,kind='sync',key='inbound'):
    now=int(time.time())
    with db.connect(True) as con:
        old=con.execute("SELECT * FROM jobs WHERE user_id=? AND provider='strava' AND kind=? AND job_key=?",(user,kind,key)).fetchone()
        if old:
            if kind=='sync' and old['status'] not in ('pending','running'):
                con.execute("UPDATE jobs SET status='pending',next_at=MAX(next_at,?),error=NULL,updated_at=? WHERE id=?",(now,now,old['id']))
            return old['id']
        id=uuid.uuid4().hex
        con.execute("INSERT INTO jobs(id,user_id,provider,kind,job_key,status,next_at,created_at,updated_at) VALUES(?,?,'strava',?,?,'pending',?,?,?)",(id,user,kind,key,now,now,now))
        return id

def gpx(payload):
    points=payload.get('points',[])
    if len(points)<2:raise ProviderError('Een GPX-upload vereist een eigen GPS-spoor met minstens twee punten.',retry=0)
    root=Element('gpx',version='1.1',creator='VELO',xmlns='http://www.topografix.com/GPX/1/1');segment=SubElement(SubElement(root,'trk'),'trkseg')
    for p in points:
        point=SubElement(segment,'trkpt',lat=str(p[0]),lon=str(p[1]));SubElement(point,'ele').text=str(p[2]);SubElement(point,'time').text=p[3]
    return tostring(root,encoding='utf-8',xml_declaration=True)

class Worker:
    def __init__(self,db,strava):self.db,self.strava=db,strava
    def tick(self):
        self.db.cleanup();now=int(time.time())
        with self.db.connect(True) as con:
            # Polls and reads can be repeated, but an interrupted upload POST cannot.
            con.execute("UPDATE jobs SET status=CASE WHEN kind='upload' THEN 'needs_review' ELSE 'pending' END,error='Vorige uitvoering onderbroken',lease_until=0 WHERE status='running' AND lease_until<?",(now,))
            accounts=con.execute("SELECT user_id,preferences FROM connections WHERE provider='strava' AND status='connected' AND next_sync<=?",(now,)).fetchall()
        for account in accounts:
            prefs=json.loads(account['preferences'])
            if prefs.get('enabled',True) and prefs.get('automatic'):enqueue(self.db,account['user_id'])
        with self.db.connect(True) as con:
            job=con.execute("SELECT * FROM jobs WHERE status='pending' AND next_at<=? ORDER BY created_at LIMIT 1",(now,)).fetchone()
            if not job:return False
            con.execute("UPDATE jobs SET status='running',lease_until=?,updated_at=? WHERE id=?",(now+600,now,job['id']))
        try:
            if job['kind']=='sync':
                did_work=self.strava.sync(job['user_id'])
                self.finish(job,'complete' if did_work else 'skipped',None,'Synchronisatie geslaagd' if did_work else 'Synchronisatie uitgeschakeld of geen inkomende categorie geselecteerd')
            else:self.upload(job)
        except ProviderError as e:
            status='needs_review' if e.uncertain else 'failed' if e.authentication or e.retry==0 else 'pending'
            attempts=job['attempts']+1;delay=max(e.retry,min(21600,30*(2**min(attempts,9))))
            with self.db.connect(True) as con:
                con.execute("UPDATE jobs SET status=?,attempts=?,next_at=?,lease_until=0,error=?,updated_at=? WHERE id=?",(status,attempts,int(time.time())+delay,e.message,int(time.time()),job['id']))
                con.execute("UPDATE connections SET error=? WHERE user_id=? AND provider='strava'",(e.message,job['user_id']))
            self.db.history(job['user_id'],'strava','error',e.message)
        except Exception:
            # No request bodies, tokens, exception values or GPS data in logs/history.
            with self.db.connect(True) as con:con.execute("UPDATE jobs SET status=?,next_at=?,lease_until=0,error=?,updated_at=? WHERE id=?",('needs_review' if job['kind']=='upload' else 'pending',now+300,'Taak niet voltooid; controleer serverstatus.',now,job['id']))
        return True

    def finish(self,job,status,result,message):
        with self.db.connect(True) as con:con.execute("UPDATE jobs SET status=?,result=?,error=NULL,lease_until=0,updated_at=? WHERE id=?",(status,self.db.seal(result) if result else None,int(time.time()),job['id']))
        self.db.history(job['user_id'],'strava',status,message)

    def upload(self,job):
        account=self.strava.connection(job['user_id'])
        if not account:raise ProviderError('Strava-account ontkoppeld.',authentication=True)
        prefs=json.loads(account['preferences'])
        if not prefs.get('enabled',True) or not prefs.get('uploads',False):raise ProviderError('Uploads zijn uitgeschakeld.',retry=0)
        if 'activity:write' not in account['scope'].split(','):raise ProviderError('Strava-uploadrechten ontbreken.',authentication=True)
        result=self.db.open(job['result']) if job['result'] else {}
        if result.get('upload_id'):
            response=self.strava.request(job['user_id'],'GET',f"uploads/{result['upload_id']}")
        else:
            with self.db.connect() as con:row=con.execute("SELECT payload FROM documents WHERE user_id=? AND kind='rides' AND id=?",(job['user_id'],job['job_key'])).fetchone()
            if not row:raise ProviderError('Eigen rit niet gevonden.',retry=0)
            track=gpx(self.db.open(row['payload']))
            response=self.strava.request(job['user_id'],'POST','uploads',data={'data_type':'gpx','sport_type':'Ride','external_id':job['user_id']+'-'+job['job_key']+'.gpx'},files={'file':('ride.gpx',track,'application/gpx+xml')})
        result=response.json()
        if result.get('error'):raise ProviderError('Strava weigert deze upload; controleer op dubbele activiteit.',retry=0)
        if result.get('activity_id'):
            self.finish(job,'complete',{'activity_id':result['activity_id']},'Eigen rit door Strava verwerkt')
        elif result.get('id'):
            with self.db.connect(True) as con:con.execute("UPDATE jobs SET status='pending',result=?,next_at=?,lease_until=0,updated_at=? WHERE id=?",(self.db.seal({'upload_id':result['id']}),int(time.time())+20,int(time.time()),job['id']))
        else:raise ProviderError('Uploadantwoord is onduidelijk. Controleer Strava.',uncertain=True)
