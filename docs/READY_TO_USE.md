# VELO: intern beheerde verbinding en automatische updates

Dit document is voor de eigenaar/ontwikkelaar, niet voor gewone gebruikers. De normale Android-interface bevat geen backend-URL, Client ID, client secret, API-key of installatie-instructies.

## Netwerkkeuze

De eigenaar heeft op 1 november 2026 expliciet gekozen voor uitsluitend lokale adressen. `config/lan.json` is de interne buildconfiguratie. De app gebruikt die vaste origin; eerder opgeslagen, door gebruikers ingevulde URL's kunnen de app niet omleiden. Sessiecredentials worden nooit naar een afwijkende origin overgenomen.

De LAN-build staat HTTP uitsluitend expliciet toe voor private IPv4-adressen. Android krijgt daarvoor alleen in deze build toestemming voor cleartext-verkeer. Deze testdistributie is geen publieke HTTPS-productieversie. Een normale productiebuild gebruikt HTTPS en heeft LAN-modus uitgeschakeld. Productie- en beheerwachtwoorden of API-secrets worden nooit ingebouwd.

Bouw de lokaal ondertekende LAN-APK met `./scripts/build_android.ps1 -Mode lan`. Uitvoer: `dist/velo-lan.apk`. Voor productie wordt een echte HTTPS-origin in `config/production.json` ingericht en `-Mode production` gebruikt; het script weigert voorbeeldhosts, onveilige origins en LAN-modus. De signingkey blijft uitsluitend lokaal.

## Normale gebruikersflow

Bij openen wordt de sessie veilig hersteld. Zonder sessie verschijnt de eenvoudige accountpagina. Aanmelden schakelt onmiddellijk door naar de fietscomputer; verder zonder account blijft mogelijk. Bij een onbereikbare dienst blijven lokale ritregistratie en kaarten toegankelijk. Wachtwoordherstel toont een normale beschikbaarheidsmelding zolang SMTP ontbreekt.

Ritten, eigen/GPX-routes, activiteitprofielen, trainingsplannen, trainingsprofiel, trainingsresultaten en overdraagbare instellingen worden automatisch gesynchroniseerd. Lokale kaartbestanden, secrets en Strava-cache worden niet meegenomen. Accountwissels archiveren de gegevens van de vorige gebruiker voordat de volgende gebruiker gegevens ziet. Verwijderingen worden via tombstones doorgegeven; verouderde writes en deletes worden geweigerd. Bij conflicten wordt de lokale versie apart bewaard en kan de gebruiker die terugzetten.

## Strava en routeplanning

Strava heeft uitsluitend een normale verbindknop als de backend aangeeft dat de dienst beschikbaar is. De officiele OAuth-flow en gebruikersgebonden tokens blijven op de backend. Na koppelen wordt automatische import ingeschakeld; uitgaand delen van eigen GPS-ritten vereist de afzonderlijke toestemming van de gebruiker. Niet-geimplementeerde diensten worden als niet beschikbaar getoond, zonder nepverbinding.

Live Strava vereist nog geregistreerde credentials en een passende bereikbare HTTPS-callback. De eigenaar heeft nog geen publiek domein beschikbaar gesteld; die live koppeling wordt daarom niet geclaimd.

Het vroegere persoonlijke openrouteservice-sleutelveld is verwijderd. Zoek- en routeverzoeken gebruiken nu de beveiligde backendproxy met een uitsluitend server-side `ORS_API_KEY` (of `ORS_API_KEY_FILE`). Zonder die externe configuratie meldt routeplanning dat zij tijdelijk niet beschikbaar is. Opgeslagen GPX-begeleiding blijft werken. Er worden geen credentials verzonnen of openbare demoservices als productieprovider gebruikt.

## Automatische releases zonder Portainer-key in GitHub

Een wijziging aan backend/deployment op `main` start de backendreleaseworkflow:

1. Backendtests en Docker-build.
2. Publicatie van een SHA-image en een immutable image-digest in GHCR.
3. GitHub-release `backend-<commit-sha>` met `velo-backend-release.json`. Dit bevat uitsluitend image-digest en broncommit, geen secrets.

Een afzonderlijke lichte Python-updater op de Agent controleert standaard iedere tien minuten die publieke releases. De updater heeft geen Docker-socket en geen appdatavolume. Hij gebruikt de beperkte Portainer-identiteit uitsluitend op het LAN en verifieert de bevestigde certificaatfingerprint voordat de key wordt verstuurd. De key blijft op de homelabserver en in de lokale secrets-map, nooit in GitHub.

Voor iedere wijziging controleert hij de exacte Agent-URL, environment-ID, stack-ID/naam en repository. Hij maakt met de huidige backup-service eerst een versleutelde back-up. Vervolgens wordt de Git-stack vanaf de geteste releasetag bijgewerkt met de immutable image-digest. Volumes worden niet verwijderd (`Prune=false`). De drie applicatieservices moeten gezond worden en werkelijk de nieuwe image draaien. Een ongezonde release wordt teruggezet naar de vorige image/Git-ref en geblokkeerd tot een andere release verschijnt. Een onderbroken update wordt via niet-gevoelige statusmetadata hervat.

De updater blijft bewust op een apart geteste image draaien zodat hij de applicatie kan terugzetten. Hij heeft alleen een eigen klein statusvolume. Database-migraties voor automatische releases moeten additief/backwards compatible blijven; een rollback draait geen destructieve schemawijziging terug. De voor-updateback-up blijft het herstelpunt voor de eigenaar.

Configuratie staat in `deployment/compose.updater.yaml` en `.env.updater.example`. De eigenaar hoeft geen bestanden te bewerken bij normaal gebruik: deze omgeving wordt via de beschikbare Portainer-API ingericht. De updater logt alleen uitkomsten, zonder keys, request bodies of tokens.
