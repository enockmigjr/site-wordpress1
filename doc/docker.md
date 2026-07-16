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

### Secrets Twilio et Resend dans wp-config

Le `wp-config.php` du conteneur est fourni par `docker/wp-config-docker.php`. Pour conserver les cles provider dans la configuration WordPress sans les versionner:

```powershell
Copy-Item docker/wp-config-secrets.example.php docker/wp-config-secrets.php
```

Renseigner ensuite les quatre constantes dans `docker/wp-config-secrets.php`. Ce fichier local est charge automatiquement avant WordPress, ignore par Git et par le contexte de build, et son dossier est inaccessible via Nginx. Ne jamais renseigner les valeurs reelles dans le fichier `.example.php`.

## Validation et demarrage

### Avec GNU Make

Le `Makefile` est l'interface recommandee sous Linux, macOS, WSL ou Git Bash avec GNU Make:

    make init
    make deploy

`make deploy` valide la configuration, construit les images, demarre les services avec attente des healthchecks, puis confirme que WordPress est installe, que le theme PhotoVault est actif et que les trois plugins applicatifs sont actifs.

Commandes d'exploitation courantes:

    make status
    make logs
    make verify
    make provider-status
    make cron
    make wp WP_ARGS="option get home"
    make restart
    make stop

`make down` retire les conteneurs et le reseau mais conserve le volume MariaDB. Ne pas ajouter `-v` sauf si la suppression definitive de la base est voulue et sauvegardee.

Sous Windows, executer le Makefile depuis WSL ou Git Bash. Si GNU Make n'est pas installe, les commandes Docker Compose equivalentes ci-dessous restent valides depuis PowerShell.

### Sans GNU Make

    docker compose config --quiet
    docker compose up --build -d --remove-orphans --wait --wait-timeout 180
    docker compose ps
    docker compose exec -T wordpress wp --allow-root core is-installed --path=/var/www/html
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

9. Verifier la configuration des providers sans afficher les secrets:

       make provider-status

## Sauvegarde et restauration

Un snapshot contient:

- `database.sql.gz`: dump MariaDB transactionnel avec routines, triggers et events;
- `media.tar.gz`: `wp-content/uploads` et `wp-content/photovault-private`;
- `manifest.txt`: format, date UTC, base et nombre de tables;
- `checksums.sha256`: integrite SHA-256 des trois fichiers precedents.

### PowerShell

    pwsh -File docker/scripts/backup.ps1
    pwsh -File docker/scripts/backup.ps1 -Name avant-migration
    pwsh -File docker/scripts/restore.ps1 -Mode verify -Backup avant-migration
    pwsh -File docker/scripts/restore.ps1 -Mode test -Backup avant-migration
    pwsh -File docker/scripts/restore.ps1 -Mode apply -Backup avant-migration -Confirm

### GNU Make

    make backup
    make restore-verify BACKUP=avant-migration
    make restore-test BACKUP=avant-migration

### Linux/macOS avec Docker Compose

    docker compose --profile tools run --rm backup
    docker compose --profile tools run --rm backup avant-migration
    docker compose --profile tools run --rm restore verify avant-migration
    docker compose --profile tools run --rm restore test avant-migration

Pour une restauration reelle hors wrapper PowerShell, arreter d'abord `nginx`, `cron` et `wordpress`, puis fournir les deux confirmations au conteneur. Le wrapper PowerShell automatise cette maintenance et doit etre prefere sous Windows.

Le mode `verify` controle checksums, gzip, manifeste et chemins de l'archive. Le mode `test` importe le dump dans une base temporaire, compare le nombre de tables et extrait les medias sous `/tmp`. Le mode `apply` execute d'abord ces controles, cree un dump et une archive media `pre-restore-*`, puis applique le snapshot. Une erreur pendant l'application declenche le rollback automatique.

Les dossiers `backups/` restent hors Git. En production, ajouter chiffrement, stockage hors site, retention, surveillance des echecs et tests periodiques sur une infrastructure distincte.

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
- Les outils de backup valident le flux local; la rotation, le chiffrement et la copie hors site dependent encore de l'environnement de production.

## Deploiement sur un serveur

Cette pile convient a un serveur Docker mono-hote disposant du checkout complet du projet. Avant une exposition publique:

1. Installer Docker Engine, le plugin Docker Compose, Git et GNU Make.
2. Cloner le depot racine et les quatre depots applicatifs a leurs chemins documentes dans le README.
3. Executer `make init`, puis remplacer `PHOTOVAULT_ENV=development`, `WORDPRESS_DEBUG=1` et les ports locaux par les valeurs de recette ou production adaptees.
4. Renseigner `docker/wp-config-secrets.php` sans committer ce fichier; utiliser idealement un gestionnaire de secrets et un montage en lecture seule sur le serveur.
5. Placer Nginx derriere un reverse proxy TLS; conserver le port PhotoVault lie a `127.0.0.1` lorsque le proxy se trouve sur le meme hote.
6. Configurer DNS, HTTPS, `home` et `siteurl`, puis utiliser un expediteur Resend verifie avec SPF et DKIM.
7. Executer `make deploy`, `make verify`, `make provider-status` et un test reel email/SMS.
8. Creer `make backup`, copier le snapshot vers un stockage chiffre hors hote et tester une restauration.

Le deploiement n'est considere termine que lorsque tous les services sont `healthy`, la verification applicative passe, les URL HTTPS publiques repondent, les taches cron s'executent et les sauvegardes sont restaurees sur un environnement isole.
