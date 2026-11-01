# VELO 2.6 — fietstypes en navigatie

## Gebruiken

1. Open **Fiets** en tik op het fietstype boven de meetvelden. Kies een fiets. De keuze blijft op het toestel bewaard en wordt met je instellingen gesynchroniseerd.
2. Open **Kaart**. Typ minstens drie tekens in het zoekveld. Kies een suggestie, of tik rechtstreeks op de kaart.
3. Tik op **Bereken route**. Bekijk afstand, providerreistijd en stijging indien geleverd. **Ander alternatief** vraagt maximaal twee extra routes; identieke resultaten worden niet als alternatief toegevoegd.
4. Kies **Navigeren in VELO** of **Google Maps**. Een externe app opent alleen op jouw verzoek. Android kan vragen welke kaartapp je wilt gebruiken.
5. Tijdens interne navigatie kun je naar **Fiets** gaan en een opname starten. De navigatie blijft actief bij tabwissels en scherm uit. Stoppen van de ene functie stopt de andere niet.
6. Stop navigatie met **Stop navigatie**. Een geselecteerde route blijft lokaal beschikbaar na herstart; navigatie hervat na procesbeëindiging pas wanneer je weer op navigeren tikt. Het bestaande herstelproces voor ritopnamen blijft beschikbaar.

## Fietstypes en Strava

| Fiets | Vast opgeslagen ID | Officieel Strava sport_type | BRouter-profiel |
|---|---|---|---|
| Racefiets | road | Ride | fastbike |
| Mountainbike | mountain | MountainBikeRide | mtb |
| Gravelbike | gravel | GravelRide | gravel |
| Elektrische fiets | electric | EBikeRide | trekking |
| Elektrische mountainbike | electricMountain | EMountainBikeRide | mtb |
| Stadsfiets | city | Ride | trekking |
| Trekkingfiets | trekking | Ride | trekking |
| Andere fiets | other | Ride | trekking |

De gebruikte publieke BRouter-installatie biedt geen afzonderlijk e-bikeprofiel aan. VELO toont en gebruikt voor deze fietsen daarom het vermelde trekking- of MTB-profiel; dit is geen berekening van accu, motorondersteuning of actieradius.

Bij de eerste start van een nieuwe rit wordt het type vastgezet in `RideSession`. Pauzeren, hervatten, checkpoints, opslaan en cloudsynchronisatie behouden dit type. Wijzigingen aan de standaardfiets herschrijven bestaande ritten niet. Tijdens de opname toont de selector het vaste type en is die vergrendeld. Het ritoverzicht toont het opgeslagen type. Oude v1-ritten zonder fietstype blijven leesbaar met de bestaande generieke `Ride`/racefiets-default; hun oorspronkelijke fietstype is niet achteraf vast te stellen.

Snapshots houden formaatversie 1 en voegen `bikeType` en `sport_type` toe. De bestaande JSONB-datalaag bewaart deze velden; een destructieve SQL- of Drift-migratie is niet nodig. De server bepaalt het uploadveld opnieuw uit de whitelist van fiets-ID's en gebruikt uitsluitend `sport_type`, niet het verouderde `type`. De bestaande upload-ID, idempotentie en verwijderingsbewijzen blijven ongewijzigd. Een sporttypewijziging maakt geen tweede Strava-activiteit.

## Providers en verwisselbaarheid

- **Kaart:** bestaande MapLibre Native (`maplibre_gl`) met OpenFreeMap/OSM. Donkere en lichte stijlen, verplaatsen, zoomen, kompas, positie volgen, bestemmingsmarker en routespoor. De stijl is instelbaar bij Kaartinstellingen. De native informatieknop bevat de bronattributie; rasterkaarten tonen hun bestaande attributie.
- **Geocoding:** `GeocodingService` met `PhotonGeocoder`. Forward en reverse geocoding via HTTPS. Minimaal drie tekens, debounce 600 ms, geserialiseerde verzoeken met minstens één seconde tussen verzoekstarts, maximaal zes suggesties en lokale deduplicatie. De actuele GPS-positie geeft geografische voorkeur. OSM-lokale namen blijven behouden, omdat de publieke Photon-server geen `lang=nl` ondersteunt. Geen publieke Nominatim-autocomplete.
- **Routing:** `CyclingRouter` met `BRouterService`. Twee echte waypoints, het fietsprofiel, GeoJSON en `timode=1`. Coördinaten en antwoord worden gevalideerd. Afslaginstructies komen uitsluitend uit BRouter-voicehints; manoeuvrecodes worden naar Nederlands vertaald. Ontbrekende tijd, hoogte of hints blijven ontbrekend. De resterende reistijd is een schatting op basis van de providerduur en routevoortgang, geen verkeersinformatie.
- `PHOTON_URL` en `BROUTER_URL` zijn optionele publieke `--dart-define`-waarden voor een andere compatibele instantie. Een andere API kan de abstracte service implementeren zonder de kaart te vervangen. Geen sleutels nodig voor de standaardproviders. De eerdere ORS-client en serverproxy blijven beschikbaar voor compatibiliteit, maar de actieve navigatie en offline-gebiedzoeker gebruiken ze niet meer.

Photon en BRouter zijn publieke diensten zonder beschikbaarheidsgarantie. De app beperkt autocomplete, caching, alternatieven en herberekeningen. BRouter-verzoeken hebben een timeout van 45 seconden; de publieke client accepteert maximaal 200 km hemelsbrede afstand. Nieuwe routes of adressen kunnen tijdelijk mislukken door een limiet of storing. Een bestaande route en lokale fietscomputer blijven bruikbaar. Bij structureel hoger gebruik is een eigen of contractueel geschikte provider nodig; er wordt geen server geïnstalleerd door deze wijziging.

## GPS, achtergrond en herberekenen

`LocationHub` geeft onafhankelijke leases op één `RealGPSService`. Navigatie en de productie-RideController delen dezelfde Android-geolocatorstream. Een lease stoppen verwijdert alleen die afnemer; de bron stopt pas bij de laatste lease. De bestaande instellingen voor GPS-interval en nauwkeurigheid blijven gelden. Een bestaande opname heeft voorrang op het standaardfietstype bij nieuwe routeplanning.

De Android-manifestpermissies voor locatie, foreground location service, wake lock en meldingen waren al aanwezig. VELO vraagt locatie en meldingen op het toestel; de foreground-service wordt vanuit de zichtbare app gestart en blijft tijdens actieve navigatie of ritregistratie werken wanneer het scherm uitgaat. Er is geen nieuwe aanvraag om onbeperkte achtergrondlocatie toegevoegd. Android-fabrikantinstellingen kunnen een proces alsnog beëindigen; ritcheckpoints en de geselecteerde route blijven lokaal bewaard. Na een procesherstart hervat VELO geen navigatie stilzwijgend.

Afwijking gebruikt de afstand tot het routespoor plus de gerapporteerde GPS-fout. Herberekenen vereist nauwkeurigheid van maximaal 35 m en minimaal 12 seconden aanhoudende afwijking; weer op de route of een onnauwkeurige fix reset de wachttijd. Er is maximaal één automatische poging per minuut. De instelling **Automatisch herberekenen** kan uit. Tijdens een aanvraag blijft de bestaande route zichtbaar; een laat antwoord vervangt geen ondertussen gekozen andere route. Tijdelijke Strava-routes worden niet automatisch naar een andere router gestuurd.

## Offline, opslag en privacy

- Ritregistratie en het volgen van een lokaal opgeslagen route, inclusief geleverde instructies, blijven offline werken.
- Nieuwe adreszoeken en nieuwe/herberekende routes vereisen internet. Recente gelijke zoekopdrachten kunnen maximaal zeven dagen uit de lokale cache komen; er worden maximaal vijftig queryresultaten bewaard.
- De geselecteerde bestemming en route staan lokaal in Drift. Eerder berekende routes zijn via de mapknop beschikbaar; GPX-import blijft werken.
- Een gewone kaartcache garandeert geen gebiedsdekking. VELO onderscheidt een volledig gedownload gebied op de huidige positie van uitsluitend eventueel gecachete tegels. Een gebied buiten die positie wordt niet als beschikbare offline kaart gepresenteerd. Controleer ook zoomniveau en volledige routedekking vóór vertrek.
- Bestaande OpenFreeMap-downloads blijven beschikbaar bij **Kaartinstellingen → Offline gebieden**. De client begrenst op 2.500 geraamde tegels, maximaal vier parallelle verzoeken, de native 3.000-tegellimiet en pauzeren rond 48 MB. Dit blijft onder de gepubliceerde limieten van 3.000 tegels of 50 MB per download. Voor raster-MBTiles gelden de licentie en dekking van het geïmporteerde bestand.
- Online kaarten delen het bekeken kaartgebied met de provider. Zoeken deelt de query en zo mogelijk locatievoorkeur met Photon. Routering deelt vertrekpunt en bestemming met BRouter. Er worden geen Strava-tokens of backendsecrets meegestuurd.

## Gecontroleerde bronnen en licenties

Gecontroleerd op 1 november 2026:

- [Officiële Strava uploadvelden en sport_type](https://developers.strava.com/docs/uploads/).
- [Photon API en publieke servervoorwaarden](https://github.com/komoot/photon): software Apache-2.0, redelijk gebruik en geen beschikbaarheidsgarantie.
- [BRouter project](https://github.com/abrensch/brouter): MIT; [actuele publieke profielen](https://brouter.de/brouter/profiles2/); [officiële manoeuvrecodes](https://github.com/abrensch/brouter/blob/master/brouter-core/src/main/java/btools/router/VoiceHint.java).
- [OpenFreeMap mobiele/offlinevoorwaarden en attributie](https://openfreemap.org/quick_start/). Kaartgegevens van OpenStreetMap onder ODbL, attributie aan OpenStreetMap-bijdragers; stijl en kaartbronnen houden hun eigen licenties.
- [MapLibre Native](https://github.com/maplibre/maplibre-native): BSD-2-Clause. Er is geen nieuwe SDK toegevoegd; de bestaande Flutter- en native-licentiemeldingen blijven behouden.

## Verificatie

Live op de Huawei: racefiets/MTB/gravel selecteren, alle acht opties zichtbaar, gravelkeuze na force-stop/herstart bewaard; donkere kaart en echte locatie; echte Grote Markt-suggesties met Sint-Niklaas en Antwerpen; suggestie kiezen en bestemming centreren; gravelroute berekenen, alternatief kiezen, interne navigatie starten, tabwissel naar fietscomputer, scherm uit/aan met foreground GPS-service en behoud van navigatie; wifi uit/aan met behoud van route en expliciete offline-status; kaart aantikken met echt reverse-geocodeadres; Google Maps opent als externe Android-app. Wifi is terug ingeschakeld. Tijdens deze controle is geen nieuwe activiteit naar Strava geüpload.

Live providerchecks: straat `Damrak`, plaatsen `Antwerpen`/`Sint-Niklaas`, postcodes `9100`/`1012`, onvolledige `Grote Markt` en reverse geocoding leverden resultaten. Voor dezelfde openbare testpunten leverden fastbike, mtb en gravel verschillende routes; trekking gaf ook een geldige route. Afstand, tijd, stijging en hints kwamen uit de echte providerantwoorden.

Automatisch: 180 Fluttertests en 19 Edge-tests geslaagd. Nieuwe tests dekken keuze/persistentie, onveranderlijke snapshots, opname/pauze/herstel, gedeelde GPS met doorlopende trackpunten nadat navigatie stopt, autocomplete-debounce en selectie, providerprofielen, beide geocoders, caching, ontbrekende providerdata, fouten/rate limit, route-opslag, afslagvertaling, off-route-hysterese, Google Maps-URL en het echte multipart-Strava-uploadcontract (`GravelRide`, geen `type`). Alle acht serverwaarden en ongeldige input zijn getest.

De nieuwe fietstypes zijn niet met acht echte Strava-uploads getest: dat zou ongewenste testactiviteiten maken. Het uploadcontract is geïsoleerd getest; de echte GPX-uploadketen was in 2.5 al gecontroleerd. Er is tijdens deze controle geen volledige bewegende buitenrit met herberekening afgelegd. Afwijkingsdetectie, herberekeningsdrempels en gelijktijdige opname zijn automatisch met expliciete test-GPS-input gecontroleerd; deze fixtures zijn nooit productieactiviteiten geworden.

Buildcontrole: `flutter pub get`, `flutter analyze`, de volledige Fluttertests en de Android-debug- en releasebuild met `config/supabase.json` zijn geslaagd. De laatste toetsenbordcorrectie is ook in de navigatiewidgettest gecontroleerd; er zijn geen analyzerproblemen. De bestaande niet-blokkerende Gradle-waarschuwingen over de toekomstige Workmanager/Kotlin-migratie blijven aanwezig.

De bijgewerkte Edge Functions zijn daadwerkelijk gedeployd: `velo-api` versie 19, `velo-worker` versie 19 en `velo-webhook` versie 9, alle ACTIVE. Voor de standaard kaart-, zoek- en routeproviders ontbreekt geen externe configuratie.
