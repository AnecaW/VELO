# VELO 2.5.0 — Strava-resultaten

Datum: 1 november 2026. Dit verslag beschrijft de echte integratie met het eigen Strava-account, naast geïsoleerde tests.

## Oorspronkelijke oorzaak

`STRAVA_CLIENT_ID` en `STRAVA_CLIENT_SECRET` ontbraken in Supabase. De Flutter-pagina verving de concrete configuratiestatus door een generieke beschikbaarheidsmelding. De bestaande encryptie en gedeeltelijke OAuth-/uploadinfrastructuur zijn hergebruikt. Daarnaast veroorzaakte de oude statuspagina te veel herhaalde API-aanvragen; status, uploadtaken en historie zijn nu gecombineerd, kort gecachet en samengevoegd bij gelijktijdige aanvragen.

## Uitgevoerd

- Officiële mobiele OAuth in de externe browser/Strava-app, willekeurige state, eenmalige callback en eigenaargebonden handoff. Profiel en daadwerkelijk verleende scopes worden gecontroleerd.
- Serversecrets en webhook ingesteld op het bestaande Supabase-project; de bestaande encryptiesleutel is behouden.
- Bestaande Edge Functions `velo-api` en `velo-worker` uitgebreid; `velo-webhook` toegevoegd en daadwerkelijk geregistreerd bij Strava.
- Vier PostgreSQL-migraties daadwerkelijk toegepast: `20261101194000`, `20261101195000`, `20261101195500`, `20261101200000`. Bestaande tabellen zijn uitgebreid, met private OAuth-staging, leases/generatiecontrole, paginavensters, cacheverval en veilige ontkoppel-/ontvangstbewijsfuncties.
- Hervatbare activiteitimport, echte activiteitdetails/kaartgegevens, bronmarkering en originele Strava-link. Providerdata blijven apart van lokale ritstatistieken.
- Handmatige upload op de ritpagina en in instellingen; optioneel automatisch na opslaan; een eigenaargebonden lokale outbox; stabiele externe identiteit; persistent upload-ID en definitieve activiteitstatus; veilige retry en bescherming tegen duplicaten.
- Statussen voor ontbrekende configuratie, verbinden, verbonden, synchronisatie en fouten. De bestaande VELO-stijl en overige functies zijn behouden.

## Echte cloud- en toestelcontroles

1. De eigenaar gaf op de Huawei toestemming op de officiële Strava-pagina en bevestigde de automatische terugkeer naar VELO. De backend bevestigde een actieve verbinding met opgeslagen athlete-ID, profiel/foto, geldige versleutelde tokens en de werkelijk toegekende scopes `read`, `activity:read`, `activity:write`.
2. **8 echte Strava-activiteiten** zijn geïmporteerd. De lijst en bronmarkering zijn op de Huawei bekeken. De detailtest vond een fout met een verdwijnende widgetcontext tijdens het laden; die is hersteld en met een regressietest afgedekt. Op de definitieve Huawei-build zijn daarna het echte detailvenster, snelheidsgegevens, het aangeleverde kaartspoor en de originele Strava-link daadwerkelijk gecontroleerd.
3. De eigenaar nam een echte VELO-rit op met **9 opgeslagen GPS-punten**. Strava aanvaardde de GPX-upload en gaf een upload-ID terug. Er kwamen echte create- en delete-webhooks binnen. Strava meldde daarna dat de aangemaakte activiteit verwijderd was; de eigenaar bevestigde dat hij de testrit zelf had verwijderd. VELO respecteert dit en maakt geen nieuwe kopie. Er is daarom geen blijvende activiteitlink voor die verwijderde testrit geclaimd.
4. Twee herhaalde backend-aanvragen voor diezelfde rit retourneerden hetzelfde ontvangstbewijs; er bleef precies één uploadtaak bestaan, zonder een nieuwe providerupload.
5. Een echte refresh-aanvraag is gedaan en het antwoord is opnieuw versleuteld opgeslagen. Het nieuwste ontvangen refresh-token is gecontroleerd. Strava gaf in deze live test hetzelfde refresh-token terug; daadwerkelijke rotatie en een verlopen token zijn daarnaast in geïsoleerde tests gecontroleerd, zonder te beweren dat zes uur is afgewacht.
6. Ontkoppelen is vanuit de echte app getest: providerverbinding en cache verdwenen, terwijl het minimale eigen ontvangstbewijs behouden bleef. Eigen ritdocumenten worden door de ontkoppelfunctie niet gewijzigd. Opnieuw autoriseren werkte en haalde de 8 activiteiten opnieuw op.
7. Zonder wifi bleef de fietscomputer op de Huawei bruikbaar. De oorspronkelijke wifi-instelling is hersteld. Offline upload/hervatting en eigenaarisolatie zijn ook met geïsoleerde netwerkfixtures getest. Er is geen tweede echte upload van de verwijderde testrit gemaakt om een storing na te bootsen.
8. Cloudbeveiliging is gecontroleerd: een gewone authenticated client heeft geen SELECT-recht op de tokentabel en geen EXECUTE-recht op de private gateway, token-/ontkoppel-RPC's. Een andere authenticated identiteit zag nul persoonlijke taken in een teruggedraaide SQL-test, zonder extra account te maken.

## Kwaliteitscontrole

- `flutter analyze`: schoon.
- **166 Fluttertests geslaagd**, inclusief nieuwe Strava-tests en de regressietest voor activiteitdetails.
- **18 Edge-tests geslaagd**; Deno-typecontrole voor alle drie functies geslaagd. De tests dekken OAuth, encryptie, verlopen/ingetrokken tokens, refresh-concurrentie, paging/resume, uploadstatus/idempotentie, rate-limits, webhookvalidatie, persistente ontvangst en verwijderde activiteiten.
- Android-debug- en releasebuild geslaagd uit dezelfde definitieve bron; de debugvariant is op de bestaande Huawei bijgewerkt, zonder uninstall of wissen van appgegevens.
- Broncode en beide APK's zijn gecontroleerd tegen de bekende private secretwaarden; geen waarden gevonden. Productiecredentials en persoonlijke GPS-bestanden zijn buiten Git gehouden.

## Nog te configureren

Voor het eigen geregistreerde Strava-account ontbreekt geen vereiste configuratie meer. Het eigen callbackdomein en webhook zijn actief. Er is geen Docker-, Portainer- of eigen-domeinconfiguratie nodig.

Automatisch uploaden blijft een bewuste keuze. Een toekomstige echte rit kan handmatig worden verstuurd of na die keuze automatisch na opslaan. Route-import is behouden maar niet live getest met een Strava-route; deze stond uit. De live uploadtest bewijst acceptatie en de daaropvolgende, door de eigenaar bevestigde verwijdering; de blijvende positieve uploadlink is met geïsoleerde tests gecontroleerd omdat de testrit al verwijderd was.

Installatie, beheer, back-ups, rechten en officiële documentatie: [STRAVA.md](STRAVA.md).
