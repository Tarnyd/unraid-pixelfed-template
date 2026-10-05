#!/bin/bash
set -e

# --- PUID/PGID Logic ---
PUID=${PUID:-99}
PGID=${PGID:-100}
CURRENT_GID=$(getent group www-data | cut -d: -f3)
CURRENT_UID=$(getent passwd www-data | cut -d: -f3)

if [ "$PGID" != "$CURRENT_GID" ]; then
  echo "Updating www-data group ID to $PGID"
  groupmod -o -g "$PGID" www-data
fi

if [ "$PUID" != "$CURRENT_UID" ]; then
  echo "Updating www-data user ID to $PUID"
  usermod -o -u "$PUID" www-data
fi

# Create .env file from example if it does not exist
if [ ! -f /var/www/.env ]; then
    echo "Initializing .env file..."
    cp /var/www/.env.example /var/www/.env
fi

ENV_FILE=/var/www/.env

# --- In-place .env migrations (v0.12.x -> v0.14.x) ---
# Idempotent: safe to run on every boot, only acts on legacy values.

# Laravel 13 renamed CACHE_DRIVER to CACHE_STORE (old name only works as fallback)
if grep -q '^CACHE_DRIVER=' "$ENV_FILE" && ! grep -q '^CACHE_STORE=' "$ENV_FILE"; then
    echo "Migrating .env: CACHE_DRIVER -> CACHE_STORE"
    sed -i 's/^CACHE_DRIVER=/CACHE_STORE=/' "$ENV_FILE"
fi

# v0.12.12 renamed the hCaptcha env vars
if grep -q '^CAPTCHA_SITEKEY=' "$ENV_FILE" && ! grep -q '^CAPTCHA_H_SITEKEY=' "$ENV_FILE"; then
    echo "Migrating .env: CAPTCHA_SITEKEY -> CAPTCHA_H_SITEKEY"
    sed -i 's/^CAPTCHA_SITEKEY=/CAPTCHA_H_SITEKEY=/' "$ENV_FILE"
fi
if grep -q '^CAPTCHA_SECRET=' "$ENV_FILE" && ! grep -q '^CAPTCHA_H_SECRET=' "$ENV_FILE"; then
    echo "Migrating .env: CAPTCHA_SECRET -> CAPTCHA_H_SECRET"
    sed -i 's/^CAPTCHA_SECRET=/CAPTCHA_H_SECRET=/' "$ENV_FILE"
fi

# v0.12.12 switched APP_LOCALE from 2-letter codes to BCP-47 tags.
# The app still maps legacy codes at runtime, but that mapping is scheduled
# for removal in a future release, so normalize the .env now.
LOCALE=$(grep '^APP_LOCALE=' "$ENV_FILE" | head -n1 | sed -E 's/^APP_LOCALE="?([^"]*)".*/\1/')
case "${LOCALE,,}" in
    af) NEW_LOCALE="af-ZA" ;;
    ar) NEW_LOCALE="ar-SA" ;;
    bn) NEW_LOCALE="bn-BD" ;;
    bs) NEW_LOCALE="bs-BA" ;;
    ca) NEW_LOCALE="ca-ES" ;;
    cs) NEW_LOCALE="cs-CZ" ;;
    cy) NEW_LOCALE="cy-GB" ;;
    da) NEW_LOCALE="da-DK" ;;
    de) NEW_LOCALE="de-DE" ;;
    el) NEW_LOCALE="el-GR" ;;
    en) NEW_LOCALE="en-US" ;;
    eo) NEW_LOCALE="eo-UY" ;;
    es) NEW_LOCALE="es-ES" ;;
    eu) NEW_LOCALE="eu-ES" ;;
    fa) NEW_LOCALE="fa-IR" ;;
    fi) NEW_LOCALE="fi-FI" ;;
    fr) NEW_LOCALE="fr-FR" ;;
    gd) NEW_LOCALE="gd-GB" ;;
    gl) NEW_LOCALE="gl-ES" ;;
    he) NEW_LOCALE="he-IL" ;;
    hi) NEW_LOCALE="hi-IN" ;;
    hr) NEW_LOCALE="hr-HR" ;;
    hu) NEW_LOCALE="hu-HU" ;;
    id) NEW_LOCALE="id-ID" ;;
    it) NEW_LOCALE="it-IT" ;;
    ja) NEW_LOCALE="ja-JP" ;;
    ko) NEW_LOCALE="ko-KR" ;;
    me) NEW_LOCALE="me-ME" ;;
    mk) NEW_LOCALE="mk-MK" ;;
    ms) NEW_LOCALE="ms-MY" ;;
    nl) NEW_LOCALE="nl-NL" ;;
    no) NEW_LOCALE="no-NO" ;;
    oc) NEW_LOCALE="oc-FR" ;;
    pl) NEW_LOCALE="pl-PL" ;;
    pt) NEW_LOCALE="pt-PT" ;;
    ro) NEW_LOCALE="ro-RO" ;;
    ru) NEW_LOCALE="ru-RU" ;;
    sk) NEW_LOCALE="sk-SK" ;;
    sr) NEW_LOCALE="sr-CS" ;;
    sv) NEW_LOCALE="sv-SE" ;;
    th) NEW_LOCALE="th-TH" ;;
    tr) NEW_LOCALE="tr-TR" ;;
    uk) NEW_LOCALE="uk-UA" ;;
    vi) NEW_LOCALE="vi-VN" ;;
    zh-cn) NEW_LOCALE="zh-CN" ;;
    zh-tw) NEW_LOCALE="zh-TW" ;;
    *) NEW_LOCALE="" ;;
esac
if [ -n "$NEW_LOCALE" ]; then
    echo "Migrating .env: APP_LOCALE ${LOCALE} -> ${NEW_LOCALE}"
    sed -i "s/^APP_LOCALE=.*/APP_LOCALE=\"${NEW_LOCALE}\"/" "$ENV_FILE"
fi

# Ensure required directory structure exists
mkdir -p /var/www/storage/framework/{cache/data,sessions,views}
mkdir -p /var/www/storage/logs
mkdir -p /var/www/bootstrap/cache

# Set ownership for storage and cache directories
chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache

# --- Maintenance and Update Tasks ---
echo "Running automated maintenance tasks..."

# Generate APP_KEY if it is missing
if ! grep -q "APP_KEY=base64" /var/www/.env; then
    echo "Generating application key..."
    php /var/www/artisan key:generate --force
fi

# Run database migrations (safe to run on every boot)
echo "Checking for database migrations..."
php /var/www/artisan migrate --force

# Generate Passport keys if they are missing
if [ ! -f /var/www/storage/oauth-private.key ]; then
    echo "Generating OAuth keys..."
    php /var/www/artisan passport:keys --force
    chown www-data:www-data /var/www/storage/oauth-*.key
fi

# Ensure storage symbolic link exists
if [ ! -L /var/www/public/storage ]; then
    echo "Creating storage symbolic link..."
    php /var/www/artisan storage:link --force
fi

# Clear application cache to prevent version mismatch issues
echo "Clearing application cache..."
php /var/www/artisan config:clear
php /var/www/artisan route:clear
php /var/www/artisan view:clear

# Refresh instance actor (required for federation stability)
php /var/www/artisan instance:actor

echo "Initialization complete. Starting services..."

# Final permission check for generated OAuth keys
if ls /var/www/storage/oauth-*.key 1> /dev/null 2>&1; then
    chown www-data:www-data /var/www/storage/oauth-*.key
fi

# Execute the container command
exec "$@"
