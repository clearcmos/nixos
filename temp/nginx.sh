#!/bin/bash

distro=$(lsb_release -is)
if [[ "$distro" != "Debian" && "$distro" != "Ubuntu" ]]; then
    echo "This script is intended only for Debian or Ubuntu systems."
    exit 1
fi

echo "Do you already have your MaxMind Account ID and License Key? (y/n)"
read -r have_credentials

if [[ "$have_credentials" != "y" ]]; then
    echo "Please go to https://www.maxmind.com/ to retrieve your required information or create an account."
    echo "Press enter to continue the script once you have your Account ID and License Key..."
    read -r
fi

EDITION_ID="GeoLite2-ASN GeoLite2-City GeoLite2-Country"
CONFIG_FILE="/etc/GeoIP.conf"

packages="curl jq libnginx-mod-http-geoip2 nginx wget"
for package in $packages; do
    if ! dpkg -l | grep -qw $package; then
        sudo apt-get install -y $package
    fi
done

if ! dpkg -l | grep -qw geoipupdate; then
    GITHUB_API_URL="https://api.github.com/repos/maxmind/geoipupdate/releases/latest"
    DOWNLOAD_URL=$(curl -s $GITHUB_API_URL | jq -r '.assets[] | select(.name | endswith("_linux_amd64.deb")) | .browser_download_url')

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "Failed to find a download URL. Exiting."
        exit 1
    fi

    echo "Downloading geoipupdate from $DOWNLOAD_URL"
    wget "$DOWNLOAD_URL" -O geoipupdate.deb

    if [ $? -ne 0 ]; then
        echo "Download failed. Exiting."
        rm -f geoipupdate.deb
        exit 1
    fi

    echo "Installing geoipupdate"
    sudo dpkg -i geoipupdate.deb || sudo apt-get install -f
    rm geoipupdate.deb
    echo "Installation complete."
fi

function configureGeoIPAndUpdate() {
    sudo bash -c "cat > $CONFIG_FILE <<EOF
AccountID $1
LicenseKey $2
EditionIDs $EDITION_ID
EOF"

    if ! sudo geoipupdate; then
        echo "Error retrieving updates: Your account ID or license key could not be authenticated."
        return 1
    fi

    return 0
}

function promptForMaxMindCredentials() {
    while :; do
        echo "Please enter your MaxMind credentials."
        read -p "Enter your MaxMind Account ID: " ACCOUNT_ID
        read -p "Enter your MaxMind License Key: " LICENSE_KEY

        if configureGeoIPAndUpdate "$ACCOUNT_ID" "$LICENSE_KEY"; then
            echo "geoipupdate configuration complete."
            break
        else
            echo "Error retrieving updates: Your account ID or license key could not be authenticated."
        fi

        echo "Would you like to try re-entering your MaxMind credentials? (y/n)"
        read -r retry
        if [[ "$retry" != "y" ]]; then
            echo "Exiting due to unsuccessful GeoIP database update."
            exit 1
        fi
    done
}

promptForMaxMindCredentials

ROUTER_IP=$(ip route | awk '/^default via/ {print $3}')
echo "Detected router IP is $ROUTER_IP. Is this correct? (y/n)"
read -r response
if [[ "$response" != "y" ]]; then
    read -p "Enter the correct router IP: " ROUTER_IP
fi

CRON_JOB="0 3 * * 1 /usr/bin/geoipupdate"
(crontab -l 2>/dev/null | grep -q "$CRON_JOB") || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

declare -A country_codes=(
    [1]="Canada (CA)"
    [2]="Tunisia (TN)"
    [3]="United States (US)"
)

echo "Please select the country codes for IPs that should be whitelisted. You can select multiple countries by inputting numbers followed by spaces."
for key in $(echo "${!country_codes[@]}" | tr ' ' '\n' | sort -n | tr '\n' ' '); do
    echo "$key. ${country_codes[$key]}"
done

echo "Enter your selections (e.g., '1 2'):"
read -r selection

IFS=' ' read -ra selected_codes <<< "$selection"
whitelist=()
for index in "${selected_codes[@]}"; do
    code="${country_codes[$index]}"
    code=${code##*\(}
    code=${code%%)*}
    whitelist+=("$code")
done

echo "Configuring Nginx to whitelist: ${whitelist[@]}"

whitelist_formatted=$(printf "        %s yes;\n" "${whitelist[@]}")

NGINX_CONF="/etc/nginx/nginx.conf"

whitelist_formatted=$(printf "\t%s yes;\n" "${whitelist[@]}")

{
    echo "user www-data;"
    echo "worker_processes auto;"
    echo "pid /run/nginx.pid;"
    echo "error_log /var/log/nginx/error.log;"
    echo "load_module /usr/lib/nginx/modules/ngx_http_geoip2_module.so;"
    echo ""
    echo "events {"
    echo "    worker_connections 768;"
    echo "}"
    echo ""
    echo "http {"
    echo "    sendfile on;"
    echo "    tcp_nopush on;"
    echo "    types_hash_max_size 2048;"
    echo "    server_tokens off;"
    echo ""
    echo "    include /etc/nginx/mime.types;"
    echo "    default_type application/octet-stream;"
    echo ""
    echo "    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;"
    echo "    ssl_prefer_server_ciphers on;"
    echo ""
    echo "    log_format geoip_log '\$remote_addr - \$remote_user [\$time_local] '"
    echo "                         '\"\$request\" \$status \$body_bytes_sent '"
    echo "                         '\"\$http_referer\" \"\$http_user_agent\" '"
    echo "                         '\"\$geoip2_data_country_code\"';"
    echo ""
    echo "    access_log /var/log/nginx/access.log geoip_log;"
    echo ""
    echo "    gzip on;"
    echo ""
    echo "    geoip2 /usr/share/GeoIP/GeoLite2-Country.mmdb {"
    echo "        \$geoip2_data_country_code country iso_code;"
    echo "    }"
    echo ""
    echo "    map \$geoip2_data_country_code \$allowed_country {"
    echo "        default no;"
    echo -e "$whitelist_formatted"
    echo "    }"
    echo ""
    echo "    geo \$exclusions {"
    echo "        default 0;"
    echo "        $ROUTER_IP 1;"
    echo "    }"
    echo ""
    echo "    limit_req_zone \$binary_remote_addr zone=mylimit:10m rate=10r/s;"
    echo ""
    echo "    server {"
    echo "        location / {"
    echo "            limit_req zone=mylimit burst=20 nodelay;"
    echo "        }"
    echo "    }"
    echo ""
    echo "    include /etc/nginx/conf.d/*.conf;"
    echo "    include /etc/nginx/sites-enabled/*;"
    echo "}"
} | sudo tee $NGINX_CONF > /dev/null

echo "Nginx configuration updated."

if sudo nginx -t; then
    echo "Nginx configuration syntax is OK. Restarting Nginx."
    sudo systemctl restart nginx
else
    echo "Error in Nginx configuration syntax. Not restarting Nginx."
fi
