> Historisch: dit beschrijft de vorige self-hosted installatie. De actieve app gebruikt nu [Supabase](SUPABASE.md); deze oude instructies zijn niet nodig voor gebruik.

# VELO: werkelijk uitgevoerde installatie

Gecontroleerd op 1 november 2026. Repository: https://github.com/AnecaW/VELO.

## Android-app

De ondertekende installatie staat in `dist/velo-lan.apk` (2.2.0, build 4). De gebruiker installeert de app, maakt een account aan en logt in. Het serveradres is vooraf ingesteld in de LAN-build; de normale interface bevat geen serveradres, API-key of OAuth-configuratie. Zonder account en tijdens netwerkuitval blijven lokale fietscomputerfuncties beschikbaar. Deze installatie werkt op het thuisnetwerk; er is op verzoek geen publiek domein ingericht.

Registratie, login, veilige sessieopslag, herstel, uitloggen, wachtwoordwijziging en accountverwijdering zijn aangesloten op de echte backend. Offline uitloggen verwijdert de lokale sessie en bewaart uitsluitend in secure storage een opdracht om de serversessie na herstel van de verbinding in te trekken. Accountgegevens, eigen ritten, routes, trainingsplannen en instellingen synchroniseren per gebruiker. Conflicterende lokale versies blijven herstelbaar. Appwissels tijdens een actieve registratie worden tegengehouden om ritten bij het juiste account te houden.

## Werkelijk gedeployed

- Portainer-stack `velo`, ID 25, environment 4 (`brunoserverdesktop`), Agent `192.168.0.150:9001`.
- Backend `http://192.168.0.150:8080`; `/healthz` antwoordt HTTP 200, `status: ok`, versie 3.1.0.
- API, worker en backup draaien met healthchecks, persistente volumes en automatisch herstartbeleid. Database-schema 4 bewaart bestaande accounts.
- Afzonderlijke onderhoudsstack `velo-maintenance`, ID 26, met gezonde updatercontainer. Deze heeft geen Docker-socket; een beperkte Portainer-identiteit en vastgepind TLS-certificaat bewaken de toegang tot uitsluitend de bedoelde stack en Agent.
- Actieve applicatierelease: `backend-f6b2b789a91dd0aa005d24e68735812014f2511e`. Ook deze laatste release is werkelijk automatisch toegepast (log `2026-11-01 13:28:07,508 INFO velo.updater automatic_update_updated`).
- De updater heeft daadwerkelijk zelfstandig een gepubliceerde backendrelease toegepast. Logbewijs: `2026-11-01 12:31:42,430 INFO velo.updater automatic_update_updated`. Updates gebruiken een gecontroleerde Git-tag en image-digest, maken vooraf een versleutelde backup en controleren de gezondheid. Mislukte updates krijgen rollback; dezelfde mislukte image wordt geblokkeerd.
- Geen server- of rootwachtwoord gebruikt. Productie-env, beperkte API-key, beheerderswachtwoord en signingkeys staan uitsluitend buiten Git. Het tijdelijke beheerderswachtwoord staat lokaal in `C:/Users/wanne/.codex/secrets/velo-admin-initial.txt`.
- Versleutelde productiebackup daadwerkelijk aangemaakt en in een geisoleerde tijdelijke map hersteld. De actieve database is daarbij niet vervangen. Sessies en providercredentials worden uit backups verwijderd.

## Uitgevoerde controles

- 140 Fluttertests geslaagd; `flutter analyze` zonder bevindingen.
- 59 backendtests geslaagd: accounts, isolatie, sessierotatie/intrekking, migraties, gegevensconflicten, OAuth-fixtures, synchronisatie, duplicaten, ontbrekende configuratie en updater/rollback.
- Echte Android-emulatortest tegen de LAN-backend geslaagd: onboarding, registratie, sessieherstel uit Android secure storage, uitloggen en opnieuw inloggen. Wegwerpaccounts achteraf verwijderd. De fysieke telefoon is niet gebruikt.
- Debug- en ondertekende release-APK gebouwd. Android-manifest van de LAN-release gecontroleerd op de expliciet toegestane LAN-HTTP-verbinding. Standaard productieconfiguratie vereist HTTPS.
- Docker-imagebouw, Compose-validatie en bestaande database-migratie gecontroleerd. GitHub bouwt en publiceert backendimages automatisch; frontend-CI controleert analyse, tests en debugbuild met JDK 21.
- Bij commits zijn getrackte bestanden gecontroleerd tegen de lokale productiesecrets. Databases, backups, GPS-data, `.env`, keystores en buildartefacten zijn uitgesloten.

## Bewust nog niet actief

Strava mist echte Client ID, Client Secret en een geregistreerde bereikbare callback. De backendadapter en fout-/refresh-/synchronisatiepaden zijn getest met providerfixtures; er is geen live Strava-koppeling of echte import geclaimd. De app toont de koppeling als niet beschikbaar. Andere diensten zijn informatief, niet als werkende integratie gepresenteerd.

SMTP en e-mailverificatie blijven op verzoek uit. Wachtwoordherstel toont een duidelijke melding. Later toevoegen via Portainer-variabelen vereist geen code- of databaseherinstallatie. OpenRouteService mist een servercredential; de app vraagt geen persoonlijke sleutel en meldt routeplanning zonder configuratie als niet beschikbaar.

Er is geen publiek HTTPS-domein of bereikbaarheid buiten het LAN. HTTP is uitsluitend toegestaan in deze expliciete interne LAN-build, niet als publieke productiestandaard.

## Wat de eigenaar nog doet

1. Installeer `dist/velo-lan.apk` op Android en gebruik het thuisnetwerk. Maak een account aan of gebruik het reeds aangemaakte beheerdersaccount; wijzig diens tijdelijke wachtwoord in de app.
2. Bewaar encryptiesleutel en backups op een tweede beveiligde locatie. Deze hostvolumes zijn geen externe disaster-recoverykopie.
3. Alleen wanneer gewenst: voeg providercredentials, SMTP en later een domein met HTTPS toe. Tot dan blijven deze onderdelen eerlijk uitgeschakeld.

Normale appgebruikers hoeven Docker, Portainer, IP-adressen of secrets niet te configureren. Zie `READY_TO_USE.md` voor onderhoud en `SELF_HOSTING.md` voor herstel.

APK SHA-256: `a478df876e6f0c1222bd05daaad06f07350b6c495871e2c0330aa8eaafb0ae73`. Download: https://github.com/AnecaW/VELO/releases/tag/android-lan-v2.2.0.
