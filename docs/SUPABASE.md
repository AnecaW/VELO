> Actuele Strava-configuratie en praktijktests: [STRAVA.md](STRAVA.md) en [STRAVA_RESULTS.md](STRAVA_RESULTS.md). De providercredentials en webhook zijn inmiddels ingesteld.

# VELO op Supabase

De actieve app gebruikt uitsluitend het beheerde Supabase-project `pdooxhljbutbsotbjbrt`, via HTTPS op `https://pdooxhljbutbsotbjbrt.supabase.co`. De normale gebruiker installeert de APK, maakt een account aan en begint. Er zijn geen servervelden, eigen domein, Docker of Portainer nodig.

## App en accounts

`supabase_flutter` is de officiële SDK. `SupabaseAccountService` sluit deze aan op de bestaande accountpagina en offline synchronisatie. Auth gebruikt e-mail/wachtwoord, sessievernieuwing, uitloggen en accountverwijdering. Registratie met naam staat aan, e-mailbevestiging is verplicht, wachtwoorden vereisen minimaal 12 tekens en access-JWT's verlopen na 15 minuten. Supabase JWT's kunnen tot hun vervaltijd geldig blijven na uitloggen; refresh-sessies worden ingetrokken. Dit is geen claim van onmiddellijke JWT-intrekking.

De SDK-sessie en PKCE-verifier staan in Android secure storage. Foreground en Workmanager verversen sessies onder dezelfde lokale databaselease. Offline uitloggen wist de lokale sessie; een intrekkingsopdracht blijft uitsluitend in secure storage totdat de verbinding terug is. Een oude intrekking gebruikt een geïsoleerde SDK-client en overschrijft geen nieuwe login.

`config/supabase.json` bevat alleen de publieke project-URL en publishable key. Een publishable key is een clientidentificatie, geen beheergeheim; beveiliging komt van Auth, RLS en server-side controles. Er staat geen service-role key, personal access token, providersecret of databasewachtwoord in de app.

## PostgreSQL en gegevensisolatie

- `velo_documents`: eigen ritten, routes, instellingen, fietsprofielen en trainingsgegevens, verliesloos opgeslagen als JSONB in het bestaande appformaat. De sleutel bestaat uit gebruiker, soort en document-ID. Revisies, tombstones en een incrementele index bewaren bestaande offline conflictafhandeling.
- `velo_tracks`: GPS-sporen apart van lichte activiteitmetadata, met eigen RLS. Incrementele synchronisatie haalt maximaal één volledig spoor per pagina op.
- `velo_profiles`: uitsluitend het eigen openbare profiel binnen het account, niet een lijst van andere gebruikers.
- `velo_jobs` en `velo_sync_history`: de eigenaar kan uitsluitend eigen taakstatus en geschiedenis lezen.
- `velo_private`: providerverbindingen, versleutelde tokens, OAuth-sessies, tijdelijke providercache en rate-limits. Deze schema is niet beschikbaar voor gewone clients.

Alle negen gebruikerstabellen hebben RLS. Directe documentmutaties door clients zijn geblokkeerd. De write-RPC bepaalt zelf `auth.uid()`, neemt nooit een gebruiker-ID van de client aan, serialiseert mutaties per gebruiker, controleert de verwachte revisie en beperkt opslag en documentgrootte. De service-only RPC voor providergegevens is niet uitvoerbaar door `anon` of `authenticated`.

Eigen opnames en providergegevens blijven gescheiden. Strava-cache verloopt na maximaal 24 uur. Synchronisatie overschrijft gewijzigde lokale versies niet stil: de app bewaart conflicten met een herstelactie. Bestaande lokale fietscomputerfuncties zijn behouden.

Oude self-hosted accounts worden niet als Supabase-accounts geïmpersoneerd. Gebruikers maken een nieuw Supabase-account aan. Als op hetzelfde toestel nog een oude veilige sessie staat met hetzelfde e-mailadres, importeert de app de bijbehorende lokale accountkopie eenmalig. Andere accountarchieven blijven gescheiden; bestaande data wordt niet verwijderd. Gegevens die uitsluitend op de oude server staan, worden niet automatisch opgehaald. De oude backendbroncode blijft behouden als historisch onderdeel en wordt niet meer gestart of door de app gebruikt.

## Edge Functions en periodiek werk

`velo-api` verifieert gebruikers server-side via Supabase Auth. Het exacte Strava OAuth-callbackpad en de niet-persoonlijke herstelbeschikbaarheidsflag zijn publiek bereikbaar; de callback gebruikt een onvoorspelbare, gehashte, vervallende en eenmalige autorisatiesessie. Handoff en PKCE-controle verbinden het resultaat aan het oorspronkelijke account. Accountverwijdering vraagt opnieuw het wachtwoord en verwijdert Auth-account en gekoppelde gegevens via foreign-key cascades.

De Strava-adapter ondersteunt activiteitimport, route-import, eigen GPX-upload, afzonderlijke voorkeuren, ontkoppelen, tokenvernieuwing, rate-limits, idempotente taken, retries en geschiedenis. Onzekere uploads vereisen controle voordat opnieuw wordt geüpload. Import is begrensd tot recente activiteiten en kleine routepagina's; er is geen onbegrensde historische import of route-export naar Strava. Provider-tokens zijn extra versleuteld met AES-GCM en aan de eigenaar gebonden. Refresh herstelt geen intussen verwijderde verbinding. Deze adapter is voorbereid, maar zonder echte providercredentials niet live gekoppeld.

`velo-worker` accepteert uitsluitend een aparte serversecret. `pg_cron` roept hem iedere minuut aan via `pg_net`; de token wordt tijdens uitvoering uit Supabase Vault gelezen. De worker verwerkt begrensde taken; automatische Strava-import wordt per account hoogstens iedere 15 minuten ingepland. De app kan handmatige synchronisatie en upload na een rit aanvragen. PostgreSQL bewaart taken over herstarts heen, herstelt verlopen leases en stopt herhaalde fouten met een herstelstatus.

Navigatie gebruikt een geauthenticeerde Edge-proxy naar OpenRouteService. De providerkey komt nooit op het toestel. Zonder key blijven opgeslagen routes en lokale navigatiefuncties beschikbaar; online routeplanning meldt dat de dienst nog niet beschikbaar is.

## Uitvoering en onderhoud

De SQL-bestanden in `supabase/migrations/` zijn daadwerkelijk toegepast en staan in de Supabase-migratiegeschiedenis. Beide Edge Functions zijn daadwerkelijk gedeployed. De cron is actief en de geplande HTTP-aanroepen zijn met status 200 gecontroleerd. De vorige Docker-imagepublicatie is uit de actieve GitHub-workflows verwijderd. Deze migratie bedient of verwijdert de oude Portainer-stacks niet.

Onderhoud vanaf de repository, zonder Docker:

```powershell
python scripts/supabase_admin.py migrate --token-file <privaat-tokenbestand>
python scripts/supabase_admin.py deploy --token-file <privaat-tokenbestand>
powershell -NoProfile -File scripts/build_android.ps1
```

De beheerclient verstuurt credentials alleen via HTTPS naar de vaste Supabase Management API en schrijft ze niet naar logs. De operator bewaart de token buiten Git. Voeg externe secrets toe via Supabase Dashboard > Edge Functions > Secrets:

- `STRAVA_CLIENT_ID` en `STRAVA_CLIENT_SECRET`, daarna de officiële Strava-appconfiguratie met callback `https://pdooxhljbutbsotbjbrt.supabase.co/functions/v1/velo-api/oauth/strava/callback` en callbackdomein `pdooxhljbutbsotbjbrt.supabase.co`.
- `ORS_API_KEY` voor online routeplanning.
- `VELO_TOKEN_ENCRYPTION_KEY` en `VELO_SCHEDULER_TOKEN` zijn al veilig aangemaakt. De encryptiesleutel mag niet zomaar worden vervangen; bewaar hem met databasebackups buiten deze machine. De lokale beveiligde kopie staat in de secrets-map van de eigenaar.

Supabase Auth heeft inmiddels eigen SMTP-configuratie. `configure-auth` controleert uitsluitend of de vereiste velden aanwezig zijn, behoudt de geheime waarden, verplicht e-mailbevestiging, stelt de toegestane callback `ultimatebike://auth/callback` in en schakelt herstel in met `VELO_PASSWORD_RESET_ENABLED=true`. Confirmation- en recovery-templates bevatten zowel de officiële `ConfirmationURL` als de officiële `Token`. Open een link op hetzelfde Android-toestel waarop de aanvraag is gedaan (PKCE), of voer de code uit de mail in VELO in wanneer je de mail op bijvoorbeeld een iPhone leest. Safari op een iPhone zonder VELO kan het Android-appadres niet openen. Een al bevestigd account kan gewoon inloggen.

Registratie vanaf de fysieke Huawei, ontvangst van de bevestigingsmail en bevestiging van het echte eigenaaraccount zijn gecontroleerd. De eigenaar heeft daarna bevestigd dat hij de herstelcode heeft ingevoerd en zijn eigen wachtwoord heeft ingesteld. De naam komt via een Auth-trigger in het eigen RLS-profiel; er is geen openbare gebruikerslijst. Mailsecrets blijven uitsluitend in Supabase Auth.

Maak databasebackups via de beschikbare Supabase-backupvoorziening of een beveiligde PostgreSQL-export, afhankelijk van het projectplan. Bewaar de AES-sleutel apart. Herstel eerst in een apart project en controleer RLS, migraties, cascadegedrag, secrets en cron voordat je de app omzet. Deze nieuwe cloudinstallatie heeft geen geclaimde externe disaster-recoverykopie.

## Controles

De oude `scripts/test_supabase_live.py`-run had 35 geslaagde controles toen autoconfirm aanstond. Het script weigert nu wegwerpregistraties met actieve mailbevestiging. Ook de oude native wegwerpaccounttest wordt op het productieproject overgeslagen. Deze historische resultaten zijn geen nieuwe SMTP-test.

De huidige tests staan in [UI_AUTH_RESULTS.md](UI_AUTH_RESULTS.md): SDK-mocks gebruiken uitsluitend lokale HTTP-fixtures; echte productiecontroles gebruiken alleen het door de eigenaar aangewezen account. RLS voor een andere identiteit is in een teruggedraaide SQL-transactie gecontroleerd zonder een extra account te maken. Deno test Edge-authenticatie, schedulerafscherming, eigenaargebonden encryptie en GPX. GitHub-CI gebruikt geen productiecredentials.

Officiële referenties: [Flutter SDK](https://supabase.com/docs/reference/dart/introduction), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [Edge-authenticatie](https://supabase.com/docs/guides/functions/auth), [Management API](https://supabase.com/docs/reference/api/introduction).

Voor de mailcode en links: [officiële OTP API](https://supabase.com/docs/reference/dart/auth-verifyotp), [mailtemplates](https://supabase.com/docs/guides/auth/auth-email-templates), [mobiele deep links](https://supabase.com/docs/guides/auth/native-mobile-deep-linking).
