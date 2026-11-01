# Productupgrade — 1 november 2026

Baseline: Flutter 3.47.2 / Dart 3.13.2; 73 tests geslaagd. Bestaande SQLite, GPS-filters, GPX, BLE en Strava blijven behouden. Huawei ELE-L29 (Android 10/API29) aangesloten; update zonder gegevens wissen.

1. Applicatiebrede ritcontroller en vijf blijvende navigatietabs.
2. OLED/graphite/light/system thema, accent/contrast/nacht, nieuw dashboard en Meer-menu.
3. MapLibre-native met echte OpenFreeMap-stijlen, providerinstellingen, huidige positie en routes. Bestaande raster-MBTiles als compatibele import behouden.
4. Begrensde, providerconforme offline gebieden, status/voortgang/pauze/verwijderen/herstart.
5. Lokale gevalideerde trainingsgenerator, voorkeuren, bewerken/bibliotheek/weekplanner en opgeslagen uitvoering met meetgegevens.
6. Bestaande tests aanpassen aan het product, nieuwe regressies, debug/release en fysieke toestelcontrole.

Geen fictieve metingen. Kaartcentrum zonder GPS is een expliciet wereld-overzicht, geen gebruikerslocatie. Geen sleutelafhankelijke provider als werkend presenteren.
