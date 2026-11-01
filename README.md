# Ultimate Bike Computer 2.1

Android-fietscomputer op de bestaande Flutter-basis, met OLED-interface, vijf blijvende tabs, echte MapLibre-kaarten, offline gebiedsdownloads en lokale trainingsgenerator.

Nieuw: **Meer → Verbonden apps**, privacy-/synchronisatie-instellingen en directe GPX-uitwisseling. De eigenaar kiest gebruik zonder servers. Daarom is Strava client-ID 292844 zichtbaar, maar geen account verbonden: Strava vereist een client secret bij de tokenuitwisseling, dat niet in de app wordt ingebouwd. GPX importeren/exporteren en zelf via Strava uploaden werken zonder accountserver. Zie [CONNECTED_APPS.md](CONNECTED_APPS.md) voor de concrete mogelijkheden, beperkingen en de optionele afzonderlijke OAuth-implementatie.

## Installeren

- `dist/UltimateBikeComputer-debug.apk`: update voor de bestaande debug-installatie op de Huawei P30. De update behoudt lokale gegevens.
- `dist/UltimateBikeComputer-release.apk`: persoonlijk ondertekende release. De handtekening verschilt van debug; deze vervangt de debug-app niet rechtstreeks. De huidige telefoon is met debug bijgewerkt.
- Versie 2.1.0+3. SHA-256 en bestandsgroottes: `dist/checksums.json`.

Open de APK via Android Bestanden en geef die app zo nodig installatierechten. Verwijderen van de fietscomputer verwijdert lokale gegevens; gebruik Gegevensbeheer voor een JSON-back-up. Deze bevat ook profielen en trainingen. Native offline kaarten worden afzonderlijk gedownload.

## Gebruiken

De tabs zijn Home, Kaart, Fiets, Training en Meer. Kies een activiteitprofiel, open Fiets en start de opname. Geef Android locatietoegang en toestemming voor de registratiemelding. Wacht buiten op een actuele GPS-fix. Zonder sensoren blijven hun waarden `—`. Tabwissels houden de opname actief. Stop en bevestig Opslaan voor een lokale rit met geschiedenis en GPX-export.

Kaart gebruikt OpenFreeMap met Midnight, Daylight of Cycle streets: stijlen van dezelfde gegevensprovider. Kaartinstellingen ondersteunt ook een eigen HTTPS MapLibre-stijl. Download een klein gebied met gewenste zoomniveaus en kies Offline gebruiken bij een volledig gebied. Offline kaarten berekenen zelf geen nieuwe route. Adressen zoeken en nieuwe fietsroutes vereisen een eigen openrouteservice-sleutel in Integraties. GPX en opgeslagen routes werken lokaal.

Training maakt zonder API-sleutel een lokaal advies. FTP is optioneel; zonder FTP gebruikt de generator ervaren inspanning (RPE). Bewaar, wijzig, dupliceer en plan trainingen of start de uitvoering. Timer en eventuele actuele sensormetingen leveren een lokaal resultaat. Handmatig voltooien is expliciet een eigen bevestiging zonder verzonnen metingen.

Meer bevat zoeken en toegang tot ritten, statistieken, routes, offline kaarten, sensoren, trainingen, Strava, integraties, profielen, apps en instellingen. Weergave biedt OLED Black, Graphite, Light, systeemthema, accentkleur, contrast, nacht- en minimale fietsweergave.

## Testbewijs en grenzen

Zie [UPGRADE_REPORT.md](UPGRADE_REPORT.md) voor wijzigingen, fysieke tests, downloadbeleid, configuratie en beperkingen. [README_V1.md](README_V1.md) en [OPLEVERING.md](OPLEVERING.md) beschrijven de eerdere versie.

120 Flutter-tests en 12 OAuth-brokertests slagen. De analyse is foutloos. De Huawei P30/Android 10 is fysiek gebruikt voor online kaarten, stijlen, download, offline herstart en training. De ritflow met geïnjecteerde GPS wordt uitsluitend op de aparte Android 15-emulator getest. Een buitenrit, langdurig batterijverbruik, fysieke BLE-sensoren en persoonlijke Strava/ORS-aanroepen zijn hiermee niet bewezen. Een echte Strava-login/synchronisatie is zonder de noodzakelijke veilige tokenuitwisseling niet uitgevoerd.

## Ontwikkelen

Flutter 3.47.2, Dart 3.13.2, JBR 21, SDK 36. Exacte pakketten: pubspec.lock. Native kaartengine: maplibre_gl 0.27.1. GPS/registratie, SQLite, BLE en configureerbare Strava-backend zijn behouden.

```powershell
flutter pub get
flutter analyze
flutter test --reporter expanded
python backend/test_strava_oauth.py
flutter test integration_test/app_flow_test.dart -d emulator-5554 --dds-port 58231
flutter build apk --debug
flutter build apk --release
```

De integratietest verwacht machtigingen en GPS-fixture op de aparte emulator; start daarvoor scripts/emulator_fixture.py. Voer deze test niet uit op een persoonlijk toestel: de Flutter-testtool kan zijn testinstallatie verwijderen. De telefoon is afzonderlijk via gewone APK-updates getest.

Release-signing gebruikt de bestaande persoonlijke android/key.properties en android/keystore/ultimate-bike-release.jks; bewaar deze privé voor latere updates. Strava vereist eigen OAuth-backend/accountautorisatie. Google Maps en externe AI zijn niet geconfigureerd; ingebouwde kaarten en lokale training werken zonder die sleutels.

Op deze computer is build een NTFS-junction naar C:\Users\wanne\.codex\builds\bike-computer-upgrade-20261101 wegens ruimtegebrek op D:. Dit betreft uitsluitend gegenereerde bestanden; een nieuwe checkout kan een gewone buildmap gebruiken.

De nieuwe self-hosted backend en accountintegratie staan beschreven in [docs/SELF_HOSTING.md](docs/SELF_HOSTING.md). Deze instructies vervangen eerdere opmerkingen over uitsluitend lokale accounts of een optionele tokenbroker. Productie gebruikt de VELO-accountbackend; Strava-secrets en tokens blijven op de server.
