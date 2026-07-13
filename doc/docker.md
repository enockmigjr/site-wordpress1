# Environnement Docker PhotoVault

L'environnement local utilise Nginx, WordPress PHP-FPM, MariaDB, Mailpit, WP-CLI et un runner cron.

## Versions et responsabilites

- WordPress: branche 7.0 avec PHP 8.2 FPM.
- WP-CLI: 2.12.0, telecharge depuis la release officielle et verifie en SHA-512.
- MariaDB: branche LTS 11.4.
- Mailpit: SMTP interne sur le port 1025 et UI locale sur le port 8025.
- Nginx: reverse proxy local sur le port 8080.
- Cron: execute les evenements dus toutes les 60 secondes; WP-Cron opportuniste est desactive.

## Initialisation

PowerShell:

    pwsh -File docker/scripts/init-env.ps1

Linux/macOS:

    sh docker/scripts/init-env.sh

Les scripts refusent d'ecraser un fichier .env existant et generent des secrets cryptographiquement aleatoires.

## Validation et demarrage

    docker compose config --quiet
    docker compose up --build -d
    docker compose ps
    docker compose logs --tail=100 wordpress nginx db mailpit cron

## Verification fonctionnelle

1. Ouvrir http://localhost:8080.
2. Ouvrir http://localhost:8025.
3. Verifier le endpoint interne Nginx:

       curl http://localhost:8080/healthz

4. Envoyer une verification email ou un OTP depuis Identity Security Kit.
5. Confirmer la reception dans Mailpit.
6. Tester l'expediteur WordPress global:

       docker compose exec cron wp eval "var_export(wp_mail('docker-test@example.test','Docker mail test','Mail transport is operational.'));" --allow-root

7. Executer les evenements dus:

       docker compose exec cron wp cron event run --due-now --allow-root --path=/var/www/html

8. Verifier les plugins:

       docker compose exec wordpress wp plugin list --allow-root --path=/var/www/html

## Securite

- Les ports HTTP et Mailpit sont lies a 127.0.0.1 en developpement.
- Les mots de passe DB et les salts WordPress sont obligatoires.
- Le fichier .env est ignore par Git et Docker.
- Les originaux PhotoVault prives sont bloques par Nginx.
- PHP est interdit dans wp-content/uploads.
- wp-config.php, fichiers caches, backups, dumps SQL, readme et licence ne sont pas servis.
- wp_mail utilise msmtp vers Mailpit dans l'image locale.
- WORDPRESS_MAIL_FROM et WORDPRESS_MAIL_FROM_NAME sont appliques par un mu-plugin Docker charge depuis /opt/photovault/mu-plugins.
- Le healthcheck Nginx cible /healthz et ne suit pas les redirections applicatives.
- L'editeur de fichiers WordPress est desactive.
- WP_DEBUG ne s'affiche jamais dans les reponses HTML.

## Limites actuelles

- Le moteur Docker doit etre actif pour le build et les tests bout-en-bout.
- La branche WordPress 7.0 de l'image applique les correctifs de maintenance; le coeur XAMPP local doit aussi etre mis a jour separement.
- Cette configuration monte le projet local pour le developpement. Une image de production immutable necessitera les URLs distantes ou un registre d'artefacts pour les quatre depots applicatifs.
