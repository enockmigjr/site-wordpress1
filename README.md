# PhotoVault WordPress Infrastructure

Ce depot racine versionne uniquement l'environnement Docker et sa documentation. Le coeur WordPress, les uploads, les plugins tiers et les quatre depots applicatifs sont volontairement ignores.

Depots applicatifs independants:

- wp-content/themes/PhotoVault
- wp-content/plugins/photovault-core
- wp-content/plugins/identity-security-kit
- wp-content/plugins/newsletter-campaign-kit

## Demarrage local

Sous PowerShell:

    pwsh -File docker/scripts/init-env.ps1
    docker compose config --quiet
    docker compose up --build -d
    docker compose ps

Sous Linux/macOS:

    sh docker/scripts/init-env.sh
    docker compose config --quiet
    docker compose up --build -d

Application: http://localhost:8080
Mailpit: http://localhost:8025

Le moteur Docker Desktop doit etre demarre. Ne commitez jamais le fichier .env genere.

## Strategie de version

Le depot racine suit les fichiers d'infrastructure. Chaque depot applicatif conserve son propre historique et doit etre committe separement lorsqu'il est modifie.
