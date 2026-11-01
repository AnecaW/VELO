"""Configure Strava only from private local files; never print credentials."""
import argparse,json,secrets,urllib.request,urllib.error,urllib.parse
from pathlib import Path
from supabase_admin import Management

def env(path):
 result={}
 for line in Path(path).read_text(encoding='utf-8-sig').splitlines():
  if '=' in line and not line.lstrip().startswith('#'):
   k,v=line.split('=',1);result[k.strip()]=v.strip().strip('\"').strip("'")
 return result

def main():
 parser=argparse.ArgumentParser()
 parser.add_argument('--token-file',required=True)
 parser.add_argument('--credentials-file',required=True)
 parser.add_argument('--server-secrets-file',required=True)
 args=parser.parse_args()
 credentials=env(args.credentials_file)
 for k in ('STRAVA_CLIENT_ID','STRAVA_CLIENT_SECRET'):
  if not credentials.get(k):raise SystemExit('Missing private configuration field: '+k)
 if not credentials['STRAVA_CLIENT_ID'].isdigit():raise SystemExit('STRAVA_CLIENT_ID must contain digits only.')
 backup=Path(args.server_secrets_file);server=env(backup)
 aes=server.get('STRAVA_TOKEN_ENCRYPTION_KEY') or server.get('VELO_TOKEN_ENCRYPTION_KEY')
 if not aes:raise SystemExit('Existing token encryption backup missing; refusing to replace the encryption key.')
 additions={'STRAVA_TOKEN_ENCRYPTION_KEY':aes,'STRAVA_WEBHOOK_VERIFY_TOKEN':server.get('STRAVA_WEBHOOK_VERIFY_TOKEN') or secrets.token_urlsafe(32)}
 with backup.open('a',encoding='utf-8') as file:
  for k,v in additions.items():
   if k not in server:file.write('\n'+k+'='+v+'\n')
 api=Management(args.token_file)
 api.request('/secrets',[{'name':k,'value':v} for k,v in {**credentials,**additions}.items() if k in ('STRAVA_CLIENT_ID','STRAVA_CLIENT_SECRET','STRAVA_TOKEN_ENCRYPTION_KEY','STRAVA_WEBHOOK_VERIFY_TOKEN')])
 print('Strava configuration stored server-side; encryption key preserved.',flush=True)
 for slug in ('velo-api','velo-worker','velo-webhook'):api.deploy(slug)
 target=f'https://{api.project}.supabase.co/functions/v1/velo-webhook'
 def strava(method,fields):
  fields={'client_id':credentials['STRAVA_CLIENT_ID'],'client_secret':credentials['STRAVA_CLIENT_SECRET'],**fields}
  data=urllib.parse.urlencode(fields).encode()
  url='https://www.strava.com/api/v3/push_subscriptions'
  if method=='GET':url+='?'+data.decode();data=None
  request=urllib.request.Request(url,data=data,method=method,headers={'Content-Type':'application/x-www-form-urlencoded'})
  try:
   with urllib.request.urlopen(request,timeout=45) as response:return json.load(response)
  except urllib.error.HTTPError as error:raise SystemExit('Strava webhook setup failed: HTTP '+str(error.code)+' (credentials and provider body withheld).') from None
 subscriptions=strava('GET',{})
 if subscriptions:
  matching=[s for s in subscriptions if s.get('callback_url')==target]
  if not matching:raise SystemExit('This Strava app already has a webhook pointing elsewhere. It has not been replaced.')
  subscription=matching[0]
 else:subscription=strava('POST',{'callback_url':target,'verify_token':additions['STRAVA_WEBHOOK_VERIFY_TOKEN']})
 api.request('/secrets',[{'name':'STRAVA_WEBHOOK_SUBSCRIPTION_ID','value':str(subscription['id'])}])
 api.deploy('velo-webhook')
 print('Webhook subscription active:',subscription['id'],flush=True)
 print('Authorization callback domain:',api.project+'.supabase.co',flush=True)

if __name__=='__main__':main()
