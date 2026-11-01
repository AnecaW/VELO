# VELO

VELO is een Android-fietscomputer met ritregistratie, navigatie, offline kaarten, sensoren, training en een persoonlijk account.

## Gebruiken

1. Installeer de aangeleverde VELO-app.
2. Open VELO en maak een account aan of meld je aan.
3. Begin met fietsen. Je eigen ritten, routes, profielen, trainingsgegevens en instellingen worden automatisch bij je account bewaard.
4. Open optioneel **Verbonden apps** om Strava te koppelen wanneer deze dienst beschikbaar is.

De app vraagt nooit om een serveradres, poort, API-sleutel of OAuth-instellingen. Bij verbindingsverlies blijven je lokale fietscomputer en opgeslagen gegevens beschikbaar. Je wijzigingen worden opnieuw geprobeerd zodra er verbinding is. Je kunt ook zonder account verder fietsen.

**Huidige distributie:** op verzoek van de eigenaar uitsluitend op het thuisnetwerk. De vaste verbinding zit in de interne buildconfiguratie. Een publieke HTTPS-versie is nog niet ingericht. SMTP-herstel en live Strava blijven uitgeschakeld zolang de benodigde externe configuratie ontbreekt; de app toont dat eerlijk.

## Accounts en gegevens

- E-mailregistratie, login, veilig sessieherstel, wachtwoordwijziging en accountverwijdering.
- Korte access-tokens en eenmalig roterende refresh-tokens, opgeslagen in Android secure storage.
- Automatische synchronisatie na wijzigingen, bij terugkeer in de app, netwerkherstel en achtergrondwerk.
- Offline wijzigingen blijven op het toestel; wijzigingen van meerdere toestellen krijgen revisiecontrole. Bij een conflict worden beide versies bewaard en kun je een versie terugzetten.
- Accounts op hetzelfde toestel hebben gescheiden lokale gegevens. Uitloggen wist de actieve weergave, maar behoudt een herstelbare accountkopie.
- Strava-gegevens blijven een afzonderlijke tijdelijke cache. Ze worden niet als eigen opnames opnieuw geupload of in persoonlijke back-ups gemengd.

## Project

- `lib/`, `android/`, `ios/`, `test/`: de bestaande Flutter-app.
- `backend/`: FastAPI, SQLite WAL, versiegestuurde migraties, authenticatie, synchronisatie, Strava en back-ups.
- `config/`: interne verbindingsinstellingen voor builds, zonder geheimen.
- `deployment/`: Portainer-stacks voor de applicatie en de lichte automatische updatecontrole.
- `.github/workflows/`: tests, Android-builds, imagepublicatie en immutable backend-releases.
- `docs/`: installatie, beveiliging, API en werkelijk gemeten deploymentresultaten.

## Onderhoud voor de eigenaar

De gewone appgebruiker hoeft niets technisch in te stellen. Eigenaar- en ontwikkelaarsinformatie staat apart:

- [Installatie, HTTPS, updates en herstel](docs/SELF_HOSTING.md)
- [Gebruiksklare LAN-versie en automatische updates](docs/READY_TO_USE.md)
- [API en gegevensisolatie](docs/BACKEND_API.md)
- [Werkelijke deploymentresultaten](docs/SELF_HOSTED_RESULTS.md)

Productie-env, keys, tokens, databases, persoonlijke GPS-bestanden, backups en signingkeys worden niet in Git opgenomen.
