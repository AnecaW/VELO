> Historisch: dit beschrijft de vorige self-hosted installatie. De actieve app gebruikt nu [Supabase](SUPABASE.md); deze oude instructies zijn niet nodig voor gebruik.

# VELO self-hosted installatie

De Flutter-app blijft in de bestaande projectroot. `backend/` bevat FastAPI, een onderhouden SQLite-datalaag met versiegestuurde SQL-migraties, een worker en versleutelde back-ups. Een enkele API-process en worker delen een SQLite WAL-volume op lokale Docker-opslag. Gebruik geen NFS/SMB-volume en schaal deze containers niet horizontaal. Voor meerdere servers is een PostgreSQL-migratie nodig.

## Lokaal testen

1. Kopieer `deployment/.env.example` naar `deployment/.env`.
2. Genereer een Fernet-sleutel met `docker run --rm velo-backend:local python -m velo_backend.cli generate-secrets` nadat je de image hebt gebouwd: `docker build -t velo-backend:local backend`. Bewaar de sleutel in een wachtwoordmanager. De bootstrapcode uit dat commando is voor de oudere uitnodigingsflow en is niet nodig voor de aanbevolen CLI-installatie.
3. Vul `VELO_ENCRYPTION_KEYS` en je toekomstige HTTPS-origin in. Laat Strava en SMTP leeg zolang ze niet beschikbaar zijn. Voor uitsluitend LAN-debug kun je `VELO_PUBLIC_URL=https://velo.example.test` gebruiken; dit maakt nog geen werkende publieke URL of Strava-callback.
4. Zet alleen voor LAN-tests `VELO_BIND_ADDRESS=0.0.0.0`. Beperk TCP 8080 met de firewall tot je LAN. Gebruik bij echte accounts HTTPS via een reverse proxy.
5. Start vanuit de projectroot: `docker compose --env-file deployment/.env -f deployment/compose.yaml up -d --build`.
6. Maak de eerste beheerder aan met `docker compose --env-file deployment/.env -f deployment/compose.yaml exec api python -m velo_backend.cli create-admin`. Voer e-mailadres en een uniek wachtwoord interactief in. Dit commando weigert een tweede initiële beheerder. Er is geen standaardaccount of onbeveiligde beheerinstallatieroute. Nieuwe e-mailregistraties zijn pas beschikbaar na deze stap.
7. Test `/healthz` en controleer `docker compose --env-file deployment/.env -f deployment/compose.yaml ps`.
8. Open in Flutter Meer > VELO-account. Stel het serveradres in en registreer of log in. Alternatief: `flutter run --dart-define=VELO_BACKEND_URL=http://<agent-lan-adres>:8080`. Alleen debugbuilds laten HTTP toe; releasebuilds vereisen HTTPS. Een opgeslagen serveradres heeft voorrang op de buildinstelling.

## Portainer: Git-stack op de Agent

Portainer-beheer draait op `192.168.0.149`; de containers horen op de Docker-environment van Agent `192.168.0.150`. Deze adressen zijn infrastructuurgegevens, geen appdefaults. Selecteer in Portainer eerst die Agent-environment en controleer het environment-ID/adres. Kies niet zonder controle de lokale Portainer-environment.

De aanbevolen stack gebruikt een gepubliceerde image en heeft geen relatieve hostpaden nodig:

1. Push broncode naar de bestaande repository `https://github.com/AnecaW/VELO`.
2. Voer in GitHub Actions de workflow **Backend image** uit. Die publiceert `ghcr.io/anecaw/velo-backend:<commit-sha>` en `:latest`. Gebruik de SHA-tag of digest voor herhaalbare updates. Stel het package publiek in of voeg in Portainer een beperkte registry-identiteit toe met uitsluitend leesrechten voor dat package.
3. Open de juiste Agent-environment > Stacks > Add stack > Repository. Repository: bovenstaande URL, ref `refs/heads/main`, composepad `deployment/compose.portainer.yaml`.
4. Vul de variabelen uit `.env.example` in via Portainer. Zet `VELO_IMAGE` op de gepubliceerde SHA-tag. Houd de encryptiesleutel geheim; Portainerbeheerders kunnen environment variables zien. Gebruik voor strengere scheiding `_FILE`-secrets met uitsluitend leesbare Docker-secretbestanden; de backend ondersteunt `VELO_ENCRYPTION_KEYS_FILE`, `STRAVA_CLIENT_SECRET_FILE` en `SMTP_PASSWORD_FILE`. Hiervoor moet je de overeenkomstige secret-mounts in een eigen stackvariant toevoegen. Commit nooit echte secrets.
5. Kies `VELO_BIND_ADDRESS=0.0.0.0` wanneer een reverse proxy/tunnel op een andere host of container via het Agent-adres verbindt; scherm de poort af voor internet. Gebruik `127.0.0.1` bij een proxy/tunnel op dezelfde host die via hostnetwerk verbindt.
6. Deploy en controleer de drie healthchecks. Open de API-containerconsole in Portainer en voer `python -m velo_backend.cli create-admin` interactief uit. Gebruik een console met terminal voor verborgen wachtwoordinvoer.
7. Test `http://192.168.0.150:8080/healthz` uitsluitend als de LAN-bind is ingesteld. Verwacht `status: ok`. De uiteindelijke app gebruikt je HTTPS-URL.

`compose.yaml` is daarnaast geschikt voor lokale Compose-builds of een Portainer-installatie met ondersteuning voor Git-buildcontexten. `compose.portainer.yaml` werkt met de gepubliceerde image en heeft die extra ondersteuning niet nodig. Dit is een Docker Standalone Compose-stack, geen Swarm-stack.

## Beperkte Portainer-identiteit

De werkelijk gedeployde stack gebruikt `deployment/compose.portainer-restricted.yaml`, stacknaam `velo`, environment 4 op de Agent. Deze variant is nodig wanneer Portainer capability-overrides voor gewone gebruikers verbiedt. Ook het laten vallen van capabilities wordt door die Portainer-regel geweigerd. De image draait als UID 10001 en behoudt `no-new-privileges` en een alleen-lezen rootbestandssysteem. Op de server zijn nul effectieve en toegestane capabilities geverifieerd. Gebruik `compose.portainer.yaml` als de beheerpolicy capability-overrides wel toestaat.

## HTTPS en netwerk

Kies een eigen domein, bijvoorbeeld `velo.jouwdomein.be`. Stel `VELO_PUBLIC_URL=https://velo.jouwdomein.be` in. Gebruik Caddy/Nginx met een geldig publiek certificaat en DNS A/AAAA-records naar je reverse proxy; publiceer alleen 443 (en 80 voor certificaatuitgifte indien nodig). Proxy naar de interne Agent-poort. Een alternatief is een Cloudflare Tunnel met public hostname naar `http://<agent-adres>:8080`, zonder router port-forward. Laat een eventuele browser-only toegangscontrole de mobiele API en OAuth-callback niet blokkeren; VELO-authenticatie beschermt de accountendpoints.

Gebruik bij voorkeur ook op het LAN het HTTPS-domein met split DNS of tunnel. Controleer dat je proxy geen OAuth-querystrings, Authorization-headers, request bodies of resetlinks logt. De backend logt alleen methode, status en duur. Proxyheaders worden bewust niet vertrouwd; achter een proxy delen gebruikers daarom de conservatieve IP-rate-limits. Voor grotere installaties moet een expliciet vertrouwde proxyconfiguratie worden ingericht.

## Strava

Configureer `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET` en de correcte publieke HTTPS-origin. Registreer het callbackdomein bij Strava en gebruik `https://<domein>/oauth/strava/callback`. Start opnieuw na wijziging. Geen credentials worden verzonnen of in de app ingebouwd.

De app opent de officiële autorisatiepagina, de backend bewaart de gebruikersgebonden staat en wisselt de code in. Een eenmalige handoff plus telefoonverifier bevestigt de koppeling. Access- en refresh-tokens blijven versleuteld op de server. Alleen de eigen gebruiker kan deze gegevens benaderen. Nieuwe toestemming of een ander Strava-account kan opnieuw verbinden vereisen; ontkoppel eerst bij accountwissel.

Activiteitenimport, route-import en optionele eigen GPX-upload zijn afzonderlijke functies. Route-export naar Strava wordt niet aangeboden. Synchronisatie is opt-in; inkomend begint bij recente zeven dagen, met beperkte paginering en routeaantallen. De server bewaart cursors, jobstatus, retries, quota en geschiedenis. Onzekere uploads worden nooit blind herhaald. Controleer `needs_review` in de jobstatus en bij Strava voordat je handmatig opnieuw uploadt. API-gegevens zijn een afzonderlijke cache van maximaal 24 uur, worden niet in lokale fietsstatistieken of back-ups gemengd en worden bij ontkoppelen verwijderd.

## SMTP later activeren

Laat voorlopig `SMTP_HOST` en `SMTP_FROM` leeg. Registratie en login werken zonder e-mailverificatie. Wachtwoordherstel geeft dan expliciet aan dat de beheerder e-mail moet configureren.

Later stel je in Portainer `SMTP_HOST`, `SMTP_PORT` (587 met STARTTLS of 465 met SSL), `SMTP_SECURITY` (`starttls` of `ssl`), `SMTP_USERNAME`, `SMTP_PASSWORD` en `SMTP_FROM` in. Herdeploy de stack; database of code hoeft niet opnieuw aangemaakt te worden. Er is geen onversleutelde SMTP-modus. De herstelflow verzendt een eenmalige link van 30 minuten naar het accountadres. Na wijzigen worden alle sessies ingetrokken. De antwoordtekst onthult niet of het adres bestaat. Configureer SPF/DKIM/DMARC bij je mailprovider en test de aflevering met een eigen testaccount. SMTP is hier niet met een echte provider getest.

## Opslag, back-up en herstel

`data` bevat SQLite, WAL en versleutelde persoonlijke documenten/tokens. `backups` bevat dagelijks een versleutelde back-up; de laatste zeven blijven staan. Beide zijn Docker named volumes op de geselecteerde Agent-host. Verwijder volumes niet bij een update en gebruik nooit `down -v` voor productie.

De back-up bevat accounts, wachtwoordhashes, eigen documenten en upload-deduplicatiestatus. Providertokens, API-cache, sessies, herstelcodes en uitnodigingen zijn uitgesloten. Na herstel opnieuw inloggen en Strava opnieuw verbinden. De encryptiesleutel wordt apart bewaard; zonder sleutel is herstel onmogelijk. Kopieer back-ups regelmatig naar een tweede beveiligde locatie; een volume op dezelfde schijf is geen bescherming tegen schijfverlies.

Handmatige back-up: `docker compose --env-file deployment/.env -f deployment/compose.yaml exec api python -m velo_backend.cli backup --file /backups/manual.velobackup` werkt alleen als je ook het back-upvolume op die container mount. Gebruik standaard de backup-container: `... exec backup python -m velo_backend.cli backup --file /backups/manual.velobackup`.

Herstel: stop eerst API, worker en backup. Maak eerst een aparte kopie van het huidige datavolume. Plaats het gekozen bestand in het back-upvolume en voer een eenmalige backup-servicecontainer uit: `docker compose --env-file deployment/.env -f deployment/compose.yaml run --rm --no-deps backup python -m velo_backend.cli restore --file /backups/<bestand>.velobackup --confirm`. De actieve encryptiesleutelset moet de oorspronkelijke sleutel bevatten. Controleer het herstelcommando en start daarna de stack. Het herstel controleert authenticatie en integriteit voordat de database wordt vervangen en weigert bij aanwezige WAL-bestanden van een actieve database. Verwijder die nooit terwijl een proces draait.

Sleutelrotatie: maak eerst een back-up; zet de nieuwe Fernet-sleutel vooraan in `VELO_ENCRYPTION_KEYS`, gevolgd door oude sleutels gescheiden door komma's. Herdeploy en voer `python -m velo_backend.cli rotate-key` in een container uit. Bewaar oude sleutels zolang oude back-ups nodig zijn.

## Updates

Maak een back-up, publiceer een nieuwe image, wijzig `VELO_IMAGE` in Portainer naar de nieuwe SHA-tag en kies Update stack / re-pull. Migraties lopen automatisch en transactioneel bij starten. Controleer alle healthchecks en login. Zet bij problemen eerst de containers stil en herstel de bijbehorende databaseback-up met de vorige image; een oudere image begrijpt mogelijk nieuwe schema's niet. Automatische containerherstart is `unless-stopped`; Docker zelf moet als service automatisch starten op de Agent-host.
