"""UI smoke helpers for the dedicated test emulator, never a physical device."""
import subprocess,xml.etree.ElementTree as E,re,time,json
from pathlib import Path
ADB=r'C:\Users\wanne\AppData\Local\Android\sdk\platform-tools\adb.exe'
OUT=Path('artifacts/screenshots');OUT.mkdir(parents=True,exist_ok=True)
def adb(*args):return subprocess.check_output([ADB,'-s','emulator-5554',*args],timeout=25)
def nodes():
 adb('shell','uiautomator','dump','/sdcard/bike-ui.xml')
 return list(E.fromstring(adb('exec-out','cat','/sdcard/bike-ui.xml')).iter('node'))
def labels():return [(n.get('text') or n.get('content-desc'),n.get('bounds')) for n in nodes() if n.get('text') or n.get('content-desc')]
def tap(label,contains=False,scroll=False):
 for attempt in range(8 if scroll else 1):
  for n in nodes():
   values=[n.get('text',''),n.get('content-desc','')]
   if any((label in v if contains else label==v) for v in values):
    x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')))
    adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));time.sleep(.5);return
  if scroll:adb('shell','input','swipe','160','490','160','180','300');time.sleep(.3)
 raise AssertionError('Missing '+label+': '+str(labels()))
def screenshot(name):
 (OUT/(name+'.png')).write_bytes(adb('exec-out','screencap','-p'))
def back():adb('shell','input','keyevent','4');time.sleep(.4)
if __name__=='__main__':print(json.dumps(labels(),ensure_ascii=True,indent=2))
