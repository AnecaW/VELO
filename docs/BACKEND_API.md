# Backend API

Gebruik `Authorization: Bearer <access_token>` voor alle eigen gegevens. Access-tokens leven 15 minuten. Refresh-tokens worden bij iedere vernieuwing vervangen en alleen als digest bewaard. Hergebruik trekt de familie in; wachtwoordwijziging en herstel trekken alle sessies in. Wachtwoorden gebruiken Argon2id, bestaande scrypt-hashes blijven leesbaar.

| Methode | Pad | Inhoud |
|---|---|---|
| GET | `/healthz` | Databasehealthcheck |
| GET | `/api/v1/server` | Publieke configuratiestatus |
| POST | `/api/v1/accounts/register` | `email`, `password` |
| POST | `/api/v1/accounts/login` | `email`, `password` |
| POST | `/api/v1/accounts/refresh` | `refresh_token`; eenmalige rotatie |
| POST | `/api/v1/accounts/logout` | `refresh_token`; familie intrekken |
| GET | `/api/v1/me` | Eigen account |
| DELETE | `/api/v1/me` | `password`; account en servergegevens verwijderen |
| POST | `/api/v1/accounts/password` | `current_password`, `new_password` |
| POST | `/api/v1/accounts/password-reset` | `email`; 503 zolang SMTP ontbreekt |
| GET/POST | `/account/reset` | Eenmalige herstelpagina |
| GET | `/api/v1/integrations/strava` | Status, account-ID, rechten, laatste sync, voorkeuren, fout |
| POST | `/api/v1/integrations/strava/authorize` | State, telefoonchallenge en scopes |
| GET | `/oauth/strava/callback` | Officiële OAuth-callback |
| POST | `/api/v1/integrations/strava/confirm` | State, handoff en telefoonverifier |
| PUT | `/api/v1/integrations/strava/preferences` | Afzonderlijke gegevenskeuzes |
| POST | `/api/v1/integrations/strava/sync` | Synchronisatiejob inplannen |
| DELETE | `/api/v1/integrations/strava` | Toegang intrekken en gegevens wissen |
| GET | `/api/v1/integrations/strava/activities` | Eigen tijdelijke activiteitencache |
| GET | `/api/v1/integrations/strava/activities/{id}` | Detail in eigen cache |
| GET | `/api/v1/integrations/strava/routes` | Eigen tijdelijke routecache |
| POST | `/api/v1/integrations/strava/uploads/{ride_id}` | Eigen rit uploaden na opt-in |
| GET | `/api/v1/jobs` | Laatste honderd eigen jobs |
| GET | `/api/v1/jobs/{id}` | Eigen jobstatus |
| GET | `/api/v1/sync/history` | Laatste honderd eigen gebeurtenissen |
| GET/PUT/DELETE | `/api/v1/data/{kind}[/{id}]` | Versleutelde eigen documenten met revisies |

Fouten hebben `{"error":{"code":"...","message":"..."}}`. Validatiefouten echoën geen invoer. De oudere gebruikersnaam/uitnodigingsroutes blijven voor compatibiliteit behouden; nieuwe Android-accounts gebruiken de e-mailroutes. Gebruik voor installatie het interactieve CLI-commando `create-admin`. Stel voor deze installatie geen bootstrapsecret in.

De server bewaart Strava-tokens versleuteld; Android ontvangt uitsluitend een eenmalige handoff en bewaart de VELO-sessie in secure storage. Activiteitenimport, route-import en eigen GPX-upload zijn afzonderlijke functies. Route-export naar Strava is niet beschikbaar. Een onzekere upload wordt niet blind herhaald. API-cache verloopt na maximaal 24 uur en wordt niet geback-upt of als lokale rit meegeteld.

Gecontroleerde officiële bronnen op 1 november 2026:

- [Strava OAuth](https://developers.strava.com/docs/authentication/) en [limieten](https://developers.strava.com/docs/rate-limits/).
- [Komoot](https://support.komoot.com/hc/en-us/articles/10331570510618-komoot-API): geen publieke API.
- [Garmin Connect](https://developer.garmin.com/gc-developer-program): persoonlijke en zakelijke API-toegang, eigen adapter nodig.
- [Wahoo Cloud API](https://developers.wahooligan.com/cloud): appgoedkeuring vereist.
- [Ride with GPS](https://ridewithgps.com/api/v1/doc/): officiële API, eigen client nodig.
- [TrainingPeaks](https://help.trainingpeaks.com/hc/en-us/articles/234441128-TrainingPeaks-API): goedgekeurde ontwikkelaars.
- [Health Connect](https://developer.android.com/health-and-fitness/health-connect/get-started): Android SDK en afzonderlijke systeemtoestemming.

Alleen Strava heeft een serveradapter. De overige diensten worden informatief getoond; er worden geen verbindingen gesimuleerd. Lokale fietscomputerfuncties blijven zonder account en bij serveruitval toegankelijk.
