import subprocess,time
adb=r'C:\Users\wanne\AppData\Local\Android\sdk\platform-tools\adb.exe'
for i in range(150):
 for permission in ['ACCESS_FINE_LOCATION','ACCESS_COARSE_LOCATION','POST_NOTIFICATIONS']:
  subprocess.run([adb,'-s','emulator-5554','shell','pm','grant','com.example.bike_computer','android.permission.'+permission],capture_output=True)
 subprocess.run([adb,'-s','emulator-5554','emu','geo','fix',str(4.4025+i*.00005),'51.2194','10','8','10'],capture_output=True)
 time.sleep(1)
print('GPS + Android permission fixture complete')
