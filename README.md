# PhotoVault WordPress Infrastructure

Ce depot racine versionne uniquement l'environnement Docker et sa documentation. Le coeur WordPress, les uploads, les plugins tiers et les quatre depots applicatifs sont volontairement ignores.

Le runbook canonique, depuis le choix du serveur jusqu'au rollback, est `doc/GUIDE-DEVOPS-COMPLET.md`.

Depots applicatifs independants:

- wp-content/themes/PhotoVault
- wp-content/plugins/photovault-core
- wp-content/plugins/identity-security-kit
- wp-content/plugins/newsletter-campaign-kit

## Demarrage local

Avec GNU Make sous Linux, macOS, WSL ou Git Bash:

    make init
    make deploy
    make status

Le deploiement attend les healthchecks puis verifie WordPress, le theme et les trois plugins applicatifs. `make help` affiche toutes les commandes disponibles.

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

Le healthcheck Nginx utilise l'endpoint interne `/healthz` et ne suit donc pas
les redirections WordPress. En local, `WORDPRESS_MAIL_FROM` et
`WORDPRESS_MAIL_FROM_NAME` configurent l'expediteur global via un mu-plugin
Docker; utilisez toujours une adresse syntaxiquement valide.

Le moteur Docker Desktop doit etre demarre. Ne commitez jamais le fichier .env genere.

Les credentials Twilio et Resend API sont places dans `docker/wp-config-secrets.php`; le SMTP transactionnel est configure dans `.env`. Aucun secret ne doit entrer dans le Makefile, un fichier exemple ou Git. `make provider-status` indique l'etat sans afficher les valeurs. Sur l'hebergement final, `make production-preflight PUBLIC_URL=https://votre-domaine.example` refuse les providers de test, Mailpit, une home non HTTPS et les principaux en-tetes publics manquants avant la recette de reception reelle.

## Sauvegarde et restauration

Creer un snapshot atomique MariaDB + uploads + originaux prives:

    pwsh -File docker/scripts/backup.ps1

Verifier puis tester la restauration sans toucher au site actif:

    pwsh -File docker/scripts/restore.ps1 -Mode verify -Backup photovault-YYYYMMDDTHHMMSSZ
    pwsh -File docker/scripts/restore.ps1 -Mode test -Backup photovault-YYYYMMDDTHHMMSSZ

Appliquer une restauration reelle exige une confirmation. Le wrapper suspend les services web/cron actifs, cree des fichiers de rollback, restaure puis redemarre les memes services:

    pwsh -File docker/scripts/restore.ps1 -Mode apply -Backup photovault-YYYYMMDDTHHMMSSZ -Confirm

Les snapshots sous `backups/` sont ignores par Git. Copiez-les vers un stockage chiffre hors machine avec une politique de retention adaptee.

## Strategie de version

Le depot racine suit les fichiers d'infrastructure. Chaque depot applicatif conserve son propre historique et doit etre committe separement lorsqu'il est modifie.
