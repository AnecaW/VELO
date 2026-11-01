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
- GitHub Flutter-CI is nu ook volledig geslaagd: analyse, tests en debug-APK-build op Linux met JDK 21. Run: https://github.com/AnecaW/VELO/actions/runs/41301644118. De eerdere ontbrekende iconenmap en Java-versie zijn hersteld.
- Voor commit/push zijn de index en geheimenpatronen gecontroleerd. De enige gevonden lange wachtwoord/secret-literals waren expliciete backendtestwaarden. Productie-env, databases, GPS-bestanden, back-ups, APK's, signingkeys en lokale logs zijn uitgesloten. De remote had bij aanvang geen commits om op oudere secrets te controleren.

## Werkelijk gedeployed op de homelabserver

Op 1 november 2026 is via de afzonderlijke Portainer API-key en het door de gebruiker bevestigde, vastgepinde TLS-certificaat de Git-stack `velo` aangemaakt. Stack-ID: **25**; environment-ID: **4**, naam `brunoserverdesktop`, Agent `192.168.0.150:9001`. Er zijn geen gewone server- of rootwachtwoorden gebruikt.

De stack gebruikt `deployment/compose.portainer-restricted.yaml` uit dezelfde GitHub-repository en de hierboven vermelde gepubliceerde image-digest. Portainer blokkeert capability-overrides voor deze beperkte identiteit, zelfs `cap_drop: ALL`. De variant behoudt de niet-root imagegebruiker, het alleen-lezen rootbestandssysteem en `no-new-privileges`. Runtime gecontroleerd: UID 10001, `CapPrm=0`, `CapEff=0`, `NoNewPrivs=1`.

- `velo-api-1`, `velo-worker-1` en `velo-backup-1`: running en healthy.
- LAN-backend: `http://192.168.0.150:8080`.
- Healthcheck: `http://192.168.0.150:8080/healthz`, HTTP 200, `status: ok`, versie 3.0.0.
- Named volumes: `velo_data` en `velo_backups`, op de Agent-host.
- Herstartbeleid: `unless-stopped` voor alle drie containers.
- Eerste beheerder via het CLI-installatieproces aangemaakt met het door de gebruiker opgegeven e-mailadres en een willekeurig gegenereerd wachtwoord. Dat wachtwoord is uitsluitend opgeslagen in `C:\Users\wanne\.codex\secrets\velo-admin-initial.txt`; de productie-encryptiesleutel en variabelen staan uitsluitend buiten Git in `C:\Users\wanne\.codex\secrets\velo-production.env`. Beide bestanden hebben toegangsrechten voor de huidige Windows-gebruiker.
- Echte LAN-verzoeken getest voor registratie, login, fout wachtwoord, gegevensisolatie, refresh-rotatie, uitloggen, intrekking en ontbrekende SMTP/Strava-configuratie. De twee wegwerpaccounts en hun testgegevens zijn nadien verwijderd.
- Alle drie containers herstart. Daarna beheerderlogin, schema 3 en persistentie gecontroleerd. Alleen het beheerdersaccount bleef aanwezig.
- Een versleutelde back-up na installatie is daadwerkelijk aangemaakt: `/backups/velo-after-install.velobackup`, 224382 bytes. Die echte back-up is succesvol hersteld in een geisoleerde tijdelijke map, met controle van het beheerdersaccount en afwezigheid van sessies. De actieve database is niet vervangen. Dagelijkse back-ups staan daarnaast aan.

Er is nog geen publieke HTTPS-origin ingericht. `VELO_PUBLIC_URL=https://velo.example.test` is voorlopig uitsluitend een configuratieplaceholder, geen werkende publieke URL. LAN-toegang via HTTP is bedoeld voor de debug-app. Releasegebruik en Strava-callbacks vereisen een geldig HTTPS-domein.

Voor Strava ontbreken Client ID, Client Secret en een werkend geregistreerd HTTPS-callbackdomein. De protocollen zijn getest met providerfixtures; er is geen echte Strava-accountkoppeling of live synchronisatie geclaimd. Strava meldt zonder configuratie correct dat koppeling niet beschikbaar is.

SMTP en e-mailverificatie blijven op expliciet verzoek ongeconfigureerd. Wachtwoordherstel toont dan een duidelijke melding. Later volstaan de SMTP-omgevingsvariabelen en een herdeployment; een databaseherinstallatie is niet nodig.

## Vervolgstappen voor de gebruiker

1. Installeer desgewenst de lokaal gebouwde LAN-debug-APK `dist/velo-lan-debug.apk`; daarin is uitsluitend de backend-URL via `--dart-define` ingesteld, zonder secrets. Lees het tijdelijke beheerderswachtwoord uit het bovengenoemde lokale bestand. Stel in de debug-app via Meer > VELO-account het serveradres `http://192.168.0.150:8080` in en log in met het opgegeven e-mailadres. Wijzig het tijdelijke wachtwoord via de accountpagina.
2. Bewaar de productie-encryptiesleutel en back-ups ook op een tweede beveiligde locatie. Zonder de sleutel zijn de versleutelde gegevens en back-ups niet herstelbaar.
3. Configureer een geldig HTTPS-domein met reverse proxy of tunnel, wijzig `VELO_PUBLIC_URL` in Portainer en herdeploy. Gebruik die HTTPS-URL in de release-app.
4. Configureer desgewenst Strava Client ID, Client Secret en het geregistreerde callbackdomein. SMTP blijft uitgeschakeld tot je de SMTP-variabelen invult.

De volledige commando's voor updates en herstel staan in `SELF_HOSTING.md`. GitHub Flutter-CI gebruikt nu JDK 21 omdat de bestaande MapLibre-plugin Java source level 21 vereist. De lokale Android-builds gebruikten al een geschikte JDK.
