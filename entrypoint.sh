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