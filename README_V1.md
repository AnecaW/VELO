# Ultimate Bike Computer

Een installeerbare Android-fietscomputer op de bestaande Flutter-basis. **Dit is een werkende eerste productversie, geen volledige Garmin Edge 1050-vervanger.** Zie [OPLEVERING.md](OPLEVERING.md) voor testbewijs en ontbrekende functies.

## Installeren zonder ontwikkelaarstools

1. Kopieer `dist/UltimateBikeComputer-release.apk` naar je Android-telefoon.
2. Open het APK-bestand in Bestanden en sta voor die bestandsapp tijdelijk 'Onbekende apps installeren' toe.
3. Installeer en open **Ultimate Bike Computer**. Android 7.0/API 24 of hoger is de ondergrens van de gebruikte Flutter-build; Android 15/API 35 is getest met een emulator.
4. Kies op Home een activiteitprofiel. Open Settings voor eenheden, GPS, automatische pauze, helderheid en scherm-aan.
5. Tik START RIDE en daarna START. Geef locatietoegang tijdens gebruik en toestemming voor de zichtbare registratiemelding. Sta bij voorkeur nauwkeurige locatie toe.
6. Wacht buiten op GPS. Niet-beschikbare sensormetingen verschijnen als `—`. Gebruik PAUZE/HERVAT en STOP / OPSLAAN om lokaal te bewaren.
7. Open RITTEN voor geschiedenis, kaart en GPX-export. Exporteer naar een zelfgekozen locatie met de Android-bestandskiezer.

De release is ondertekend met een voor dit project gegenereerde persoonlijke sleutel. Debug en release hebben verschillende handtekeningen. Een eerdere debug-installatie kan daarom niet rechtstreeks door deze release worden bijgewerkt; maak eerst een back-up en verwijder daarna de debugversie. Verwijderen van de app verwijdert lokale gegevens.

## Eerste fietsrit

- Controleer GPS buiten en maak eerst een korte proefrit.
- Settings > GPS & Recording: 1–10 seconden GPS-interval, hoge/besparende nauwkeurigheid, maximaal toegestane horizontale GPS-fout; deze keuzes gelden vanaf de volgende rit.
- Automatische pauze: na vijf seconden onder 3 km/h; hervatten boven 4 km/h. Een handmatige pauze hervat alleen handmatig.
- Via het rastericoon op het fietsscherm: velden toevoegen, verwijderen en verslepen. De volgorde wordt per geselecteerd profiel bewaard. Swipe tussen de gegevenspagina's; liggend toont elke pagina minder velden zodat cijfers groot blijven.
- Het sloticoon blokkeert de ritbediening. Ontgrendelen blijft bereikbaar bovenaan.
- Bewaar voor vertrek een GPX-route en eventueel een toegestane raster-MBTiles-kaart. Controleer zelf de geografische dekking en zoomniveaus van het bestand.
- GPS-hoogte en hellingsgraad zijn schattingen; er is geen barometrische of terreinmodelcorrectie.
- Android kan achtergrondwerk bij batterijbesparing beperken. De app gebruikt een locatie-foreground-service en een wakelock. De betrouwbaarheid over een volledige buitenrit moet op jouw toestel nog worden bevestigd.

## Kaarten, routes en offline gebruik

Navigation > bestandsicoon importeert GPX-tracks, routes en waypointcoördinaten (maximaal 10 MB/100.000 punten). Import gebeurt via de systeembestandskiezer; XML wordt op een aparte isolate geparseerd. Via de mapknop open je lokaal opgeslagen routes en bestemmingsfavorieten. Lang drukken op de kaart vult een bestemming in.

**Zonder internet:** ritregistratie, geschiedenis, instellingen, GPX-spoorbegeleiding en geïmporteerde raster-MBTiles blijven beschikbaar. Een routespoor wordt ook zonder achtergrondkaart getoond, met een expliciet label. Een GPX zonder afslagdata krijgt geen verzonnen gesproken afslagaanwijzingen. De route bevat wel voortgang, resterende afstand en detectie van routeafwijkingen.

**Nieuwe fietsroute/adres zoeken:** maak een eigen sleutel bij [openrouteservice](https://openrouteservice.org/log-in/) en voer die in onder Settings > Integrations. Ondersteund: gewone fiets, racefiets, MTB en e-bike. Adreszoeken, routes en herberekening gebruiken HTTPS naar openrouteservice en vereisen netwerk en een geldige sleutel. Routegeometrie en instructies worden lokaal bewaard. Check [actuele beperkingen](https://openrouteservice.org/restrictions/) en je eigen quotum. Er zijn geen gedeelde sleutels ingebouwd. Live providerroutering is zonder sleutel niet gevalideerd.

Online OpenStreetMap is opt-in onder Navigation Settings. Dit verzendt de bekeken kaartgebieden naar de tileprovider. Er is identificatie/attributie en geen bulkdownload. [De OSM-tilevoorwaarden](https://operations.osmfoundation.org/policies/tiles/) verbieden het vooraf downloaden van gebieden van hun openbare tileserver. Voor offline gebruik importeert de app alleen zelf aangeleverde raster-MBTiles waarvoor je gebruiksrechten hebt. Vector-MBTiles worden geweigerd. Kaarten worden niet in JSON-back-ups opgenomen.

**Niet beschikbaar:** nieuwe offline wegenroutering, offline adreszoeken, routealternatieven, rondritten, tussenpunten plannen en verfijnde wegvermijding. Opgeslagen GPX-spoorbegeleiding is dus niet hetzelfde als een volledige offline routeringsengine.

## Sensoren

Settings > Sensors > Scan sensoren. Maak de sensor wakker en geef Android Bluetooth-toestemmingen. Ondersteund in de implementatie:

| BLE-profiel | Metingen |
|---|---|
| Heart Rate / 0x180D, 0x2A37 | 8/16-bit hartslag |
| Cycling Speed and Cadence / 0x1816, 0x2A5B | Crankcadans, inclusief 16-bit rollover |
| Cycling Power / 0x1818, 0x2A63 | Momentaan fietsvermogen |

De sensorpagina ontdekt en verbindt echte apparaten; er is geen standaard simulatie. Onvolledige pakketten stoppen de rit niet. Verouderde meetwaarden worden na tien seconden gewist. Hardwareverbindingen zijn nog niet op fysieke sensoren getest. Wielsnelheid/omtrekconfiguratie, batterij-uitlezing, automatische herverbinding en kalibratie zijn nog niet geïmplementeerd. ANT+ wordt expliciet als niet geïmplementeerd aangegeven.

## Training, hoogte en statistieken

Training bevat drie trainingen met werkende intervaltimer, pauzeren en overslaan. Stel FTP in onder Settings > Training. De vermogenszones gebruiken expliciete percentages van FTP. De timer bestuurt geen trainer en registreert zelfstandig geen GPS-rit. Energieverbruik is een ruwe schatting, geen meting.

KLIMMEN toont het hoogteprofiel uit de geselecteerde route wanneer alle punten hoogte bevatten. Het kan je positie op die route volgen. Dit is nog geen automatische herkenning van afzonderlijke beklimmingen. STATISTIEKEN berekent periodes, afstand, rijtijd, hoogtewinst en lokale uitersten uit bewaarde ritten. Strava-segmenten zijn niet beschikbaar.

## Strava-authenticatie en synchronisatie

Strava is opt-in. Alleen expliciet geselecteerde ritten worden in een lokale uploadwachtrij gezet. Offline blijven die taken lokaal bewaard. Start synchronisatie handmatig; er is geen periodieke achtergrondworker.

1. Registreer een eigen Strava API-app en stel de callbackdomain van je eigen HTTPS-host in.
2. Host `backend/strava_oauth.py` privé achter een HTTPS reverse proxy. De Python HTTP-server luistert uitsluitend op `127.0.0.1:8080`.
3. Configureer op die server `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET`, `PUBLIC_URL` (bijvoorbeeld `https://bike.example`), en een willekeurige `SESSION_SECRET` van minstens 32 tekens. Gebruik omgevingsvariabelen; zet secrets niet in broncode. Python 3.10+; geen externe Python-packages nodig.
4. Start `python backend/strava_oauth.py`. Zet redactie/uitschakeling van URL-querylogging ook op je reverse proxy aan: OAuth-callbacks bevatten een eenmalige code. Gebruik toegangsbeperking en rate limiting passend bij je private server. Dit is geen geharde publieke multi-tenantdienst.
5. Settings > Integrations > Strava: vul je HTTPS-backend en client ID in. Kies Verbinden via OAuth en geef in Strava toestemming voor `activity:write`.
6. De callbackpagina toont een eenmalige code. Plak die in de app en rond authenticatie af. De state wordt gecontroleerd; de server wisselt de code met het officiële tokenendpoint uit.
7. Tokens en de backend-sessie staan in Android beveiligde opslag; de Strava-clientsecret blijft op je server. Tokens worden vernieuwd wanneer ze verlopen. Kies per rit Delen en daarna Wachtrij synchroniseren.

De app bewaart upload-ID en activiteit-ID. HTTP 429 en veilige retrygevallen krijgen uitstel; een upload met onzekere uitkomst wordt **niet blind opnieuw verstuurd**. Controleer bij status `unknown` eerst je Strava-account. Er is nog geen UI om die onzekere taken na handmatige controle opnieuw vrij te geven. Verbreken verwijdert lokale tokens; trek toegang ook in bij Strava als je de machtiging volledig wilt intrekken.

[Officiële OAuth-documentatie](https://developers.strava.com/docs/authentication/) en [uploaddocumentatie](https://developers.strava.com/docs/uploads/). Backend, verversen, wachtrij en fouten zijn met testdiensten getest. Een echte Strava-login/upload is zonder jouw appregistratie niet getest.

## Launcher en apps

Home > APPS of Settings > Apps & Launcher toont Android-apps met een startbare launcheractiviteit. Zoeken, favorieten en filteren op favorieten worden ondersteund. Tik op een app om deze te openen.

Kies 'Standaardlauncher instellen' om de officiële Android-keuze te openen; de app wijzigt de launcher niet stilzwijgend. Terugzetten: Android Instellingen > Apps > Standaardapps > Startscherm. 'Direct fietsscherm bij opstarten' staat onder Display en geldt bij een nieuwe appstart.

Scherm vastzetten gebruikt het Android-mechanisme met de systeembevestiging. Er is een zichtbare knop om het vastzetten te verlaten; Android heeft daarnaast zijn eigen ontgrendelgebaar/toetsen. Dit is geen beheerde kiosk. Een echte device-owner-configuratie is niet geleverd.

## Gegevens, privacy en herstel

Ritten staan in een vaste appmap in SQLite/Drift, met een additieve migratie van databaseversie 1 naar 2. Alle GPS-punten en tijden worden bewaard. Opslaan van metadata en volledig ritpayload gebeurt binnen een transactie. Dezelfde rit-ID wordt niet dubbel opgeslagen.

Een actieve rit krijgt ongeveer elke vijf seconden een checkpoint. Na procesbeëindiging vraagt het fietsscherm om herstel. De rit hervat gepauzeerd; tijd waarin het proces niet draaide wordt niet als fietsen gerekend. Hoogstens de nog niet vastgelegde laatste seconden kunnen ontbreken. Een GPS-uitval of pauze wordt niet als rechtstreekse ritafstand overbrugd. GPX-export bevat segmentgrenzen na pauzes.

Settings > Back-up & herstellen exporteert/importert JSON met ritten, routes en instellingen. Tokens/API-sleutels en offline kaartbestanden worden niet geëxporteerd. Bestaande ritten blijven bij import behouden. Android automatische cloudback-up is uitgeschakeld. De app synchroniseert niets zonder expliciete actie. Diagnostiekexport bevat geen tokens of GPS-spoor.

De database van de oorspronkelijke app stond in telkens nieuwe tijdelijke mappen. Die oude, tijdelijke bestanden worden niet automatisch samengevoegd; bestanden zijn niet verwijderd.

## Machtigingen

| Machtiging | Doel |
|---|---|
| Nauwkeurige/benaderde locatie | GPS-registratie en navigatie |
| Foreground service + location | Zichtbare langdurige ritregistratie |
| Meldingen | Registratiemelding op recente Android-versies |
| Wake lock | Actieve locatieverwerking tijdens schermuitval |
| Bluetooth scan/connect (oude Bluetooth-machtigingen t/m API 30) | Echte BLE-sensoren |
| Internet/netwerkstatus | Alleen optionele kaart-, route- en Stravafuncties |

Er wordt geen onbeperkte toegang tot alle bestanden, alle geïnstalleerde packages of permanente achtergrondlocatie gevraagd. Bestandsimport/export gebruikt de Android-documentkiezer.

## Architectuur en bouwen

- `lib/features`: home, rit, navigatie, geschiedenis, training, instellingen, analyse.
- `lib/services/ride`: vervangbare GPS/tijd, registratie, export en volledige sessiecodering.
- `lib/database`: Drift/SQLite, migraties, transacties en versioned JSON-documenten voor flexibele configuratie.
- `lib/services/navigation`: GPX, routeprojectie, echte HTTPS-routering/geocoding.
- `lib/services/bluetooth`: echte BLE-laag en afzonderlijke packetdecoders.
- `lib/services/integrations`: beveiligde tokenopslag en idempotente uploadwachtrij.
- `android/.../MainActivity.kt`: officiële launcherrol, appmenu, scherminstellingen, meldingsmachtiging, TTS en toesteldiagnostiek.
- `test`, `integration_test`, `backend/test_strava_oauth.py`: automatische tests.

Gebruikte basis: Flutter 3.47.2, Dart 3.13.2, Java/JBR 21, AGP 9.1, Kotlin 2.4 en SDK 36. Dependencies staan exact in `pubspec.lock`. De bestaande Flutter-app is behouden; geen onnodige Compose-herschrijving.

```powershell
flutter pub get
flutter analyze
flutter test --reporter expanded --timeout 30s
python backend/test_strava_oauth.py
flutter test integration_test/app_flow_test.dart -d emulator-5554
flutter build apk --debug
flutter build apk --release
```

De Android UI-test verwacht locatie-/meldingsmachtigingen en een GPS-fixture op de afzonderlijke testemulator. `scripts/emulator_fixture.py` levert die; test nooit automatisch op een persoonlijk toestel. `scripts/android_smoke.py` bevat helpers voor native documentkiezer- en schermcontroles.

Release-signing gebruikt `android/key.properties` en `android/keystore/ultimate-bike-release.jks` (beide uitgesloten van versiebeheer). Bewaar deze twee bestanden privé als je later onder dezelfde handtekening wilt updaten. Op een andere ontwikkelmachine stel je eigen paden/Android SDK in; de APK zelf heeft die ontwikkelbestanden niet nodig. `scripts/configure_signing.py` kan bij een nieuwe checkout een eigen persoonlijke sleutel maken. Distributie naar een appstore en beheerde toestelprovisioning zijn niet uitgevoerd.
