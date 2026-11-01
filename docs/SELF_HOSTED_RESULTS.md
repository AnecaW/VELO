# Uitvoering en resterende installatie

Uitgevoerd op 1 november 2026. De bestaande Flutter-app staat behouden in de projectroot. Het lege GitHub-project `https://github.com/AnecaW/VELO` is gevuld met de bestaande app en de nieuwe backend.

## Implementatie

- `backend/src/velo_backend/`: FastAPI, e-mailaccounts, Argon2id, access-tokens van 15 minuten, roterende refresh-tokens, intrekking, wachtwoordwijziging, accountverwijdering, rate-limits, Strava, jobs, logging, versleutelde back-ups en CLI-beheerinstallatie.
- `backend/migrations/`: transactionele SQLite WAL-migraties, inclusief bestaande accounts, refresh-tokenfamilies en eenmalige wachtwoordherstelcodes.
- `lib/services/accounts/` en `lib/features/accounts/`: veilige sessieopslag en herstel, registratie, login, accountbeheer en herkenbare verbindingsmeldingen.
- `lib/services/integrations/backend_strava.dart`: de actieve Flutter-adapter gebruikt de accountbackend; Strava-tokens blijven op de server. De bestaande synchronisatiepagina's, GPX-functies, ritregistratie en lokale opslag zijn behouden.
- `deployment/`: lokale bouwbare Compose-stack, Portainer-stack met gepubliceerde image en voorbeelden zonder secrets.
- `.github/workflows/`: backendtests/Docker-build, Flutterchecks en handmatige imagepublicatie.
- `docs/SELF_HOSTING.md` en `docs/BACKEND_API.md`: installatie, configuratie, HTTPS, API, updates en herstel.

## Gecontroleerd

- Backend: 45 tests geslaagd, inclusief registratie/login, verkeerde wachtwoorden, isolatie, refresh-rotatie en hergebruik, intrekking, migraties, healthcheck, OAuth-state/verifier/replay, verlopen staat, ingetrokken Strava-refresh-token, idempotente uploads, ontbrekende configuratie, SMTP-herstel met gemockte aflevering, back-up en herstel.
- Flutter: 125 tests geslaagd, waaronder nieuwe accountsessie- en schermtests.
- `flutter pub get`, analyse, debug-APK en release-APK lokaal uitgevoerd. Buildlogs staan lokaal als `selfhost-*.log` en worden niet gecommit. De build waarschuwt voor de bestaande workmanager Kotlin-plugin; die waarschuwing verhinderde de APK-builds niet.
- Docker-image lokaal gebouwd en beide Compose-bestanden gevalideerd.
- Lokale WSL-stack `velo-selfhost-test`: API, worker en backup healthy. Healthcheck `http://127.0.0.1:18080/healthz` gaf HTTP 200 en `{"status":"ok","version":"3.0.0"}`.
- Registratie, login, eigen account en refresh via echte HTTP-verzoeken tegen de container getest. CLI-beheerinstallatie getest met uitsluitend gegenereerde testcredentials. Twee testaccounts en schema 3 bleven na opnieuw aanmaken van de containers behouden.
- GitHub backendchecks en imagepublicatie geslaagd. Gepubliceerde image zonder registrycredentials opgehaald:
  `ghcr.io/anecaw/velo-backend@sha256:17a049230e128dc9751e45431938be815025795bc0dce7888d86e03c4c1caa2f`.
- De eerste Flutter-CI-run vond de lege iconenmap die Git niet had meegenomen. De map wordt inmiddels met een README bewaard; de nieuwe CI-run is via GitHub Actions te volgen.
- Voor commit/push zijn de index en geheimenpatronen gecontroleerd. De enige gevonden lange wachtwoord/secret-literals waren expliciete backendtestwaarden. Productie-env, databases, GPS-bestanden, back-ups, APK's, signingkeys en lokale logs zijn uitgesloten. De remote had bij aanvang geen commits om op oudere secrets te controleren.

## Nog niet op de homelabserver geïnstalleerd

Dit is geen claim van productie-deployment. Portainer is bereikbaar op HTTPS-poort 9443 en rapporteerde versie 2.39.5. De beheerserver gebruikt een zelfondertekend certificaat; er zijn geen serverwachtwoorden of API-credentials naartoe verstuurd. Alleen publieke statusmetadata werd zonder credentials gelezen.

Voor automatische deployment ontbreken nog een afzonderlijke Portainer API-key en controle van het beheercertificaat. De gebruiker is gevraagd de key buiten de repository op te slaan in `C:\Users\wanne\.codex\secrets\velo-portainer-api-key.txt` en de waargenomen SHA-256-fingerprint `6af0a3650c7540e8e1807abdc3db1906b631e2d9b36993a1be2c4e99636e1269` te bevestigen. Zonder die controle wordt de key niet naar een ongeverifieerde HTTPS-server gestuurd.

Voor Strava ontbreken Client ID, Client Secret en een werkend geregistreerd HTTPS-callbackdomein. De protocollen zijn getest met providerfixtures; er is geen echte Strava-accountkoppeling of live synchronisatie geclaimd. Strava meldt zonder configuratie correct dat koppeling niet beschikbaar is.

SMTP en e-mailverificatie blijven op expliciet verzoek ongeconfigureerd. Wachtwoordherstel toont dan een duidelijke melding. Later volstaan de SMTP-omgevingsvariabelen en een herdeployment; een databaseherinstallatie is niet nodig.

## Handmatige vervolgstappen

1. Selecteer in Portainer de environment van Docker Agent `192.168.0.150`.
2. Maak een Git-stack uit `https://github.com/AnecaW/VELO`, branch `main`, composepad `deployment/compose.portainer.yaml`.
3. Vul `VELO_IMAGE` met bovenstaande digest, genereer en bewaar `VELO_ENCRYPTION_KEYS`, en stel `VELO_PUBLIC_URL`, bindadres en poort in volgens `SELF_HOSTING.md`. Strava en SMTP mogen leeg blijven.
4. Start de stack en controleer de drie healthchecks. Voer in de API-containerconsole interactief `python -m velo_backend.cli create-admin` uit.
5. Test de LAN-healthcheck en stel het serveradres in via Meer > VELO-account. Gebruik een debugbuild voor HTTP-LAN-tests en een geldig HTTPS-domein voor releasegebruik.
6. Configureer later de Strava-app en het callbackdomein; test verbinden, synchroniseren en ontkoppelen met je eigen account.

De volledige commando's voor updates en herstel staan in `SELF_HOSTING.md`. Er staat geen productie-backend-URL vast zolang de stack en HTTPS-origin niet zijn ingericht.
