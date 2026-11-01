# VELO

Android-fietscomputer met ritregistratie, offline kaarten, sensoren, navigatie, training en een persoonlijk Supabase-account.

## Gebruiken

1. Download de [Supabase-versie voor Android](https://github.com/AnecaW/VELO/releases/tag/android-supabase-v2.3.0) en installeer `velo-supabase.apk`.
2. Maak een nieuw VELO-account aan of log in met je Supabase-account.
3. Begin met fietsen. Eigen ritten, routes, profielen, trainingsplannen en instellingen synchroniseren automatisch.

Je hoeft geen serveradres, poort of sleutel in te voeren. De app gebruikt rechtstreeks HTTPS naar het beheerde Supabase-project en werkt ook buiten het thuisnetwerk. Lokale fietscomputerfuncties en offline gegevens blijven beschikbaar bij verbindingsverlies en zonder account.

## Actieve architectuur

- Flutter met de officiële `supabase_flutter` SDK, Android secure storage en bestaande lokale Drift/SQLite-opslag.
- Supabase Auth voor registratie met directe toegang, login, sessieherstel, wachtwoordbeheer en uitloggen.
- PostgreSQL met RLS op alle gebruikerstabellen, accountisolatie, revisiecontrole en incrementele synchronisatie.
- Edge Functions voor serversecrets, providerintegraties, navigatieproxy en accountverwijdering.
- Supabase Cron/Vault voor periodiek werk. Geen eigen server, Docker, Portainer of eigen domein nodig.

Strava is voorbereid maar mist echte providercredentials. Online routeplanning mist een OpenRouteService-key. Deze diensten worden niet als werkend gepresenteerd. Eigen SMTP is nog niet ingesteld; succesvolle mailaflevering wordt niet geclaimd.

## Project

- `lib/`, `android/`, `ios/`, `test/`: bestaande Flutter-app en SDK-integratie.
- `supabase/migrations/`: werkelijk toegepaste PostgreSQL-migraties en RLS.
- `supabase/functions/`: gedeployde Edge Functions en beveiligingstests.
- `config/supabase.json`: uitsluitend publieke projectconfiguratie, geen beheergeheimen.
- `scripts/supabase_admin.py`: migraties/deployment via Supabase Management API, zonder Docker.
- `scripts/test_supabase_live.py`: echte account-, database- en isolatietests met opruiming.
- `backend/` en `deployment/`: historische self-hosted broncode, behouden voor referentie. De actieve app gebruikt deze niet en de Docker-imagepublicatieworkflow is verwijderd.

## Bouwen en controleren

```powershell
flutter pub get
flutter analyze
flutter test
powershell -NoProfile -File scripts/build_android.ps1
npx -y deno test --allow-env supabase/functions/security_test.ts
```

De ondertekende release komt in `dist/velo-supabase.apk`. Voor lokale releasebouw is de bestaande private Android-signingconfiguratie nodig. CI gebruikt geen productiecredentials.

Zie [het volledige afwerkings- en toestelrapport](docs/PRODUCTION_READY_REPORT.md), [Supabase-installatie en onderhoud](docs/SUPABASE.md) en [de cloudresultaten](docs/SUPABASE_RESULTS.md). Historische self-hostingdocumentatie beschrijft de vorige installatie en is niet de huidige gebruiksaanwijzing.

Service-role keys, personal access tokens, providersecrets, productiedata, signingkeys en backups horen nooit in de app of Git.
