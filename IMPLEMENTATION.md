# Uitvoeringsplan

De bestaande Flutter/Dart-app blijft behouden; een herschrijving naar Compose zou bruikbare code en tests vervangen. Android-integratie gebeurt via plugins en een kleine native Kotlin-brug.

1. Onderzoek bestaande broncode, tests en Android-toolchain (uitgevoerd).
2. Vervang standaard simulatie door echte GPS en BLE; herstel GPS-filters, timers, pauzes en foutafhandeling.
3. Gebruik duurzame SQLite-opslag met migratie, volledige sessies en checkpoints voor crashherstel.
4. Bouw GPX-import/export, kaartweergave, lokale routeopslag en echte providerroutering met expliciete configuratie.
5. Maak gegevensschermen, instellingen, launcher/appmenu en diagnostiek bruikbaar en persistent.
6. Voeg kern-, opslag-, navigatie- en UI-regressietests toe; voer bestaande tests uit en corrigeer verouderde tests inhoudelijk.
7. Bouw debug en release; probeer installatie en visuele inspectie wanneer een Android-runtime beschikbaar is.
8. Lever APK's en een eerlijk overzicht van implementatie, testbewijs en beperkingen.

## Omgeving bij aanvang

- Flutter 3.47.2 / Dart 3.13.2; bestaande Drift/SQLite, Bloc en GoRouter.
- Android SDK 36.1.0 en emulatorbinary aanwezig; geen AVD/system image en geen aangesloten toestel.
- Android command-line tools ontbreken; bestaande Gradle-wrapper en geïnstalleerde buildtools worden eerst gebruikt.
- De oorspronkelijke database werd voor elke instantie in een nieuwe tijdelijke map aangemaakt. Daardoor was opslag na procesherstart niet duurzaam.
- Het oorspronkelijke ritvenster gebruikte standaard MockGPSService en gesimuleerde sensoren.
- De oorspronkelijke routeplanner gaf hemelsbrede afstand weer als route; deze wordt uitsluitend als afstandsberekening behouden.
