> Historisch verslag van versie 2.3.0. SMTP en e-mailbevestiging zijn nadien ingeschakeld; de actuele UI- en mailresultaten staan in [UI_AUTH_RESULTS.md](UI_AUTH_RESULTS.md).

# VELO — afwerking en werkelijk uitgevoerde controles

Uitgevoerd op 1 november 2026. De actieve cloud-backend is uitsluitend Supabase-project `pdooxhljbutbsotbjbrt` van VELO. De app gebruikt geen LAN-backend, Docker, Portainer of eigen domein.

## Resultaat

De app start op de fietscomputer. De vijf hoofddelen zijn Fiets, Kaart, Activiteiten, Training en Apps. Apps is een interne iconenhub met zoeken en toegang tot het bestaande dashboard, account, routes, kaarten, statistieken, sensoren, trainingen, profielen, gekoppelde diensten en instellingen. De Android HOME-intent en rolwijziging zijn verwijderd; de bestaande Android-launcher is niet vervangen. De app heeft een eigen adaptief VELO-icoon.

De bestaande OLED-/Liquid Glass-stijl, grote waarden en configureerbare gegevensvelden blijven behouden. De fietscomputer toont snelheid, gemiddelden, maximum, afstand, tijden en hoogte. Richting, GPS-nauwkeurigheid, coördinaten en daling zijn extra selecteerbare velden. Onbetrouwbare of ontbrekende GPS levert geen verzonnen snelheid of afstand op. Checkpoints, pauzeren, hervatten, opslaan en lokale geschiedenis blijven beschikbaar zonder internet.

MapLibre toont echte OpenFreeMap-kaarten, GPS-positie en routes, met rotatie, noord boven, centreren, zoom, GPX-import/-export en bestaande offline kaartfuncties. Online nieuwe routes berekenen vereist nog een OpenRouteService-key; opgeslagen routes en vooraf gedownloade kaarten hebben die niet nodig. De bestaande trainingsgenerator, intervaltimer, profielen, statistieken en Bluetooth LE-sensorfuncties zijn behouden. ANT+ en automatische smarttrainerbesturing worden niet als geïmplementeerd gepresenteerd.

## Schijf en build

Bij de mislukte releasebouw was D: werkelijk vol. `flutter clean` verwijderde uitsluitend gegenereerde Flutter-buildbestanden en maakte ongeveer 2,9 GB vrij. Broncode, assets, databases, configuratie en gebruikersgegevens zijn behouden. Bij de latere controle was ruim 220 GiB vrij op D:. De Gradle-cache op C: was circa 6,39 GiB; op C: was voldoende vrije ruimte en verplaatsen was niet nodig.

`flutter pub get`, debugbouw en ondertekende releasebouw zijn daadwerkelijk uitgevoerd. Een aangetroffen Android-ANR tijdens GPS-stop is onderzocht met de Android-stacktrace en opgelost door de officiële Android-locatieplugin bij te werken naar 5.2.1. De NMEA-listener wordt niet onnodig gestart. Zie de [officiële bugfix](https://pub.dev/packages/geolocator_android/changelog). Het compatibele `geolocator` 14.0.1 is gepind vanwege een Linux-dbus-conflict tussen de nieuwere wrapper en de bestaande connectivity-plugin.

## Supabase en beveiliging

- Officiële Flutter SDK met veilige sessie-/PKCE-opslag, refresh, uitloggen, wachtwoordwijziging en accountverwijdering.
- Registratie met directe toegang, minimaal 12 tekens voor wachtwoorden en access-JWT's van 15 minuten. Nieuwe gebruikers maken een Supabase-account aan; oude serveraccounts worden niet geïmpersoneerd.
- Acht toegepaste, geregistreerde SQL-migraties. Alle negen persoonlijke tabellen hebben RLS. Gebruikers kunnen geen andere eigenaar kiezen of rechtstreekse documentmutaties gebruiken om revisiecontrole te omzeilen.
- GPS-tracks staan apart van lichte activiteitmetadata; volledige sporen worden begrensd per pagina opgehaald. Sensorconfiguraties, favorieten, routes, training en instellingen blijven eigenaargebonden. Wachtrijen, geschiedenis en vervalacties hebben passende indexen.
- `velo-api` en `velo-worker` zijn daadwerkelijk gedeployed en actief. Servercron/Vault en HTTP 200-antwoorden zijn gecontroleerd. Geen service-role key of beheertoken in Flutter of Git.
- Provider-tokens zijn extra versleuteld met AES-GCM en aan de eigenaar gebonden. OAuth-state/handoff zijn eenmalig en verlopen. Tokenrefresh is per gebruiker vergrendeld; een ontkoppelde verbinding wordt niet door een lopende refresh hersteld.
- Lokale opslag en accountarchieven blijven behouden bij netwerkuitval. Conflicten zijn herstelbaar. Accountachtergrondwerk is onafhankelijk van Strava ingepland. Uploads na een rit gebruiken een duurzame lokale outbox en idempotente serverjobs.

Wachtwoordherstel blijft op verzoek expliciet uitgeschakeld zolang mailconfiguratie ontbreekt. De SDK-flow is voorbereid; later volstaan SMTP-instellingen in Supabase Auth en de serverflag `VELO_PASSWORD_RESET_ENABLED`. Registratie en login werken zonder SMTP.

## Werkelijk getest

- `flutter analyze`: schoon na de laatste stijlcorrectie.
- 148 Fluttertests: onder andere accounts, veilige sessies, gegevensisolatie, conflicten, offline synchronisatie, lokale ritregistratie, GPS-uitval/herstel, sensorverlies, kaarten, training, Apps en de duurzame Strava-uploadwachtrij.
- 35 live Supabase-controles met tijdelijke accounts: registratie, login, verkeerd wachtwoord, database/RPC, RLS, toegang zonder login, spoofed eigenaar, private RPC-afscherming, GPS-tracks, begrensde paginering, sensorconfiguratie, favorieten, conflicten, tombstones, refresh, intrekking en echte accountverwijdering. Testaccounts zijn verwijderd.
- 7 Deno-tests en typecontrole van beide Edge Functions: API-/workerafscherming, eigenaargebonden encryptie, GPX, OAuth-callback/replay, handoff-bewijs en verlopen/ingetrokken Strava-tokens. Providerreacties zijn fixtures; dit is geen live Strava-accounttest.
- Android-emulator: echte Supabase-registratie, directe toegang, secure-storage-herstel, uitloggen, opnieuw inloggen en synchronisatie. Ook de uitgebreide test van ritbediening, lokaal opslaan, geschiedenis, kaarten, training, instellingen, Apps en GPX-scherm is geslaagd.
- Fysieke Huawei ELE-L29, Android 10, toestel `XPH0219409001801`: debug-update succesvol geïnstalleerd zonder verwijderen van appgegevens. Start, achtergrondopname met actieve foregroundservice, pauze, hervatten en lokaal opslaan gecontroleerd. De korte stationaire testrit bevatte **4 echte GPS-punten**. Die ene testrit is daarna verwijderd; de vooraf bestaande rittenverzameling bleef exact gelijk. Alle vijf hoofddelen zijn geopend. Nova bleef de standaardlauncher.

Dit is een korte functionele toesteltest, geen geclaimde langdurige buitenrit of duurtest. Er was geen externe fietssensor beschikbaar voor een complete hardwaremeting; BLE-decodering en fout-/verliesgedrag zijn softwarematig getest.

## Externe configuratie die nog ontbreekt

1. Strava Client ID en Client Secret in Supabase Secrets, plus correcte officiële app-/callbackconfiguratie en toegestane athlete-capaciteit. Callback: `https://pdooxhljbutbsotbjbrt.supabase.co/functions/v1/velo-api/oauth/strava/callback`. Er is geen live Strava-koppeling of goedkeuring geclaimd. De [officiële OAuth-documentatie](https://developers.strava.com/docs/authentication/), [limieten/capaciteit](https://developers.strava.com/docs/rate-limits/) en [API Agreement](https://www.strava.com/legal/api) zijn gecontroleerd.
2. `ORS_API_KEY` voor online routeplanning.
3. Alleen wanneer gewenst: SMTP en het inschakelen van wachtwoordherstel. Dit blokkeert accountregistratie of login niet.

## Installatie en bestanden

De gecontroleerde debug-app staat op de telefoon. Open **VELO**. Maak een account aan of gebruik de fietscomputer zonder account. Er zijn geen technische backendinstellingen nodig.

Artefacten: `dist/velo-debug.apk` en `dist/velo-supabase.apk` (ondertekende release). Debug en release hebben verschillende ondertekeningen; installeer de passende update zonder de bestaande appgegevens te wissen. Deze telefoon gebruikt de debugvariant. De release is geschikt voor een nieuwe installatie met de eigen releasesleutel.

De gewijzigde onderdelen staan in `lib/app/`, `lib/features/`, `lib/services/accounts/`, `lib/services/integrations/`, `lib/services/gps/`, `android/`, `supabase/`, `scripts/`, `config/`, `test/`, `integration_test/`, `.github/workflows/` en deze documentatie. De oude self-hosted broncode blijft historisch bewaard; de oude stacks zijn niet bediend of verwijderd.

Zie [Supabase-beheer](SUPABASE.md) en de Git-commit voor de volledige bestandsdiff. Broncommit: `60ead98329fabe911eb9557446be483fafeef7f3` (73 gewijzigde bestanden). De volledige diff staat op https://github.com/AnecaW/VELO/commit/60ead98329fabe911eb9557446be483fafeef7f3.

Release: https://github.com/AnecaW/VELO/releases/tag/android-supabase-v2.3.0. Beide APK's en `SHA256SUMS.txt` zijn gepubliceerd. De definitieve debug-update is opnieuw op de fysieke telefoon geïnstalleerd; pakketversie 2.3.0, build 5 is op het toestel gecontroleerd. Het releasemanifest weigert cleartext HTTP en bevat geen Android HOME-intent.

SHA-256:

- `velo-supabase.apk`: `48181f6ceb33070c8595b819d4af40dc3e1125ad29da626e53f4fa59d9c29887`
- `velo-debug.apk`: `3a01f90618679cd451d85ce6cb69ddedb3abc6fa2e5a58998a43078b7088380f`

Getrackte bestanden, volledige Git-geschiedenis en beide APK's zijn gecontroleerd tegen de lokaal bewaarde private secrets. De broncommit is gepusht en de GitHub-controles voor Flutter, Supabase en de behouden backendtests zijn geslaagd. Cloudcontrole na deployment: beide functies ACTIVE, RLS 9/9, cron actief met HTTP 200 en nul resterende testaccounts.
