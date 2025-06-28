#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# --- PUID/PGID Logic ---
PUID=${PUID:-33}
PGID=${PGID:-33}
CURRENT_GID=$(getent group www-data | cut -d: -f3)
CURRENT_UID=$(getent passwd www-data | cut -d: -f3)

if [ "$PGID" != "$CURRENT_GID" ]; then
  echo "Changing www-data group ID to $PGID"
  groupmod -o -g "$PGID" www-data
fi

if [ "$PUID" != "$CURRENT_UID" ]; then
  echo "Changing www-data user ID to $PUID"
  usermod -o -u "$PUID" www-data
fi
# --- End PUID/PGID Logic ---

# Create .env file if it doesn't exist
if [ ! -f /var/www/.env ]; then
    echo "Creating .env file from example..."
    cp /var/www/.env.example /var/www/.env
fi

# Create all necessary directories
mkdir -p /var/www/storage/framework/cache/data
mkdir -p /var/www/storage/framework/sessions
mkdir -p /var/www/storage/framework/views
mkdir -p /var/www/storage/logs
mkdir -p /var/www/bootstrap/cache

# Set permissions (now with the correct UID/GID)
chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache

# Run one-time setup if it hasn't been done before
if ! php /var/www/artisan migrate:status --quiet; then
    echo "First run detected. Performing one-time setup..."

    if [ -z "$APP_KEY" ]; then
        php /var/www/artisan key:generate --force
    fi
    
    php /var/www/artisan migrate --force
    php /var/www/artisan passport:keys --force
    
    # This chown is inside the if-block, so it only runs after the keys are created.
    echo "Setting ownership on OAuth keys..."
    chown www-data:www-data /var/www/storage/oauth-*.key
    
    php /var/www/artisan storage:link --force
    php /var/www/artisan config:cache
    php /var/www/artisan route:cache
    php /var/www/artisan view:cache
    php /var/www/artisan instance:actor

    echo "One-time setup complete!"
fi

# <<< Check if the files exist BEFORE trying to chown them. >>>
# This prevents errors on a clean start.
if ls /var/www/storage/oauth-*.key 1> /dev/null 2>&1; then
    chown www-data:www-data /var/www/storage/oauth-*.key
fi

# Execute the command passed to this script (the Docker CMD).
exec "$@"