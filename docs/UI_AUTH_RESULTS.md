> Verslag van versie 2.4.0. De latere werkende Strava-integratie staat in [STRAVA_RESULTS.md](STRAVA_RESULTS.md).

# VELO 2.4.0 — UI, Android-apps en echte mailauthenticatie

Datum: 1 november 2026. Dit is het actuele resultaat; de 2.3.0-verslagen beschrijven de eerdere installatie.

## Uitgevoerd

- Eén spacingbasis (8/12/16/24), gedeelde paginalijst, sectiegroepen en meldingen; consistente velden, knoppen, kaarten en dialogen. Profielen, kaartinstellingen en uiterlijk gebruiken dezelfde begrensde paginalijst. Trainings- en activiteitenkaarten hebben expliciete tussenruimte. Fietscomputerlabels, waarden en eenheden staan als één groep met uitgelijnde waarderegels.
- Apps staat midden in de hoofdnavigatie. De bestaande interne hub heet **VELO-functies** en blijft bereikbaar. Android-apps komen via `ACTION_MAIN` / `CATEGORY_LAUNCHER` uit PackageManager, met echte labels en PNG-iconen. Query en iconrendering draaien op een native achtergrondexecutor. Flutter cachet kort en ververst bij terugkeer; zoeken, alfabetische sortering, favorieten, lege toestand, retry en fouten bij openen zijn beschikbaar. Geen `QUERY_ALL_PACKAGES` toegevoegd. Schermvastzetten blijft beschikbaar onder Scherminstellingen en vraagt de normale Android-bevestiging.
- Instellingen groepeert bestaande functies onder Account, Weergave, Fietscomputer, Kaart en navigatie, Training, Integraties, Gegevens en privacy, Over VELO en uitsluitend in ontwikkelbuilds Ontwikkeling. Werkende opties, kaartenimport, back-up/herstel, sensoren en diagnostiek zijn behouden. Versie/build komen van het geïnstalleerde Android-pakket.
- Registratie vraagt naam, e-mail en minimaal 12 wachtwoordtekens. De officiële Supabase SDK verzorgt registratie, bevestiging opnieuw versturen, login, herstel, OTP en sessies. Een Auth-trigger maakt het eigen profiel met naam. De migratie is daadwerkelijk toegepast.
- De al aanwezige Supabase SMTP-configuratie is behouden; e-mailbevestiging is nu verplicht en herstel staat aan. De mailtemplates bevatten een Android-link én een eenmalige code. Deze code werkt ook wanneer de gebruiker zijn mail op een iPhone leest. Mailcodes, sessies en wachtwoorden worden niet gelogd. SMTP- en beheergeheimen blijven server-side.
- Herstel heeft een aparte aanvraagpagina en nieuw-wachtwoordpagina met dubbele invoer. Opnieuw aanvragen heeft een wachttijd. Ongeldige codes/links geven een herstelbare melding; netwerkfouten blokkeren lokale fietsfuncties niet.

## Werkelijk gecontroleerd

- `flutter pub get`: geslaagd.
- `flutter analyze`: geen issues.
- `flutter test`: **158 geslaagd**, waaronder nieuwe tests voor native appdata/cache/sortering, openen/verwijderd pakket, lege toestand/retry, kleine breedte met grotere tekst, registratienaam, wachten op mailbevestiging, resend, onbevestigde login, reset via SDK, herstelcode/wachtwoordupdate/sessie-intrekking en verlopen-linkweergave.
- Edge-tests: **7 geslaagd**. Dit zijn geïsoleerde tests, geen live Strava-verbinding.
- Android-releasebuild: geslaagd met private releaseondertekening. De eerste releasepoging met `--no-pub` gebruikte een oude debug-pluginregistratie en faalde; de normale releaseopdracht vernieuwde de gegenereerde registratie en bouwde succesvol. Het bestaande buildscript gebruikt deze normale opdracht.
- Android-debugbuild: geslaagd en als update op de aangesloten Huawei ELE-L29 geïnstalleerd, zonder verwijderen of wissen van appgegevens.
- Na de update werd het echte ingelogde account automatisch hersteld; de instellingen toonden het juiste account en pakketversie 2.4.0 (6).
- Op die fysieke telefoon zijn de fietscomputer, echte app-grid, instellingen, registratie en herstel bekeken. De daadwerkelijke Clock-app is vanuit de grid geopend en VELO bleef daarna bruikbaar. Een geïnjecteerde verlopen auth-link bereikte daadwerkelijk de aparte foutpagina. Visuele auditbestanden staan uitsluitend in de genegeerde lokale artifacts-map.
- Registratie van uitsluitend het door de eigenaar opgegeven echte account vanaf de Huawei is door Supabase aanvaard. De eigenaar bevestigde ontvangst van de verificatiemail. Na openen op een iPhone kon Safari het Android-adres niet openen; de serverbevestiging was wél voltooid. Dat is gecontroleerd in Auth. Een succesvolle automatische linkoverdracht op Android is hiermee niet geclaimd; de alternatieve codeflow is toegevoegd.
- Echte e-mail/wachtwoordlogin, het juiste eigen profiel met naam en intrekking van uitsluitend de audit-login zijn gecontroleerd. Anonieme toegang tot dat profiel werd geblokkeerd. Een andere authenticated identiteit zag nul profielen in een teruggedraaide SQL-transactie, zonder een tweede account te maken.
- Daarna bevestigde de eigenaar dat hij de ontvangen herstelcode in VELO heeft ingevoerd en zijn eigen nieuwe wachtwoord heeft ingesteld. De tijdelijke lokale registratiecredential is verwijderd. Het eigen gekozen wachtwoord is niet gedeeld of opgeslagen door de ontwikkeltools.

## Bestanden

De wijzigingen staan in `lib/app/`, `lib/widgets/velo_ui.dart`, `lib/features/accounts/`, `lib/features/more/`, de instellingen-/profiel-/kaart-/training-/activiteiten-/fietsschermen, `lib/services/android_apps.dart`, de accountadapter, de native Android MethodChannel, tests, beheerscripts en `supabase/migrations/20261101180000_registration_profiles.sql`. De oude self-hosted broncode is niet verwijderd; de actieve app gebruikt alleen Supabase.

## Gebruik en grenzen

Download versie 2.4.0 via de GitHub-release. Gebruik **velo-debug.apk** als update voor de bestaande testtelefoon; **velo-supabase.apk** gebruikt de aparte private releaseondertekening voor nieuwe installaties. Wissel niet van ondertekening door persoonlijke appgegevens te wissen.

Voor mail op hetzelfde Android-toestel blijft de PKCE-link beschikbaar. Lees je de mail op een ander toestel, voer dan de code uit de nieuwste mail in VELO in; deel hem met niemand. Een al bevestigd account kan rechtstreeks inloggen. Supabase houdt de rate-limits en geldigheid van codes aan. De app gebruikt geen eigen mailserver of onbeveiligde bypass.

De oude live wegwerpaccounttest weigert productie-uitvoering met bevestigingsmail; de historische native wegwerpaccounttest wordt op het productieproject overgeslagen. Nieuwe unitfixtures versturen geen echte mail. De eerder gerapporteerde 35 cloudtests horen bij 2.3.0 en zijn niet opnieuw als SMTP-test uitgevoerd.

Strava mist nog echte providercredentials; online routeplanning mist ORS. Deze diensten zijn niet als live werkend getest of gepresenteerd. Er is geen Docker-, Portainer- of domeinconfiguratie gewijzigd. De Gradle-build geeft een niet-blokkerende waarschuwing over een toekomstige Kotlin-migratie van workmanager; de huidige builds slagen.
