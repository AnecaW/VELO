"""Authenticated navigation proxy. Provider credentials never reach mobile clients."""
import time
import httpx
from fastapi import Depends, Query
from pydantic import BaseModel, ConfigDict, Field, field_validator

class Directions(BaseModel):
    model_config = ConfigDict(extra='forbid')
    coordinates: list[tuple[float,float]] = Field(min_length=2,max_length=2)
    profile: str = 'cycling-regular'
    @field_validator('coordinates')
    @classmethod
    def valid_coordinates(cls,value):
        if any(not (-180 <= lon <= 180 and -90 <= lat <= 90) for lon,lat in value):
            raise ValueError('Invalid coordinates')
        return value
    @field_validator('profile')
    @classmethod
    def valid_profile(cls,value):
        if value not in ('cycling-regular','cycling-road','cycling-mountain','cycling-electric'):
            raise ValueError('Unsupported profile')
        return value

def install_navigation(app,db,user,Problem):
    def request(current,method,path,**kwargs):
        if not db.settings.ors_api_key:
            raise Problem(503,'Routeplanning is momenteel niet beschikbaar. Je opgeslagen routes blijven werken.','navigation_unavailable')
        now=int(time.time());key='navigation:'+current['id']
        with db.connect(True) as con:
            row=con.execute('SELECT * FROM attempts WHERE key=?',(key,)).fetchone()
            count=row['count']+1 if row and row['until_at']>now else 1
            until=row['until_at'] if row and row['until_at']>now else now+3600
            con.execute('INSERT OR REPLACE INTO attempts VALUES(?,?,?)',(key,count,until))
        if count>60:raise Problem(429,'Je hebt veel routes gezocht. Probeer het later opnieuw.','rate_limit')
        try:
            with httpx.Client(timeout=25,follow_redirects=False) as client:
                response=client.request(method,'https://api.openrouteservice.org'+path,headers={'Authorization':db.settings.ors_api_key},**kwargs)
            if response.status_code==429:raise Problem(429,'Routeplanning is druk. Probeer het later opnieuw.','rate_limit')
            if response.status_code!=200:raise Problem(503,'Routeplanning is tijdelijk niet beschikbaar. Probeer later opnieuw.','navigation_unavailable')
            return response.json()
        except (httpx.HTTPError,ValueError):
            raise Problem(503,'Routeplanning is tijdelijk niet bereikbaar.','navigation_unavailable') from None

    @app.get('/api/v1/navigation/search')
    def search(q:str=Query(min_length=3,max_length=200),current=Depends(user)):
        return request(current,'GET','/geocode/search',params={'text':q,'size':5})

    @app.post('/api/v1/navigation/directions')
    def directions(body:Directions,current=Depends(user)):
        return request(current,'POST',f'/v2/directions/{body.profile}/geojson',json={'coordinates':body.coordinates,'elevation':True,'instructions':True})
