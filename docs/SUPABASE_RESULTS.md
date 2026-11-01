> Historisch verslag van versie 2.3.0. SMTP en e-mailbevestiging zijn nadien ingeschakeld; de actuele UI- en mailresultaten staan in [UI_AUTH_RESULTS.md](UI_AUTH_RESULTS.md).

# Supabase-uitvoering — 1 november 2026

Project `pdooxhljbutbsotbjbrt` (VELO), status `ACTIVE_HEALTHY`. De app gebruikt de officiële Flutter SDK rechtstreeks via HTTPS. Er is geen eigen domein of lokale backendverbinding nodig.

## Werkelijk uitgevoerd

- Auth geconfigureerd: e-mailregistratie en login aan, directe sessie zonder mailbevestiging, minimaal 12 tekens, access-JWT van 15 minuten.
- Acht versioneerde SQL-migraties toegepast en geregistreerd: gegevens/RLS, veilige conflicten en mutaties, servercron, begrensde routeverwerking.
- Alle negen app-/providertabellen gecontroleerd op actieve RLS. Private schema en server-RPC zijn niet toegankelijk voor gewone gebruikers.
- Edge Functions `velo-api` en `velo-worker` gedeployed en actief. Encryptie- en schedulersecrets server-side ingesteld; beveiligde sleutelkopie uitsluitend buiten Git.
- Cron actief; geplande HTTP-aanroepen en een geautoriseerde workeroproep geven HTTP 200.
- De app, achtergrondtaken en buildconfiguratie omgezet naar Supabase. De vorige backend-imagepublicatie verwijderd. De oude lokale stacks zijn niet bediend of verwijderd.
- Lokale functies behouden; veilige lokale accountarchieven, conflictafhandeling en eenmalige import van de nog aangemelde oude identiteit blijven beschikbaar.

## Controles

- **35 live controles geslaagd** tegen dit Supabase-project, met twee tijdelijke gebruikers. Inclusief registratie, login, fout wachtwoord, eigen data, cross-account RLS, anonieme toegang, spoofed eigenaar, afgeschermde provider-RPC, revisieconflicten, tombstones, Edge-authenticatie, ontbrekende configuratie, refresh, uitloggen en echte accountverwijdering. Accounts zijn opgeruimd.
- **148 Fluttertests geslaagd**, inclusief officiële SDK-adapter, secure storage, gegevenssynchronisatie, lokale functies en legacy-archiefimport.
- `flutter analyze`: geen bevindingen.
- **7 Deno-beveiligingstests geslaagd** en beide Edge Functions slagen voor typecontrole.
- **Echte Android-emulatortest geslaagd**: onboarding zonder serverinstellingen, Supabase-registratie, directe toegang, sessieherstel, uitloggen, opnieuw inloggen en synchronisatie. Het testaccount is verwijderd. De fysieke telefoon is niet bediend.
- Debug-APK gebouwd voor de Androidtest. De ondertekende release staat na de releasebouw in `dist/velo-supabase.apk`.

## Nog externe configuratie

Strava Client ID/Secret en officiële providerconfiguratie ontbreken; live Strava is niet getest of geclaimd. OpenRouteService mist een key. Eigen SMTP ontbreekt; wachtwoordherstel blijft expliciet uitgeschakeld en mailaflevering is niet geclaimd. Registratie/login vereisen deze externe diensten niet.

Er is geen volledige migratie van oude serveraccounts of uitsluitend daar opgeslagen data geclaimd. De oorspronkelijke broncode en lokale accountarchieven blijven bewaard. Nieuwe gebruikers maken een Supabase-account aan; de app hoeft geen infrastructuurinstellingen te tonen.

Installatie en beheer staan in [SUPABASE.md](SUPABASE.md). Download: [Android Supabase 2.3.0](https://github.com/AnecaW/VELO/releases/tag/android-supabase-v2.3.0).
