# Opleverrapport — Ultimate Bike Computer

Datum: 31 oktober 2026. Project: `D:\wanne\Desktop\IOS Bike Computer\bike_computer`.

## Status en reikwijdte

Er is een echte Android-app gebouwd op de aanwezige Flutter-app. De standaardrit gebruikt nu echte GPS, de sensorpagina gebruikt echte BLE, volledige GPS-ritten worden duurzaam opgeslagen en er zijn installeerbare debug- en persoonlijk ondertekende release-APK's. Dit is **niet de volledige uitvoering van alle circa dertig pagina's gevraagde functies**. De beperkingen hieronder zijn onderdeel van de oplevering; ontbrekende functies zijn niet als werkend gemarkeerd.

De bestaande Flutter-, Drift- en Bloc-basis, profielen, trainingcatalogus en bruikbare tests zijn behouden. Er is geen zinloze platformherschrijving gedaan.

## Geïmplementeerd en lokaal getest

| Onderdeel | Resultaat |
|---|---|
| GPS-ritregistratie | Echte Android-locatiebron, foreground-melding, start/pauze/hervat/stop/opslaan |
| Kwaliteitscontrole | Finite/range-checks, nauwkeurigheidsfilter, tijdsvolgorde, maximale snelheid, GPS-sprongen en uitval |
| Berekeningen | Afstand, huidige/gemiddelde/maximale snelheid, bewegings- en totale tijd; gefilterde GPS-hoogte |
| Opslag | Vaste appmap, SQLite/Drift v2, v1-migratie, volledige tracks en tijden, transactioneel opslaan, unieke rit-ID |
| Crashherstel | Periodieke checkpoints en herstel als gepauzeerde rit; test bij echte procesbeëindiging staat onder runtimecontrole |
| Gegevensvelden | Toevoegen/verwijderen/herordenen, automatische swipepagina's, configuratie per profiel |
| Ritbediening | Aanraakslot, aparte stopbevestiging, opslagfouten zichtbaar en retry mogelijk |
| Geschiedenis | Duurzame ritten, totaalcijfers, rit openen, kaart bekijken, bevestigde verwijdering |
| GPX | Begrensde/veilige import, tracks/routes/waypoints, export met XML-escaping en segmentgrenzen |
| Navigatie | Routekaart, positievolgen, zoomen/pannen, oriëntatie, schaal, routeprojectie en afwijkingsdetectie |
| Offline | Lokale GPX-sporen, routearchief en raster-MBTiles-import; geen verborgen serverafhankelijkheid voor spoorbegeleiding |
| Training | Intervaltimer, pauzeren/overslaan, FTP-doelen en zones; live vermogen wanneer aanwezig |
| Hoogteprofiel | Routeprofiel uit aanwezige hoogtegegevens, gefilterde stijging en locatieprojectie |
| Statistieken | Werkelijke opgeslagen ritten, 7/30 dagen of alles, totalen en lokale uitersten |
| Instellingen | Duurzame opslag, eenheden, thema, scherm/GPS, autopauze, FTP en herinneringsintervallen |
| Gegevensbeheer | JSON-back-up/herstel zonder tokens/kaartbestanden, behoud bestaande ritten/checkpoint |
| Launcher/apps | Officiële HOME-intent/rol, apps ontdekken/openen, zoeken/favorieten, Android-scherm vastzetten/verlaten |
| Diagnostiek | Android/GPS/machtigingen/database/sensoren/batterij/netwerk/opslag/laatste fout; rapportexport |
| Testmodus | Expliciete debug-simulatie, niet standaard actief, geen vermenging met echte geschiedenis |

Gemiddelde snelheid is ritafstand gedeeld door tijd boven de bewegingsdrempel met actuele GPS. Bewegingsduur is niet hetzelfde als totale verstreken tijd. Gepauzeerde tijd wordt afzonderlijk bewaard. GPS-hoogte en hellingsgraad blijven schattingen.

## Configuratieafhankelijk — geen live end-to-endclaim

- **openrouteservice:** HTTPS-client voor fietsroutering, adreszoeken, instructies en herberekening. Eigen sleutel vereist. Request/response en fouten getest met vervangbare HTTP-client. Geen live API-account beschikbaar tijdens deze uitvoering.
- **Strava:** OAuth-state, eenmalige code-uitwisseling via meegeleverde private backend, veilige tokenopslag, tokenrotatie, expliciete uploadselectie, GPX-upload, upload-ID/polling, rate-limituitstel en bescherming tegen dubbele/onzekere uploads. Vereist eigen Strava-app, HTTPS-backend en accounttoestemming. Geen echte Strava-login of upload uitgevoerd.
- **Online kaarten:** OpenStreetMap is opt-in. Offlinebestanden moeten door de gebruiker met geldige gebruiksrechten worden aangeleverd. De meegeleverde MBTiles-testfixture bevat nadrukkelijk geen echte cartografie.
- **Gesproken aanwijzingen:** Via Android TTS; stem en aanwezigheid van de spraakengine zijn toestelafhankelijk. Geen test op fietsaudiohardware.

Zie README voor alle configuratiestappen en officiële dienstvoorwaarden.

## Hardwareafhankelijk

- BLE-HR, crankcadans en fietsvermogen zijn daadwerkelijk geïmplementeerd; packetdecoders en sensorverlies zijn automatisch getest.
- Er was geen fysiek Android-toestel en geen fysieke Bluetooth-sensor aangesloten. Detectie/verbinding/herverbinding tijdens een echte buitenrit zijn dus niet gevalideerd.
- GPS/achtergrondregistratie zijn op een Android 15/API 35 AOSP-emulator getest met geïnjecteerde locaties. Dit bewijst geen batterijduur of ontvangstkwaliteit tijdens een lange buitenrit.
- Volledige kiosk/device-owner-provisioning is niet uitgevoerd. De launcher en normaal Android-scherm vastzetten zijn verschillende functies.

## Automatische tests

| Testreeks | Resultaat | Bewijs |
|---|---|---|
| Flutter unit-, opslag-, integratie- en widgettests | 73 geslaagd, 0 gefaald | `test-results.log` |
| Android UI-workflow op API 35 | 1 geslaagd, 0 gefaald | `android-ui-tests.log` |
| Python OAuth-backend | 6 geslaagd, 0 gefaald | `backend-tests.log` |
| Statische analyse | Geen issues | `analysis.log` |

Totaal: **80 automatische testcases**. De Android UI-case bevat meerdere controles/handelingen, maar wordt eerlijk als één test geteld.

Belangrijke dekking: bekende GPS-afstand; gemiddelde/maximale snelheid; tijden; manuele/automatische pauze/hervatting; slecht GPS/NaN/sprongen/dubbele timestamps; hoogtefilter; herstel; state-machinefouten; sensorverlies; 8/16-bit HR; crankrollover; GPX/XML en segmentonderbrekingen; routevoortgang/afwijkingen; heropenen SQLite na sluiten; schema-upgrade; idempotent opslaan/sync; gelijktijdige instellingen; back-up; tokenverversing; 429/retries; uploadonzekerheid; intervalgrenzen; profielkeuze; instellingen-, sensor- en kaartpagina's.

De Android-workflow start de app, kiest een profiel, opent de veldconfiguratie, start echte GPS-registratie, pauzeert/hervat, bewaart een rit, controleert daadwerkelijk opgeslagen GPS-punten, opent geschiedenis en een rit, opent de kaart, wijzigt een instelling en opent sensoren/appmenu.

De huidige suite dekt niet alle twintig afzonderlijke gevraagde UI-scenario's of alle combinaties van hardware, Android-versies, batterijbeperkingen en netwerkstoringen. Eerdere fouten zijn hersteld en relevante tests opnieuw uitgevoerd; tests zijn niet uitgezet voor een groen resultaat.

## Bekende ontbrekende functionaliteit

1. Volledige offline wegenroutering en offline adreszoeken; momenteel alleen offline routespoorbegeleiding en lokale achtergrondkaarten.
2. Vrij toe te voegen gegevenspagina's, instelbare raster-/veldgrootte, door de gebruiker te wijzigen profielkleuren en volledige profieleditor. Pagina's worden automatisch uit de veldvolgorde opgebouwd; hun aantal en raster kunnen nog niet vrij worden ingesteld.
3. Automatische herkenning van afzonderlijke beklimmingen, vrije-rit-klimvoorspelling en een volledige ClimbPro-equivalent.
4. ANT+, wielsnelheid/omtrek, sensorbatterij, automatische BLE-herverbinding, sensorkalibratie en prioriteiten.
5. FIT-export, automatische ronden, genormaliseerd vermogen, uitgebreide hartslagzones en trainingsplaneditor.
6. Strava Live Segments/leaderboards, Komoot, Ride with GPS, weer en muziekbediening.
7. Uitgebreid archiefzoeken/filteren, favorieten/notities per rit en interactieve tijdreeksgrafieken voor alle sensormetingen.
8. WorkManager-synchronisatie op de achtergrond; synchronisatie wordt nu handmatig gestart.
9. Volledig instelbare waarschuwingen per categorie, audio/spraak voor iedere melding, automatische schermvergrendeling en draai-instellingen.
10. Voeding/hydratatie registreren telt gebeurtenissen; geen hoeveelheden of voedingsanalyse.
11. Beheerde kiosk/provisioning, recente Android-apps en volledige configureerbare dashboardwidgets.
12. Detectie van offline kaartdekking vóór vertrek is nog handmatig; een geïmporteerd bestand garandeert niet dat ieder gebied/zoomniveau beschikbaar is.

De app verbergt deze beperkingen niet achter verzonnen data, nepverbindingen, een rechte lijn als fietsroute of een niet-geteste integratiestatus.

## Build, APK en gebruik

- Debug: `build/app/outputs/flutter-apk/app-debug.apk`.
- Release: `build/app/outputs/flutter-apk/app-release.apk` en `build/app/outputs/apk/release/app-release.apk`.
- Handige kopieën: `dist/UltimateBikeComputer-debug.apk` en `dist/UltimateBikeComputer-release.apk`.
- Handtekening: persoonlijke projectsleutel; geen Android-debugcertificaat voor release.
- Applicatie-ID: bestaande `com.example.bike_computer` behouden.
- Minimum API 24; target/compile API 36. Geteste runtime API 35.
- Volledige broncode, lockfile, Android-configuratie en optionele OAuth-backend staan in deze projectmap.

Installeren: open de release-APK op Android en geef de bestandsapp toestemming om APK's te installeren. Android Studio en Codex zijn op het doeltoestel niet nodig. Launcher: Settings > Apps & Launcher > Standaardlauncher instellen. Eerste rit: profiel kiezen, GPS-/scherminstellingen controleren, START RIDE > START en de noodzakelijke machtigingen geven.

Zie [README.md](README.md) voor installatie, eerste rit, machtigingen, providers, privacy, Strava, signing en buildcommando's.
## Aanvullende runtime- en visuele controle

Op de persoonlijk ondertekende release, in de afzonderlijk aangemaakte Android 15-emulator:

- APK-installatie en koude start geslaagd.
- GPS-rit opgenomen, gepauzeerd, hervat en opgeslagen.
- Proces geforceerd beëindigd; bij openen van het fietsscherm verscheen het herstelverzoek. De rit herstelde gepauzeerd, kon hervatten en kon worden opgeslagen.
- Via de echte Android-documentkiezer een GPX-export opgeslagen; het teruggelezen XML-bestand bevatte 11 trackpunten. Bewijs: `artifacts/exported-emulator-ride.gpx`.
- Via diezelfde native bestandskiezer GPX en een zelfgemaakte raster-MBTiles-testkaart geïmporteerd. De kaart werd zonder appherstart zichtbaar.
- Tijdens schermuitval liep GPS-registratie door; de zichtbare point count groeide van 3 naar 15. Dit is een korte emulatortest, geen duurtest op fietshardware.
- Scherm-/dichtheidswijziging tijdens een gepauzeerde rit behield de rit. De aanvankelijk ontbrekende Android `configChanges`-configuratie is hersteld.
- De officiële launcher-keuzedialoog vermeldt Ultimate Bike Computer als beschikbare Home-app. De standaardlauncher van de testemulator is niet gewijzigd.
- Vanuit het eigen appmenu Android Instellingen geopend.
- Portret (320×640 en 1080×1920) en liggend (1280×720) geïnspecteerd. Een overlopende Home-statusbalk, een achterblijvende GPS-waarschuwing, te weinig ruimte voor gegevensvelden en te kleine cijfers in de liggende lay-out zijn aangepast.

Screenshots: `artifacts/screenshots/home.png`, `home-large.png`, `ride-final.png`, `ride-landscape.png`, `navigation-offline-map.png`, `climb.png`, `ride-summary.png`, `history.png`, `sensors.png`, `settings.png`, `launcher-role.png` en `app-menu.png`. Tussentijdse screenshots in dezelfde map zijn geen afzonderlijk testresultaat.

De emulator-GPX en MBTiles-testdata staan alleen onder `test/fixtures` en de testemulator, niet als vooraf gevulde gegevens in de release-APK. Sensoren zijn niet fysiek getest. Ruwe sensortijdreeksen worden nog niet opgeslagen; wel de beschikbare aggregaten.

## Artefactcontrole

Beide APK's zijn daadwerkelijk aanwezig; debug en release zijn succesvol gebouwd. De releasehandtekening is door `apksigner verify` gecontroleerd. Publieke certificaatinformatie: `artifacts/apk-signature.txt`. SDK/ABI-metadata: `artifacts/apk-metadata.txt`. Bestandsomvang en SHA-256: `dist/checksums.json`.

`dist/UltimateBikeComputer-debug.apk` gebruikt een harde koppeling naar de debug-build om dubbele opslag op de vrijwel volle D:-schijf te vermijden. Het is een normaal installeerbaar APK-bestand. De release in `dist` is een zelfstandige kopie. Gegenereerde buildtussenbestanden zijn behouden nadat automatisch opruimen door de veiligheidscontrole werd geweigerd; er is geen alternatieve recursieve verwijdering uitgevoerd.
