# VELO en Strava

De actieve integratie gebruikt Supabase Edge Functions en de officiële Strava API. De Android-app bevat geen Client Secret of Strava-access-/refresh-token. VELO behoudt de bestaande OLED-interface en lokale fietscomputer.

## Gebruiken

Open Instellingen → Verbonden diensten → Strava. Kies **Verbinden met Strava**, geef toestemming bij Strava en keer automatisch terug naar VELO. Het officiële mobiele OAuth-adres wordt in de Strava-app of externe browser geopend, zonder login-webview. Profiel, verleende rechten, laatste synchronisatie en aantallen verschijnen op de accountpagina.

Recente activiteiten staan onder **Activiteiten en routes bekijken**, met herkomst Strava, sporttype, starttijd, afstand, bewegingsduur, verstreken tijd, snelheden, hoogtemeters en eventueel het aangeleverde kaartspoor. **View on Strava** verwijst naar de oorspronkelijke activiteit. Providergegevens blijven gescheiden van lokale ritstatistieken en trainingen.

Een eigen opgeslagen rit heeft een uploadknop op de samenvatting en in de Strava-pagina. Een bruikbaar GPS-spoor met oplopende tijdstempels is vereist. Automatisch uploaden staat standaard uit en vraagt een expliciete keuze. Deze instelling geldt voor nieuwe ritten na het opslaan; bestaande ritten worden niet ineens geüpload.

Een upload is pas voltooid wanneer Strava een activiteit-ID teruggeeft. VELO bewaart de upload-ID en toont verwerkingsstatus. Een verwijderde Strava-activiteit wordt niet automatisch opnieuw aangemaakt. Bij een onzekere uitkomst is controle door de gebruiker nodig voordat een nieuwe poging wordt toegestaan.

## Werkelijke configuratie

De huidige installatie is geconfigureerd. Het callbackdomein in de Strava Developer-app is `pdooxhljbutbsotbjbrt.supabase.co`. De HTTPS-callback is:

`https://pdooxhljbutbsotbjbrt.supabase.co/functions/v1/velo-api/oauth/strava/callback`

De webhook is geregistreerd op:

`https://pdooxhljbutbsotbjbrt.supabase.co/functions/v1/velo-webhook`

Serversecrets in Supabase:

- `STRAVA_CLIENT_ID` en `STRAVA_CLIENT_SECRET`.
- `STRAVA_TOKEN_ENCRYPTION_KEY`: dezelfde bestaande AES-sleutel is behouden; er is geen blinde sleutelrotatie uitgevoerd. De oude naam `VELO_TOKEN_ENCRYPTION_KEY` blijft als compatibele fallback ondersteund.
- `STRAVA_WEBHOOK_VERIFY_TOKEN` en `STRAVA_WEBHOOK_SUBSCRIPTION_ID`.
- De bestaande Supabase service-role key en `VELO_SCHEDULER_TOKEN` blijven uitsluitend backendconfiguratie.

De beheerbestanden staan buiten Git in de persoonlijke secrets-map. Beveilig en back-up zowel de Strava-credentials als de encryptiesleutel. Zonder de juiste encryptiesleutel kunnen opgeslagen koppelingen na herstel niet worden ontsleuteld. Vervang die sleutel alleen met een gecontroleerde herencryptieprocedure of expliciete nieuwe autorisatie.

Voor een eigen herinstallatie, zonder Docker:

```powershell
python scripts/supabase_admin.py migrate --token-file <privaat-supabase-tokenbestand>
python scripts/configure_strava.py --token-file <privaat-supabase-tokenbestand> --credentials-file <privaat-strava-env-bestand> --server-secrets-file <bestaande-private-server-env-back-up>
```

Het credentials-bestand bevat `STRAVA_CLIENT_ID` en `STRAVA_CLIENT_SECRET`. Gebruik [supabase/.env.example](../supabase/.env.example) uitsluitend als veldlijst; plaats echte waarden nooit in de repository. Het script bewaart de bestaande encryptiesleutel, maakt een afzonderlijk webhook-verificatietoken aan, deployt de functies en registreert de webhook. Een bestaande webhook die naar een andere toepassing wijst wordt niet automatisch vervangen. Strava staat één webhookabonnement per Developer-app toe.

## Backend en gegevens

De bestaande `velo_private.connections`, OAuth-sessies, provider-cache en `velo_jobs` zijn uitgebreid. Er is geen tweede integratiedatabase gemaakt. De migraties voegen autorisatie-staging, refresh-leases met generatiecontrole, hervatbare paginavensters, webhooktaken, verwerkingstijdstempels en minimale eigen uploadontvangstbewijzen toe.

`velo-api` verifieert het Supabase-account en gebruikt altijd de serverbepaalde eigenaar. OAuth-state is cryptografisch willekeurig en wordt gehasht, eenmalig verbruikt en na tien minuten ongeldig. De nieuw uitgegeven provider-tokens blijven eerst versleuteld in de autorisatiesessie. Alleen de juiste VELO-gebruiker met het juiste handoff-bewijs en de verifier kan de koppeling definitief maken.

Tokens gebruiken AES-GCM met de eigenaar als aanvullende authenticatiegegevens. De private tabellen en service-RPC's zijn niet leesbaar/uitvoerbaar door gewone clients. Alle persoonlijke wachtrij- en historiegegevens behouden hun eigenaargebonden RLS. Status- en foutlogs bevatten gecontroleerde codes en HTTP-statussen, geen providerresponses, tokens, secrets of GPS-sporen.

`velo-worker` draait via de bestaande lichte Supabase Cron. Dezelfde wachtrij kan na netwerk- of procesuitval hervatten. Een lease voorkomt gelijktijdige verwerking voor dezelfde eigenaar. Refresh-operaties bewaren altijd de nieuwste ontvangen access- én refresh-token. Een oude refresh kan een opnieuw gekoppeld account niet overschrijven of ontkoppelen.

De import gebruikt een begrensd, vast tijdvenster en maximaal twee pagina's van vijftig activiteiten per verwerking. De volgende pagina wordt persistent vastgelegd. De cursor gaat pas vooruit nadat het hele venster verwerkt is. De standaardperiode is dertig dagen; 7, 30, 90 of 365 dagen zijn bewust te kiezen. Cachegegevens verlopen binnen 24 uur; kopiëren uit de cloud verlengt de oorspronkelijke vervaldatum niet opnieuw. Het bijwerken van de cache verbreekt een nog geldige geselecteerde Strava-route niet.

Een handmatige upload is onafhankelijk van de automatische-uploadinstelling. De lokale outbox is aan het VELO-account gebonden. De server gebruikt één unieke uploadtaak per gebruiker en rit en een stabiele `external_id` afgeleid van die identiteit en rit-ID. Een vooraf opgeslagen verzendintentie beschermt het geval waarin Strava de upload aanvaardt maar het antwoord verloren gaat. Het bestand bevat uitsluitend echte opgeslagen trackpoints, segmentgrenzen en tijdstempels. Polling gebeurt na minimaal dertig seconden, niet continu.

`velo-webhook` bevestigt de challenge alleen met het serversecret en verwerkt alleen het geregistreerde subscription-ID. Een event wordt eerst duurzaam en idempotent ingepland; bij een opslagfout krijgt Strava een foutstatus om opnieuw te proberen. Providerwerk gebeurt daarna buiten de ontvangstrespons. Strava ondertekent deze events niet: een intrekking wordt daarom ook bij Strava gecontroleerd voordat geldige toestemming wordt vernietigd. Verwijderde/privé gemaakte activiteiten verdwijnen uit de cache. Bij ontkoppelen verdwijnen providerdata en tokens; alleen een eigen minimaal uploadontvangstbewijs blijft behouden om dubbele verzending te voorkomen. Eigen VELO-GPS-ritten worden door deze provideracties niet verwijderd.

## Rechten en limieten

De basisflow vraagt `read`, `activity:read` en `activity:write`, voor profiel, import en handmatig uploaden. Alleen de expliciete optie voor privéactiviteiten vraagt `activity:read_all`. VELO controleert de daadwerkelijk teruggegeven scopes en schakelt ontbrekende mogelijkheden uit met een actie om opnieuw toestemming te geven.

De integratie werkt met het eigen account in Single Player Mode en vraagt geen hogere athlete capacity. De server begrenst verzoeken, verwerkt de actuele rate-limitheaders en respecteert back-off. Webhooks verwerken wijzigingen; de aanvullende cloudcontrole draait hooguit om de zes uur wanneer automatische synchronisatie is ingeschakeld.

Officiële referenties: [authenticatie en Android OAuth](https://developers.strava.com/docs/authentication/), [uploads](https://developers.strava.com/docs/uploads/), [webhooks](https://developers.strava.com/docs/webhooks/), [limieten en Single Player Mode](https://developers.strava.com/docs/rate-limits/), [merkrichtlijnen](https://developers.strava.com/guidelines/), [API Agreement](https://www.strava.com/legal/api).

De werkelijk uitgevoerde controles en grenzen staan in [STRAVA_RESULTS.md](STRAVA_RESULTS.md).
