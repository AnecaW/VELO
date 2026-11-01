# Verbonden apps — versie 2.1

## Keuze van de eigenaar: zonder servers

De opgegeven publieke Strava client-ID is **292844**; het geregistreerde callbackdomein is **localhost**. Er is geen server gestart, geen hosting aangemaakt en geen client secret gevraagd of in de APK opgenomen.

Met alleen deze waarden kan de app geen veilige zelfstandige Strava-accountkoppeling maken. De [officiële Strava OAuth-documentatie](https://developers.strava.com/docs/authentication/) vereist het client secret bij zowel code-uitwisseling als tokenvernieuwing. De gepubliceerde flow documenteert geen PKCE waarmee een openbare mobiele client dat secret kan vervangen. Een localhost-callback verplaatst alleen de terugkeerlocatie; hij vervangt die eis niet. De app embedt geen secret en gebruikt geen ongedocumenteerde token-endpoints.

Daarom is **de live Strava-accountkoppeling niet voltooid of als werkzaam getest**. Zonder een geconfigureerde HTTPS-broker wordt geen OAuth-knop aangeboden die een onvoltooibare flow start. De echte status is Niet verbonden. Automatische synchronisatie is zonder account niet actief.

Wat zonder server werkt:

- Meer → Verbonden apps → GPX uitwisselen: GPX-route uit Android Bestanden importeren, begrensd op 10 MB en gevalideerd met de bestaande parser.
- De route komt met bron GPX-import en importdatum in Kaart → Lokale routes. De oorspronkelijke GPX wordt lokaal bewaard. Een inhoudshash voorkomt dubbele import van hetzelfde bestand.
- Een zelf opgenomen rit met werkelijk GPS-spoor exporteren via Androids bestandskiezer.
- De officiële [Strava-bestandsupload](https://www.strava.com/upload/select) openen; de gebruiker kiest daar zelf het bestand en uploadt het. Alleen openen van die pagina uploadt niets en betekent geen gekoppeld account.
- Komoot openen en bestanden uitwisselen via de eigen toegestane export/import. De app leest geen privésessies uit en gebruikt geen onofficiële Komoot-API.

## Optionele OAuth-implementatie, uitsluitend na andere configuratiekeuze

De vroegere handmatig overgenomen autorisatiecode is uit de productie-interface verwijderd. Een modulaire optionele implementatie staat klaar voor geautoriseerde configuratie met een HTTPS-broker. Die is getest met gescheiden testdoubles, niet met een echt account.

Architectuur: IntegrationProvider/IntegrationRegistry, TokenStore/SecureTokenStore, StravaService, StravaIntegration, StravaCache, SyncRepository, SyncEngine en IntegrationCoordinator/WorkManager. De UI gebruikt echte opgeslagen account- en taakstatussen. Alleen de Strava-adapter is als OAuth-adapter geïmplementeerd. Andere diensten worden als informatie over beschikbaarheid getoond, zonder nep-Connect-knoppen.

De optionele flow:

1. De app maakt een cryptografisch willekeurige state en verifier. De verifier blijft in flutter_secure_storage; alleen de S256-challenge gaat naar `/start`.
2. De broker controleert client-ID/scopes en levert uitsluitend de officiële `https://www.strava.com/oauth/authorize`-URL. De app opent die in een externe browser.
3. Strava stuurt code en scopes naar de geconfigureerde HTTPS `/callback`. De broker valideert state, beperkte levensduur en hergebruik.
4. De callbackpagina biedt een terugkeerknop naar `ultimatebike://oauth/strava` met uitsluitend state en een eenmalige, verifiergebonden overdracht. Geen access/refresh token of Strava-autorisatiecode staat in deze app-link.
5. De app controleert scheme/host/path, unieke parameters, state en tien minuten geldigheid. `/exchange` vereist ook de oorspronkelijke verifier. Alleen de broker wisselt de code bij Strava in met het client secret.
6. Tokens, sessiecredential en verleende scopes komen uitsluitend in veilige tokenopslag. Refresh roteert tokens. Een verlopen of ingetrokken machtiging vraagt opnieuw verbinden. De S256-bescherming betreft onze app-broker-overdracht; dit is geen claim dat Strava zelf PKCE ondersteunt.

Android: het manifest bevat een VIEW/BROWSABLE-filter voor exact `ultimatebike://oauth/strava`; Flutter-router-deeplinking is uitgezet ten gunste van app_links. Het externe browservenster vraagt nooit Strava-wachtwoorden in onze app. iOS/HealthKit is niet gebouwd of geverifieerd in deze Windows/Android-oplevering.

## Automatische synchronisatie wanneer een echt account geconfigureerd is

Per dienst zijn gegevensuitwisseling, automatisch, bij openen, na rit, bij netwerkherstel en alleen wifi afzonderlijk instelbaar. Uploaden staat standaard uit en vraagt expliciete toestemming. WorkManager plant beperkt achtergrondwerk circa zes uur; Android, energiebesparing, force-stop en fabrikantbeleid kunnen uitvoering uitstellen. Er is geen belofte van onmiddellijke achtergrondupdates.

De engine gebruikt een SQLite-lease tegen overlappende foreground/background-taken, persistente status/cursor, een uitgaande wachtrij, exponentiële back-off en Retry-After. De officiële rate-limitheaders worden gecontroleerd. Inkomende activiteiten worden incrementeel met overlap opgehaald; een gedeeltelijk mislukte paginering schuift de cursor niet door. Een periodieke beperkte verversing houdt de tijdelijke cache bruikbaar. Maximaal zeven recente dagen, 200 activiteiten per poging en tien routes begrenzen API-gebruik; dit is geen volledige accountarchivering.

Een Strava-route wordt niet voor automatische herberekening naar openrouteservice doorgestuurd. Cacheopruiming controleert de bron-ID van de geselecteerde route, zodat een afzonderlijke lokale GPX-route met dezelfde geometrie behouden blijft.

Een lokale rit wordt alleen na opslaan geselecteerd voor automatische upload als automatisch, na-rit en uploaden allemaal zijn ingeschakeld. Geïmporteerde gegevens worden nooit opnieuw gepubliceerd. Een activiteit-ID die al aan een lokale upload gekoppeld is, wordt niet als tweede rit geïmporteerd. Een onzekere upload wordt niet blind herhaald: controleer eerst Strava.

## Gegevens en beperkingen van Strava

De [Strava API Policy](https://www.strava.com/legal/api_policy) beperkt cacheopslag tot zeven dagen, stelt eisen aan het verwerken van verwijderingen en verbiedt onder meer gecombineerde analyses en gebruik van API-data met AI. Daarom blijven opgehaalde activiteiten gescheiden van eigen ritten, trainingsresultaten en lokale statistieken. De lokale generator gebruikt deze gegevens niet. De activiteitweergave toont alleen geleverde waarden en de bron Strava.

Onze cache vervalt al na 24 uur; opruimen gebeurt bij openen, periodiek terwijl de app draait en met een lokale WorkManager-opruimtaak. Android kan werk na force-stop blokkeren; verlopen cache wordt bij het volgende openen verwijderd voordat zij wordt getoond. Geïmporteerde routes en oorspronkelijke GPX uit de API vallen onder dezelfde cacheduur. Een geselecteerde kaartkopie vervalt mee. Strava-cache en tokens worden niet opgenomen in JSON-back-ups. Op verzoek en bij ontkoppelen wordt de cache verwijderd. Een mislukte online intrekking wordt als zodanig gemeld; lokale tokens worden wel verwijderd. De gebruiker kan toegang ook bij Strava → My Apps intrekken.

## Dienstenoverzicht en geraadpleegde primaire bronnen

| Dienst | Echte status in deze build |
| --- | --- |
| Strava | Optionele officiële OAuth/API-adapter geïmplementeerd; zonder broker niet verbonden. GPX handmatig werkt onafhankelijk. |
| Komoot | [Geen publieke API](https://support.komoot.com/hc/en-us/articles/10331570510618-komoot-API); geen directe login. Toegestane GPX-uitwisseling. |
| Garmin Connect | [Ontwikkelaarsprogramma](https://developer.garmin.com/gc-developer-program/overview/) vereist toegangsregistratie/goedkeuring. Geen geconfigureerde adapter. |
| Wahoo | [Cloud API](https://developers.wahooligan.com/cloud) vereist registratie en goedkeuring. Geen geconfigureerde adapter. |
| Ride with GPS | [Officiële OAuth API](https://ridewithgps.com/api) bestaat. Eigen API-client en afzonderlijke adapterimplementatie ontbreken; geen koppeling aangeboden. |
| TrainingPeaks | [Alleen goedgekeurde ontwikkelaars, geen persoonlijk gebruik](https://help.trainingpeaks.com/hc/en-us/articles/234441128-TrainingPeaks-API). Geen adapter. |
| Health Connect | [Officiële Android-API](https://developer.android.com/health-and-fitness/health-connect) vereist systeemtoestemming en gegevensadapter; geen adapter geïmplementeerd. Er worden geen gezondheidsgegevens gelezen. |
| Apple Health | [HealthKit](https://developer.apple.com/documentation/healthkit) vereist Apple-platform, entitlement en toestemming. Geen Android-koppeling of iOS-adapter. |
| Google Fit | Google verwijst naar [migratie naar Health Connect](https://developer.android.com/health-and-fitness/health-connect/migration/fit). Geen nieuwe Fit-koppeling aangeboden. |

Het officiële Connect with Strava-beeldbestand is ongewijzigd afkomstig uit de [Strava-brandrichtlijnen](https://developers.strava.com/guidelines/). Het is alleen zichtbaar als een HTTPS-broker is ingevuld. Voor niet-geïmplementeerde diensten worden neutrale informatie-iconen gebruikt; geen verzonnen merksymbolen of accountgegevens.

## Alleen voor een eventuele latere eigen broker

Deze stappen zijn optioneel en **niet uitgevoerd**, omdat de eigenaar geen servers wil:

1. Configureer een eigen geregistreerde Strava-app. Laat de callback domain overeenkomen met de HTTPS-host van de broker; het huidige localhost is niet de host van een publieke HTTPS-broker.
2. Zet uitsluitend op die broker de variabelen uit `backend/.env.example`. Het publieke client-ID mag 292844 zijn. Het echte client secret en een sterke willekeurige SESSION_SECRET blijven buiten broncode, app en logs. De Python-code leest procesomgevingsvariabelen; een .env-bestand wordt niet automatisch geladen.
3. Run `python backend/strava_oauth.py` achter een HTTPS reverse proxy. De interne poort luistert uitsluitend op 127.0.0.1. Gebruik geen proxy-accesslogs voor OAuth-callbackquery's en geen requestbodylogging. Beveilig en beperk de publieke service.
4. Vul de HTTPS-basis-URL en publieke client-ID in de app in. Registreer exact `PUBLIC_URL/callback` bij Strava. `/config` geeft uitsluitend publieke configuratie terug.
5. Kies alleen benodigde categorieën en scopes. Publieke activiteiten gebruiken activity:read; privédata is opt-in activity:read_all. Routes gebruiken read of optioneel read_all. Uploads gebruiken uitsluitend na toestemming activity:write.
6. Doorloop echte toestemming, terugkeer, ophalen, verversen, intrekken en netwerkherstel met een eigen account. Nieuwe Strava-apps hebben beperkte athlete-capaciteit; [de officiële rate-limitpagina](https://developers.strava.com/docs/rate-limits/) beschrijft capaciteit en review. Geen echte succesvolle login of upload mag worden aangenomen op basis van alleen tests met mocks.

## Verificatie en APK's

De eerste 93 bestaande tests slaagden vooraf. Nieuwe tests gebruiken mocks alleen in testcode en controleren onder andere OAuth-state/verifier/expiry/weigering, tokenrotatie, ingetrokken toegang, API-limieten, cursors, cacheverval, back-upexclusie, idempotentie, lussen, offline/wifi, leases, ontkoppelen en UI-statussen. De Python-brokertests gebruiken een lokaal test-HTTP-proces; dit is geen draaiende productieserver.

De definitieve resultaten staan in `accounts-analysis.log`, `accounts-tests.log`, `accounts-backend-tests.log`, `accounts-debug.log` en `accounts-release.log`. Artefacten staan in `dist/UltimateBikeComputer-debug.apk` en `dist/UltimateBikeComputer-release.apk`, met SHA-256 in `dist/checksums.json`. Debug en release hebben verschillende bestaande handtekeningen. Alleen debug kan de bestaande debug-installatie op de Huawei bijwerken zonder verwijderen.

Uitgevoerd: 120 Flutter-tests geslaagd, 12 Python-brokertests geslaagd en flutter analyze zonder problemen. Op de Huawei P30/Android 10 is de nieuwe debug-app met install -r bijgewerkt, zonder de app te verwijderen. Meer → Verbonden apps, de echte status Niet verbonden, publieke client-ID 292844, de serverloze uitleg, GPX-pagina en het openen/annuleren van de native Android-bestandskiezer zijn fysiek gecontroleerd. Screenshots: `artifacts/accounts/screenshots`; uitvoer: `accounts-phone-smoke.log`. Er is geen persoonlijk bestand op de telefoon geïmporteerd en er is niets naar Strava geüpload. De enige geplande WorkManager-taak zonder verbonden account is lokale cacheopruiming. De eerste herhaling van de emulator-integratietest strandde op een tijdelijk weggevallen ADB/VM-serviceverbinding; dat is geen geslaagde producttest.

Definitief slaagt ook de uitgebreide Android-integratietest: starten/opnemen, tabwissels Kaart/Training/Fiets, pauze/hervatten, GPS-punten opslaan/teruglezen, geschiedenis, kaart, instellingen, sensoren, launcher, Meer → Verbonden apps en de serverloze GPX-pagina. De testemulator is opnieuw opgestart en de test kiest expliciet de hoofdlijst bij het scrollen. Bewijs: `accounts-integration.log`, eindstatus `All tests passed`. De eerdere mislukte poging staat afzonderlijk in het verbose-log; die is niet als geslaagd meegeteld. Het handmatig forceren van de periodieke opruimtaak op de Huawei werd door WorkManager uitgesteld omdat het volgende uitvoermoment nog niet bereikt was; dit bewijst planning, geen uitgevoerde achtergrondsynchronisatie.

Na de laatste aanpassing van accountmeldingen zijn alle 27 gerichte account-/synchronisatietests opnieuw geslaagd (`accounts-focused-tests.log`). Voer Flutter-tests en APK-builds na elkaar uit: de testtool kan het gegenereerde Android-pluginregister wijzigen, wat een gelijktijdige releasebuild verstoort. De definitieve release wordt afzonderlijk zonder actieve Flutter-tests gebouwd. Er is geen echte OAuth-aanmelding, refresh, API-import of Strava-upload op de telefoon getest; de serverloze configuratie voldoet niet aan die voorwaarden en wordt ook niet als volledige Strava-accountintegratie opgeleverd.
