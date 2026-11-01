import subprocess,time
adb=r'C:\Users\wanne\AppData\Local\Android\sdk\platform-tools\adb.exe'
for i in range(60):
 subprocess.run([adb,'-s','emulator-5554','emu','geo','fix',str(4.4025+i*.00005),'51.2194','10','8','10'],capture_output=True,check=True)
 time.sleep(2)
print('GPS fixture delivered')
