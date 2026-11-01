"""Runs only against the purpose-created emulator. All GPS is labelled test data."""
from android_smoke import *
PACKAGE='com.example.bike_computer'
for permission in ['ACCESS_FINE_LOCATION','ACCESS_COARSE_LOCATION','POST_NOTIFICATIONS']:
 adb('shell','pm','grant',PACKAGE,'android.permission.'+permission)
adb('shell','am','force-stop',PACKAGE)
adb('shell','am','start','-n',PACKAGE+'/.MainActivity');time.sleep(1)
screenshot('home')
tap('START RIDE');tap('START')
for i in range(6):
 adb('emu','geo','fix',str(4.4025+i*.00008),'51.2194','10','8','10');time.sleep(1.3)
screenshot('ride')
assert any((label or '').endswith('punten') and not label.startswith('0 ') for label,_ in labels()), labels()
tap('PAUZE');screenshot('ride-paused');tap('HERVAT')
adb('shell','am','force-stop',PACKAGE)
adb('shell','am','start','-n',PACKAGE+'/.MainActivity');time.sleep(1)
tap('START RIDE')
assert any(label=='Onafgewerkte rit gevonden' for label,_ in labels()),labels()
screenshot('recovery-dialog');tap('Herstellen')
assert any(label=='PAUSED' for label,_ in labels()),labels()
screenshot('recovered-ride');tap('HERVAT');tap('STOP / OPSLAAN');tap('Opslaan');screenshot('ride-summary')
tap('Export GPX',scroll=True)
print(json.dumps(labels(),ensure_ascii=True,indent=2))
