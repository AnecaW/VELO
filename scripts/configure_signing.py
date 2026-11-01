from pathlib import Path
import subprocess,secrets,os
root=Path.cwd();keystore=root/'android'/'keystore'/'ultimate-bike-release.jks'
keystore.parent.mkdir(exist_ok=True)
properties=root/'android'/'key.properties'
if not keystore.exists():
 password=secrets.token_urlsafe(32)
 env=os.environ.copy();env['BIKE_SIGN_PASSWORD']=password
 subprocess.run([r'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe','-genkeypair','-keystore',str(keystore),'-alias','ultimate-bike','-storepass:env','BIKE_SIGN_PASSWORD','-keypass:env','BIKE_SIGN_PASSWORD','-keyalg','RSA','-keysize','3072','-validity','10000','-dname','CN=Ultimate Bike Computer Personal Build'],env=env,check=True,capture_output=True)
 properties.write_text('storeFile=keystore/ultimate-bike-release.jks\nstorePassword='+password+'\nkeyPassword='+password+'\nkeyAlias=ultimate-bike\n',encoding='utf-8')
print('Local release signing configured; private key and passwords were not printed.')
