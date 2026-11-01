# Productupgrade 2.0 — 1 november 2026

De bestaande Flutter-app is uitgebreid; GPS-registratie, Drift/SQLite, GPX, BLE-decoders, Android-platformfuncties en Strava-integratie zijn behouden. Het eerdere opleveringsdocument beschrijft versie 1 en is historisch.

## Interface en registratie

- Vijf blijvende tabs: Home, Kaart, Fiets, Training en Meer. De centrale Fiets-knop krijgt de nadruk. Meer bevat zoeken en de bestaande functies.
- OLED Black, Dark Graphite, Light en systeemthema; accentkleur, contrast, nachtvoorkeur en minimale fietsweergave. Subtiele glaswerking op de navigatiebalk; grote cijfers zonder zware blur tijdens een rit.
- Dashboard gebruikt opgeslagen ritten, actuele apparaatstatus en echte sensorverbindingen. Weekcijfers, laatste rit en planning kunnen verborgen worden.
- Applicatiebrede RideController beheert de opname en checkpoints, onafhankelijk van schermen. Wisselen van tab stopt of vervangt de opnameservice niet. Herstel na een procesherstart blijft mogelijk via de lokale checkpoint.
- Activiteitprofielen zijn bewerkbaar en persistent, inclusief automatische pauze en drempelsnelheid.

## Demo's en meetgegevens

De statische trainingsvoorbeelden zijn vervangen door een lokale generator en een lege bibliotheek totdat de gebruiker iets bewaart. Er worden geen ritten of trainingsresultaten vooraf gevuld. Ontbrekende GPS heeft een expliciete melding en geen positie-icoon; ontbrekende hartslag, vermogen en cadans blijven `—`. De wereldkaart zonder GPS is een overzicht, geen geclaimde locatie. Ook de oude rasterweergave gebruikt geen vaste Belgische startlocatie meer. GPS-fixtures blijven uitsluitend in tests en de expliciete debug-simulatie.

## Kaarten en offline gebruik

Engine: **MapLibre Native**, via `maplibre_gl 0.27.1`. De gegevensprovider is afzonderlijk beschreven in MapStyleSpec. OpenFreeMap levert echte OpenStreetMap-geografie; Midnight, Daylight en Cycle streets zijn drie stijlen van dezelfde provider. Midnight en Daylight zijn op de Huawei geladen en visueel bekeken. Een eigen HTTPS MapLibre-stijl kan worden ingesteld. Satelliet vereist een daadwerkelijk geschikte eigen provider. Google Maps is niet toegevoegd of als werkende optie voorgesteld.

De kaart ondersteunt pannen, zoomknoppen, schaal, native attributie, route/waypoints/start/einde, actuele positie, volgen en oriëntatie. Een kaart kan zonder actieve rit GPS opvragen. Bestaande favorieten, GPX-import/export, opgeslagen routes, routeprojectie, afslagteksten en optionele herberekening blijven beschikbaar. Adressen zoeken en nieuwe fietsroutes berekenen vereisen een eigen openrouteservice-sleutel. Offline kaarten zijn geen offline routeringsengine.

Offline kaarten: huidige locatie, routecorridor, vier coördinaten, plaats zoeken met ORS en twee hoeken kiezen op een interactieve kaart. Zoomkeuze 0–16. De downloader toont werkelijke native voortgang, grootte, datum, stijl, vrije opslag en volledigheid. Pauze/hervatten/retry/verwijderen gebruiken de native functies. Gedownloade gebieden worden na een herstart opnieuw uit de native opslag gelezen. Offline gebruiken kiest het juiste gebied, zoom en stijl.

De [OpenFreeMap quick start](https://openfreemap.org/quick_start/) is geraadpleegd voor het downloadbeleid. De app begrenst een aanvraag tot 2.500 geraamde vectortegels, native 3.000 tegels, vier gelijktijdige verzoeken en pauzeert boven 48 MB gemeten gegevens. Vooraf is 100 MB vrije ruimte nodig. De omvangcontrole is asynchroon en geen exacte bytegrens; de lokale cache kan gedeelde bronnen bevatten. Een eigen provider krijgt geen gebiedsdownload zonder afzonderlijke ondersteuning en toestemming.

Fysiek offline bewijs: handmatig gekozen Brussel-gebied 50.844/4.349–50.846/4.351, zoom 10–14, zeven geraamde tegels, circa 7,6 MB lokale bronnen. De native status meldde volledig. Daarna is wifi uitgezet, de app geforceerd gesloten en herstart, en de kaart opnieuw geopend. Straat-/plaatsgegevens van Brussel waren zichtbaar; wifi is naar de oorspronkelijke toestand hersteld. De app stond daarbij ook expliciet in native offline modus. Buiten de kleine gekozen begrenzing kunnen tegels ontbreken. Zie `artifacts/upgrade/screenshots/phone-offline-after-restart.png` en `phone-offline-test.log`.

## Training

- Lokaal bewaard profiel: doel/eigen doel, niveau, beschikbare tijd en dagen, binnen/buiten, voorkeur, intensiteit, eigen FTP en hartslagzone, sensorbeschikbaarheid.
- Regelgebaseerde generator met opwarming, duur- of werk/herstelblokken en cooling-down. De som van alle stappen moet exact de gekozen tijd zijn. Zonder FTP worden RPE-doelen gebruikt. Wattage komt uitsluitend uit een door de gebruiker ingevoerde FTP; trainingsbelasting is als schatting aangeduid.
- Bewaren, naam/stapduur/RPE wijzigen, dupliceren, verwijderen, opnieuw genereren en inplannen. Weekoverzicht en samenstellen op beschikbare trainingsdagen.
- Uitvoering met huidige/volgende stap, echte actieve tijd, pauze, hervatten, overslaan en stoppen. De timer blijft bij tabwissels bestaan. Actuele sensorgegevens worden lokaal opgeslagen en naast doelen getoond; bij vermogen is het verschil met het doel zichtbaar. Resultaten kunnen aan de actieve rit-ID gekoppeld worden.
- Zelf voltooid markeren is expliciet een eigen bevestiging met nul gemeten seconden en geen verzonnen sensorwaarden. Uitgevoerde en gestopte sessies worden afzonderlijk bewaard.
- Back-up/herstel bevat ook trainingsplannen, voorkeuren, resultaten en activiteitprofielen. Native offline kaartbestanden worden niet in de JSON-back-up opgenomen.
- TrainingGenerator/AiTrainingProvider vormen een optionele uitbreidingslaag. Er wordt geen externe AI aangeroepen. Het lokale advies is geen adaptieve coach; niet elke profielkeuze verandert de stapstructuur.

## Verificatie

De oorspronkelijke 73 tests slaagden vóór de wijziging. Definitief slagen **93 Flutter-tests**, **6 Strava OAuth-backendtests**, `flutter analyze` zonder problemen, de Android-integratietest, `flutter pub get` en de debug- en releasebuild. Er zijn regressietests toegevoegd voor generatorvalidatie, exacte duur, ontbrekende FTP, trainingsuitvoering, offline grenzen, blijvende opname, back-up, profielopslag en de scheiding tussen native vector- en rastercontrollers. Bewijs staat in de `upgrade-*.log` bestanden.

Android-emulator API 35: de volledige integratietest is geslaagd met echte Android-locatie-API en expliciete emulator-GPS-fixture: starten, velden, opname, tabwissels Kaart/Training/Fiets, pauze/hervatten, opslaan, GPS-punten teruglezen, geschiedenis, kaart, instellingen, sensoren en launcherpagina. De eigen telefoon krijgt nooit geïnjecteerde GPS. Twee gevonden kaartcontrollerfouten (oude rastercontroller zonder kaart en dubbel vrijgeven van native controller) zijn hersteld en de flow is opnieuw uitgevoerd. Een afzonderlijke DDS-startfout en een ongeschikte no-DDS-herhaling zijn gevolgd door een geslaagde normale run met vaste DDS-poort.

Huawei P30 ELE-L29, Android 10/API 29: de debug-app is met `adb install -r` bijgewerkt onder dezelfde bestaande handtekening. De app en gebruikersdata zijn niet verwijderd. Echte online kaarten, stijlwissel, kleine gebiedsdownload, offline herstart en trainingsgeneratie/start zijn fysiek gecontroleerd. Screenshots staan onder `artifacts/upgrade/screenshots`. De Android-testemulator is een afzonderlijk testapparaat; de testtool mag zijn testinstallatie verwijderen.

Aanvullend fysiek gecontroleerd: de opgeslagen training komt na appherstart terug; starten, pauzeren, Home/Training wisselen, terugkeren naar dezelfde gepauzeerde stap, hervatten en beëindigen werken. De werkelijk verstreken elf actieve seconden zijn als gestopt resultaat teruggevonden, met nul verzonnen sensormetingen. Een oudere onderbroken testsessie blijft als onderbroken herkenbaar. Zie `phone-training-final-execution.log` en de screenshots van pauze, stop en resultaten.

De uiteindelijke normale release-APK is daarnaast op de aparte emulator geïnstalleerd en gestart. Home en de native kaart met emulatorpositie zijn visueel gecontroleerd; zie `upgrade-release-map-smoke.log` en `emulator-release-map.png`. Op de Huawei zijn Home, Fiets, Meer, Instellingen en de lichte/OLED-weergave bekeken. Een vroege screenshot tijdens de themaovergang is vervangen door een controle na het uitlopen van de animatie; de lichte weergave heeft dan donkere leesbare tekst. Kaartzoomen en verschuiven zijn op de telefoon uitgevoerd. De debug- en release-APK zijn respectievelijk 230.006.787 en 97.447.400 bytes; de releasehandtekening is met apksigner geverifieerd.

Niet als fysiek bewezen beschouwd: een buitenrit met betrouwbare GPS-fix, langdurige batterij-/thermische belasting, gekoppelde fysieke BLE-sensoren, ORS-aanroepen met een persoonlijke sleutel en Strava-upload naar een echt account. Indoor op het aangesloten toestel was geen actuele GPS-fix beschikbaar; dat werd correct gemeld. Een trainingsproces wordt na een gedwongen appstop niet automatisch hervat; het laatste opgeslagen resultaat blijft als onderbroken/actief herkenbaar. Plaatszoeken met eigen ORS-sleutel, grafische gebiedsselectie en alle downloadfout-/pauzegevallen zijn geïmplementeerd maar niet volledig fysiek doorgelopen.

## Installatie en configuratie

`dist/UltimateBikeComputer-debug.apk` werkt als update van de huidige debug-installatie. `dist/UltimateBikeComputer-release.apk` is persoonlijk ondertekend met de bestaande releasekeystore en heeft een andere handtekening; die vervangt de debug-app niet rechtstreeks. Daarom wordt de debugversie op de telefoon behouden. Beide APK's zijn versie 2.0.0+2. Controlegetallen staan in `dist/checksums.json`.

ORS vereist een eigen sleutel via Integraties. Strava gebruikt de bestaande configureerbare OAuth-backend en persoonlijke accountautorisatie. Eigen kaartproviders kunnen eigen sleutels/licenties vereisen. Geen Google- of AI-sleutel is vereist voor de ingebouwde kaarten en lokale generator.

Ontwikkelbasis: Flutter 3.47.2, Dart 3.13.2, JBR 21, SDK 36. Door te weinig vrije ruimte op D: is alleen de gegenereerde buildmap verplaatst naar `C:\Users\wanne\.codex\builds\bike-computer-upgrade-20261101`; de normale `build`-map in het project is een NTFS-junction daarheen. Bronnen en gegevens zijn niet verplaatst. Dit is een lokale ontwikkelinstelling; een nieuwe checkout kan een gewone buildmap gebruiken. Keystore en key.properties moeten privé bewaard blijven.
