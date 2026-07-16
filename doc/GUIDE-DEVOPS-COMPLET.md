# PhotoVault - guide DevOps complet

Derniere mise a jour: 2026-07-16

Ce fichier est le runbook canonique de PhotoVault. Il couvre la presentation locale, le deploiement mono-hote Docker, HTTPS, les emails transactionnels, les fournisseurs, les sauvegardes, la supervision, les mises a jour et le retour arriere. Les commandes supposent Ubuntu Server 24.04 LTS, un domaine public et un utilisateur `deploy`.

## 1. Etat de livraison

- Application, theme, plugins, donnees de demonstration et environnement Docker: termines.
- Presentation locale: validee avec cinq services sains, Mailpit, WordPress, le theme et les trois plugins actifs.
- Twilio Test Credentials et Resend `resend.dev`: valides pour la demonstration.
- Le proprietaire accepte la livraison a 100 % pour la presentation. La reception SMS operateur et l'authentification d'un domaine email restent des activations commerciales differees, pas des fonctionnalites manquantes.
- Le tracking d'ouverture/clic reste desactive. WordPress Multisite n'est pas utilise.

## 2. Architecture retenue

```text
Internet
   |
DNS A/AAAA
   |
Caddy :80/:443 (TLS, headers, logs)
   |
127.0.0.1:8080
   |
Nginx Docker -> PHP-FPM WordPress
                    |-- MariaDB
                    |-- cron WP-CLI
                    |-- Mailpit en local
                    |-- Resend SMTP en production
                    |-- Resend API pour les campagnes
                    `-- Twilio API pour les OTP SMS
```

Le stockage sensible se trouve dans `wp-content/photovault-private`. Nginx refuse son acces direct. Les originaux ne sont remis que par les endpoints WordPress autorises.

## 3. Type de serveur

| Usage | Choix | Capacite conseillee |
|---|---|---|
| Demonstration locale | PC avec Docker Desktop | 4 coeurs, 8 Go RAM, 30 Go libres |
| Production initiale | VPS Ubuntu 24.04 LTS x86_64 | 4 vCPU, 8 Go RAM, 100 Go NVMe |
| Petit trafic avec peu d'originaux | VPS minimal | 2 vCPU, 4 Go RAM, 60 Go SSD |
| Galerie volumineuse | VPS/dedie + stockage objet/CDN | 8 vCPU, 16 Go RAM, volume dimensionne |

Le VPS mono-hote est recommande. Un hebergement WordPress mutualise est inadapte a cette pile Docker, au stockage prive et au cron supervise. Kubernetes n'apporte rien au lancement; il devient pertinent seulement avec plusieurs noeuds, une equipe d'exploitation et des besoins de haute disponibilite mesures.

Dimensionner le disque avec cette formule:

```text
originaux + miniatures + base + 2 sauvegardes locales + 30 % de marge
```

## 4. Valeurs a preparer

Remplacer ces exemples dans toutes les commandes:

```text
SERVER_IP=203.0.113.10
DOMAIN=photos.example.com
ADMIN_EMAIL=admin@example.com
APP_DIR=/srv/photovault
```

Preparer avant le deploiement:

1. Une cle SSH d'administration.
2. Un enregistrement DNS `A` vers l'IPv4; ajouter `AAAA` uniquement si IPv6 est configure.
3. Une boite administrateur externe au serveur.
4. Pour le live: domaine Resend verifie, cle Resend, numero Twilio SMS et credentials live.
5. Un stockage objet hors serveur pour les sauvegardes.

## 5. Preparation Ubuntu

Se connecter une premiere fois en root, creer l'utilisateur puis verifier une seconde connexion SSH avant de durcir SSH:

```bash
ssh root@SERVER_IP
adduser deploy
usermod -aG sudo deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chown deploy:deploy /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
```

Depuis un second terminal:

```bash
ssh deploy@SERVER_IP
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y git make curl ca-certificates unattended-upgrades ufw
sudo timedatectl set-timezone Africa/Porto-Novo
```

Apres avoir confirme la connexion par cle, editer `/etc/ssh/sshd_config.d/99-photovault.conf`:

```text
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
```

Valider avant rechargement:

```bash
sudo sshd -t
sudo systemctl reload ssh
```

Configurer le firewall. Les ports Docker applicatifs restent lies a `127.0.0.1`; seuls SSH, HTTP et HTTPS sont publics:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose
```

Docker avertit que les ports de conteneurs publies peuvent contourner certaines regles UFW. Ne jamais remplacer les liaisons `127.0.0.1` de `docker-compose.yml` par `0.0.0.0`.

## 6. Installation Docker officielle

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker deploy
```

Le groupe `docker` donne des privileges equivalents a root. Se deconnecter/reconnecter, limiter ce groupe aux exploitants et ne jamais exposer `/var/run/docker.sock` sur TCP.

Verification:

```bash
docker version
docker compose version
docker run --rm hello-world
```

Reference officielle: <https://docs.docker.com/engine/install/ubuntu/>.

## 7. Installation des cinq depots

```bash
sudo install -d -o deploy -g deploy /srv/photovault
git clone https://github.com/enockmigjr/site-wordpress1.git /srv/photovault
cd /srv/photovault
mkdir -p wp-content/themes wp-content/plugins
git clone https://github.com/enockmigjr/PhotoVault.git wp-content/themes/PhotoVault
git clone https://github.com/enockmigjr/photovault-core.git wp-content/plugins/photovault-core
git clone https://github.com/enockmigjr/identity-security-kit.git wp-content/plugins/identity-security-kit
git clone https://github.com/enockmigjr/newsletter-campaign-kit.git wp-content/plugins/newsletter-campaign-kit
```

Verifier les branches et conserver les SHA de livraison:

```bash
git -C /srv/photovault status --short --branch
git -C /srv/photovault/wp-content/themes/PhotoVault status --short --branch
git -C /srv/photovault/wp-content/plugins/photovault-core status --short --branch
git -C /srv/photovault/wp-content/plugins/identity-security-kit status --short --branch
git -C /srv/photovault/wp-content/plugins/newsletter-campaign-kit status --short --branch
```

Ne jamais deployer un worktree sale. Pour une livraison reproductible, noter les cinq SHA dans le ticket de release ou poser des tags signes.

## 8. Configuration `.env`

Initialiser sans ecraser un fichier existant:

```bash
cd /srv/photovault
make init
chmod 600 .env docker/wp-config-secrets.php
nano .env
```

Configuration de production type:

```dotenv
PHOTOVAULT_HTTP_PORT=8080
MAILPIT_UI_PORT=8025
PHOTOVAULT_ENV=production
WORDPRESS_DEBUG=0
WORDPRESS_FORCE_SSL_ADMIN=1
WORDPRESS_HOME_URL=https://photos.example.com
WORDPRESS_SITE_URL=https://photos.example.com
PHOTOVAULT_TRUST_PROXY_HEADERS=1

WORDPRESS_MAIL_FROM=notifications@photos.example.com
WORDPRESS_MAIL_FROM_NAME=PhotoVault

PHOTOVAULT_SMTP_MODE=smtp
PHOTOVAULT_SMTP_HOST=smtp.resend.com
PHOTOVAULT_SMTP_PORT=587
PHOTOVAULT_SMTP_USER=resend
PHOTOVAULT_SMTP_PASSWORD=REPLACE_WITH_RESEND_API_KEY
PHOTOVAULT_SMTP_FROM=notifications@photos.example.com
PHOTOVAULT_SMTP_TLS=on
PHOTOVAULT_SMTP_STARTTLS=on

WORDPRESS_DB_NAME=photovault
WORDPRESS_DB_USER=photovault
WORDPRESS_DB_PASSWORD=REPLACE_WITH_RANDOM_SECRET
MARIADB_ROOT_PASSWORD=REPLACE_WITH_DIFFERENT_RANDOM_SECRET
WORDPRESS_TABLE_PREFIX=wp_

WORDPRESS_AUTH_KEY=REPLACE_WITH_RANDOM_SECRET
WORDPRESS_SECURE_AUTH_KEY=REPLACE_WITH_RANDOM_SECRET
WORDPRESS_LOGGED_IN_KEY=REPLACE_WITH_RANDOM_SECRET
WORDPRESS_NONCE_KEY=REPLACE_WITH_RANDOM_SECRET
WORDPRESS_AUTH_SALT=REPLACE_WITH_RANDOM_SECRET
WORDPRESS_SECURE_AUTH_SALT=REPLACE_WITH_RANDOM_SECRET
WORDPRESS_LOGGED_IN_SALT=REPLACE_WITH_RANDOM_SECRET
WORDPRESS_NONCE_SALT=REPLACE_WITH_RANDOM_SECRET
```

`make init` genere deja les secrets. Ne recopier aucune valeur du guide. Resend SMTP utilise `smtp.resend.com`, l'utilisateur `resend`, le port STARTTLS `587` et la cle API comme mot de passe. Le mode local reste `PHOTOVAULT_SMTP_MODE=mailpit`.

La cle SMTP est injectee au demarrage dans un fichier ephemere du conteneur, jamais dans l'image. Elle doit tout de meme etre protegee dans `.env`, sauvegardee dans un gestionnaire de secrets et tournee apres exposition.

## 9. Secrets applicatifs

Editer `docker/wp-config-secrets.php`:

```php
<?php
define( 'IDENTITY_SECURITY_TWILIO_ACCOUNT_SID', 'AC_LIVE_OR_TEST' );
define( 'IDENTITY_SECURITY_TWILIO_AUTH_TOKEN', 'SECRET' );
define( 'IDENTITY_SECURITY_TWILIO_FROM', '+12025550123' );
define( 'NEWSLETTER_CAMPAIGN_KIT_RESEND_API_KEY', 're_SECRET' );
```

Regles:

- ne jamais committer `.env` ou `docker/wp-config-secrets.php`;
- utiliser des credentials Twilio Test et `+15005550006` uniquement pour la presentation;
- desactiver le facteur SMS dans Identity Kit tant qu'aucun numero live n'est disponible;
- utiliser une adresse du domaine Resend verifie pour `From`;
- la cle Resend dans `wp-config-secrets.php` sert aux campagnes API; la valeur SMTP de `.env` sert a `wp_mail` (identite, WordPress et notifications transactionnelles).

## 10. DNS et Resend

1. Creer le domaine ou sous-domaine d'envoi dans Resend.
2. Publier exactement les enregistrements SPF et DKIM fournis.
3. Ajouter un DMARC progressif, par exemple `p=none` pendant l'observation puis renforcer selon les rapports.
4. Attendre le statut `Verified` avant d'utiliser l'adresse `From`.
5. Ne pas envoyer depuis `resend.dev` en production.

Reference SMTP: <https://resend.com/docs/send-with-smtp>.

## 11. Reverse proxy HTTPS avec Caddy

Caddy est recommande ici pour le certificat automatique et le renouvellement. Installation officielle:

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
sudo chmod o+r /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy
```

Configurer `/etc/caddy/Caddyfile` en remplacant le domaine:

```caddyfile
photos.example.com {
	encode zstd gzip

	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains"
		X-Content-Type-Options "nosniff"
		X-Frame-Options "SAMEORIGIN"
		Referrer-Policy "strict-origin-when-cross-origin"
		Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()"
		Content-Security-Policy "default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'self'; form-action 'self'; img-src 'self' data: blob: https:; media-src 'self' blob: https:; font-src 'self' data: https:; style-src 'self' 'unsafe-inline' https:; script-src 'self' 'unsafe-inline'; connect-src 'self' https:; upgrade-insecure-requests"
		-Server
	}

	reverse_proxy 127.0.0.1:8080 {
		health_uri /healthz
		health_interval 30s
		health_timeout 5s
	}

	log {
		output file /var/log/caddy/photovault-access.log {
			roll_size 100MiB
			roll_keep 10
			roll_keep_for 720h
		}
		format json
	}
}
```

Tester la CSP sur une recette avant production; ajouter seulement les domaines externes reellement utilises. Ne pas supprimer `PHOTOVAULT_TRUST_PROXY_HEADERS=1` derriere Caddy et ne pas exposer le port 8080 publiquement.

Valider puis recharger:

```bash
sudo caddy fmt --overwrite /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
sudo systemctl status caddy --no-pager
curl -I https://photos.example.com
```

References: <https://caddyserver.com/docs/install>, <https://caddyserver.com/docs/automatic-https>, <https://caddyserver.com/docs/caddyfile/directives/reverse_proxy>.

## 12. Premier deploiement

```bash
cd /srv/photovault
make config
make build
make deploy
make status
make verify
make provider-status
```

Si la base restauree existe deja, ne pas relancer `core install`. Pour une installation vierge, eviter le mot de passe administrateur dans l'historique:

```bash
read -rsp 'WordPress admin password: ' WP_ADMIN_PASSWORD; echo
docker compose exec -T -e WP_ADMIN_PASSWORD="$WP_ADMIN_PASSWORD" wordpress sh -c 'wp core install --allow-root --path=/var/www/html --url="https://photos.example.com" --title="PhotoVault" --admin_user="photovault-admin" --admin_password="$WP_ADMIN_PASSWORD" --admin_email="admin@example.com"'
unset WP_ADMIN_PASSWORD
make verify
```

Activer et verifier les composants si necessaire:

```bash
make wp WP_ARGS="theme activate PhotoVault"
make wp WP_ARGS="plugin activate photovault-core identity-security-kit newsletter-campaign-kit"
make wp WP_ARGS="plugin list"
make wp WP_ARGS="cron event list"
```

Installer les donnees de demonstration seulement sur une recette, jamais sur une production contenant des donnees reelles:

```bash
make wp WP_ARGS="photovault seed_demo --yes"
```

## 13. Commandes d'exploitation

```bash
make help
make config
make build
make deploy
make verify
make status
make logs
make restart
make stop
make down
make cron
make provider-status
make production-preflight PUBLIC_URL=https://photos.example.com
make wp WP_ARGS="option get home"
make backup
make restore-verify BACKUP=photovault-YYYYMMDDTHHMMSSZ
make restore-test BACKUP=photovault-YYYYMMDDTHHMMSSZ
```

Equivalents Docker utiles:

```bash
docker compose ps
docker compose top
docker compose images
docker compose logs --tail=200 nginx wordpress db cron
docker compose logs -f wordpress nginx
docker compose exec -T wordpress php -v
docker compose exec -T wordpress wp --allow-root core version --path=/var/www/html
docker compose exec -T db mariadb-admin ping -uroot -p
docker stats --no-stream
docker system df
```

Ne jamais utiliser `docker compose down -v` en production: `-v` supprime le volume MariaDB.

## 14. Recette apres deploiement

```bash
curl -fsS https://photos.example.com/healthz
curl -fsSI https://photos.example.com
make verify
make provider-status
make production-preflight PUBLIC_URL=https://photos.example.com
```

Verifier manuellement:

1. Home, galerie, detail, inscription, connexion, dashboard et profil.
2. Original prive inaccessible directement.
3. Miniatures chargees dans les listes, original seulement au telechargement autorise.
4. Email de verification recu et headers SPF/DKIM/DMARC valides.
5. Campagne de recette, queue terminee et desinscription fonctionnelle.
6. Lorsque Twilio live est active: OTP recu, usage unique et audit masque.
7. Aucune erreur PHP/5xx dans les logs.

Pour la presentation acceptee sans budget fournisseur, `make verify` et les diagnostics staging constituent la preuve; `production-preflight` reste volontairement rouge jusqu'aux credentials live et au domaine verifie.

## 15. Sauvegardes locales et hors site

Creer puis tester une sauvegarde:

```bash
cd /srv/photovault
make backup
ls -lah backups
make restore-verify BACKUP=photovault-YYYYMMDDTHHMMSSZ
make restore-test BACKUP=photovault-YYYYMMDDTHHMMSSZ
```

Chaque snapshot contient base compressee, medias publics/prives, manifeste et checksums SHA-256.

Pour une copie hors site, installer et configurer rclone interactivement:

```bash
sudo apt install -y rclone
rclone config
rclone copy /srv/photovault/backups remote-chiffre:photovault/backups --checkers 8 --transfers 4
rclone check /srv/photovault/backups remote-chiffre:photovault/backups --one-way
```

Utiliser un remote chiffre, activer le versioning/lifecycle chez le fournisseur et conserver au minimum une copie inaccessible avec les credentials du serveur. Reference: <https://rclone.org/docs/>.

Plan recommande:

- quotidien: 7 sauvegardes;
- hebdomadaire: 5 sauvegardes;
- mensuel: 12 sauvegardes;
- test de restauration: mensuel;
- alerte si aucune nouvelle sauvegarde depuis 26 heures.

Exemple crontab de l'utilisateur `deploy`:

```cron
15 2 * * * cd /srv/photovault && /usr/bin/make backup >> /var/log/photovault-backup.log 2>&1
45 2 * * * /usr/bin/rclone copy /srv/photovault/backups remote-chiffre:photovault/backups >> /var/log/photovault-backup.log 2>&1
```

Verifier que `deploy` peut ecrire le journal, ou remplacer `/var/log/photovault-backup.log` par `/home/deploy/photovault-backup.log`.

## 16. Restauration et reprise apres sinistre

Toujours verifier et tester avant application:

```bash
cd /srv/photovault
make restore-verify BACKUP=BACKUP_NAME
make restore-test BACKUP=BACKUP_NAME
docker compose stop nginx cron wordpress
CONFIRM_RESTORE=photovault MAINTENANCE_CONFIRMED=YES docker compose --profile tools run --rm restore apply BACKUP_NAME
docker compose up -d --wait --wait-timeout 180
make verify
```

Le script cree un snapshot pre-restauration et tente un rollback automatique en cas d'echec. Apres sinistre complet:

1. Recreer le serveur et installer Docker/Caddy.
2. Reinstaller les cinq depots aux SHA documentes.
3. Restaurer `.env` et les secrets depuis le gestionnaire de secrets.
4. Recuperer le snapshot hors site dans `backups/`.
5. Lancer `restore verify`, `restore test`, puis `restore apply`.
6. Rejouer `make deploy`, `make verify` et la recette publique.

## 17. Mise a jour sans derive

Avant toute mise a jour:

```bash
cd /srv/photovault
make backup
make restore-test BACKUP=BACKUP_NAME
git status --short
git -C wp-content/themes/PhotoVault status --short
git -C wp-content/plugins/photovault-core status --short
git -C wp-content/plugins/identity-security-kit status --short
git -C wp-content/plugins/newsletter-campaign-kit status --short
```

Mettre a jour uniquement si les cinq worktrees sont propres:

```bash
git pull --ff-only
git -C wp-content/themes/PhotoVault pull --ff-only
git -C wp-content/plugins/photovault-core pull --ff-only
git -C wp-content/plugins/identity-security-kit pull --ff-only
git -C wp-content/plugins/newsletter-campaign-kit pull --ff-only
make config
make deploy
make cron
make verify
```

Noter avant et apres les cinq SHA. Tester d'abord sur staging pour les mises a jour WordPress, PHP, MariaDB ou schemas.

## 18. Rollback applicatif

Si le deploiement echoue mais que les donnees sont compatibles, revenir aux cinq SHA precedents:

```bash
git checkout ROOT_SHA
git -C wp-content/themes/PhotoVault checkout THEME_SHA
git -C wp-content/plugins/photovault-core checkout CORE_SHA
git -C wp-content/plugins/identity-security-kit checkout IDENTITY_SHA
git -C wp-content/plugins/newsletter-campaign-kit checkout NEWSLETTER_SHA
make deploy
make verify
```

Si une migration de donnees incompatible a ete appliquee, restaurer egalement le snapshot pre-release. Apres analyse, revenir sur `main` avec `git switch main` dans chaque depot; ne jamais utiliser `git reset --hard` sur le serveur sans avoir confirme l'absence de donnees locales utiles.

## 19. Supervision

Surveiller au minimum:

- `https://DOMAIN/healthz` toutes les minutes;
- expiration TLS et DNS;
- codes HTTP 5xx et latence p95;
- etat `healthy` des cinq services;
- espace disque, RAM, charge et inode;
- erreurs PHP/Nginx/MariaDB;
- retard du cron et taille de la queue newsletter;
- echec ou vieillissement des sauvegardes;
- erreurs Twilio/Resend et taux de rejet;
- connexions administrateur et audit securite.

Commandes de diagnostic:

```bash
systemctl status docker caddy --no-pager
journalctl -u docker -u caddy --since today
docker compose ps
docker compose logs --since=30m nginx wordpress db cron
df -h
df -i
free -h
uptime
curl -fsS https://photos.example.com/healthz
```

Configurer une alerte externe vers une adresse qui ne depend pas de PhotoVault. Une supervision hebergee sur le meme serveur ne peut pas signaler sa propre panne totale.

## 20. Rotation des secrets

Ordre recommande:

1. Creer la nouvelle cle chez le fournisseur sans supprimer l'ancienne.
2. Mettre a jour `.env` ou `docker/wp-config-secrets.php`.
3. Executer `make restart`, `make verify`, `make provider-status` et un test cible.
4. Revoquer l'ancienne cle.
5. Consigner date, responsable et resultat sans enregistrer la valeur.

Tourner immediatement un secret present dans une capture, un log, l'historique shell ou Git. Pour les salts WordPress, une rotation deconnecte toutes les sessions, ce qui est normal.

## 21. Checklist de mise en production

- [ ] DNS A/AAAA correct et ports 80/443 ouverts.
- [ ] SSH par cle, root et mot de passe desactives apres verification.
- [ ] Docker officiel, service actif, socket non expose.
- [ ] Cinq depots propres et SHA consignes.
- [ ] `.env` et `wp-config-secrets.php` permissions `600`.
- [ ] `PHOTOVAULT_ENV=production`, debug desactive.
- [ ] Backend lie uniquement a `127.0.0.1`.
- [ ] Caddy valide, HTTPS et headers presents.
- [ ] Home/site URL HTTPS et proxy headers explicitement approuves.
- [ ] Resend SMTP pour `wp_mail`, Resend API pour les campagnes.
- [ ] Twilio desactive ou live; jamais de simulation presentee comme livraison operateur.
- [ ] `make deploy`, `make verify`, `make provider-status` verts.
- [ ] `production-preflight` vert lorsque les fournisseurs live sont finances.
- [ ] Originaux prives inaccessibles directement.
- [ ] Sauvegarde creee, verifiee, restauree et copiee hors site.
- [ ] Supervision externe et alertes activees.
- [ ] Plan de rollback et cinq SHA disponibles.

## 22. Cloture

Pour la presentation actuelle, le projet est accepte termine par le proprietaire avec les providers en mode staging. Pour une ouverture publique commerciale, reprendre uniquement les cases live de la checklist; aucune reecriture applicative n'est necessaire.
