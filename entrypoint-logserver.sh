#!/bin/bash

source /app/bublik/entrypoint-common.sh

setup_umask

fix_permissions_watcher() {
    echo "Starting inotify permission watcher for /home/te-logs/logs..."
    echo "Fixing permissions on existing files..."
    find /home/te-logs/logs -type d -exec chmod 2775 {} \; 2>/dev/null
    find /home/te-logs/logs -type f -exec chmod 664 {} \; 2>/dev/null
    chgrp -R www-data /home/te-logs/logs 2>/dev/null

    inotifywait -m -r -e create,moved_to /home/te-logs/logs --format '%w%f' 2>/dev/null | while read FILE
    do
        if [ -f "$FILE" ]; then
            chmod 664 "$FILE" 2>/dev/null
            chgrp www-data "$FILE" 2>/dev/null
            echo "Fixed permissions for file: $FILE"
        elif [ -d "$FILE" ]; then
            chmod 2775 "$FILE" 2>/dev/null
            chgrp www-data "$FILE" 2>/dev/null
            echo "Fixed permissions for directory: $FILE"
        fi
    done
}

process_templates() {
    echo "Processing templates..."

    PORT_SUFFIX=""
    EXT_PORT_SUFFIX=""
    if [ "${BUBLIK_DOCKER_PROXY_PORT}" != "80" ]; then
        PORT_SUFFIX=":${BUBLIK_DOCKER_PROXY_PORT}"
    fi

    # Hereby we try to resolve the problem if the truly external port is
    # different from the one internally assigned to docker proxy.
    if [ "${BUBLIK_DOCKER_PROXY_EXT_PORT}" == "proto_default" ] ; then
        # If the port is set to "proto_default", we don't append it to the url
        # believing that the port would better be derived from the protocol
        # (443 for https, 80 for http)
        EXT_PORT_SUFFIX=""
    elif [ "${BUBLIK_DOCKER_PROXY_EXT_PORT}" != "" ] ; then
        # The port is set - use it
        EXT_PORT_SUFFIX=":${BUBLIK_DOCKER_PROXY_EXT_PORT}"
    else
        # Otherwise, it is the same as normal PORT_SUFFIX. Fallback value.
        EXT_PORT_SUFFIX="${PORT_SUFFIX}"
    fi

    cp /app/te-templates/te-logs-error404.template /home/te-logs/cgi-bin/te-logs-error404
    cp /app/te-templates/te-logs-index.template /home/te-logs/cgi-bin/te-logs-index
    cp /app/te-templates/publish-logs-unpack.sh /home/te-logs/bin/
    cp /app/te-templates/publish-incoming-logs.template /home/te-logs/bin/publish-incoming-logs
    cp /app/te-templates/apache2-te-log-server.conf.template /etc/apache2/conf-available/te-logs.conf

    echo '        ScriptAlias ${URL_PREFIX}/te-logs-cgi-bin/ /home/te-logs/cgi-bin/' >> /etc/apache2/conf-available/te-logs.conf
    echo '        <Directory "/home/te-logs/cgi-bin/">' >> /etc/apache2/conf-available/te-logs.conf
    echo '            AllowOverride None' >> /etc/apache2/conf-available/te-logs.conf
    echo '            Options +ExecCGI' >> /etc/apache2/conf-available/te-logs.conf
    echo '            SetHandler cgi-script' >> /etc/apache2/conf-available/te-logs.conf
    echo '            Require all granted' >> /etc/apache2/conf-available/te-logs.conf
    echo '        </Directory>' >> /etc/apache2/conf-available/te-logs.conf

    echo '        <DirectoryMatch "^@@LOGS_DIR@@/.+">' >> /etc/apache2/conf-available/te-logs.conf && \
    echo '            Options +FollowSymLinks' >> /etc/apache2/conf-available/te-logs.conf && \
    echo '            Require all granted' >> /etc/apache2/conf-available/te-logs.conf && \
    echo '            ErrorDocument 404 ${URL_PREFIX}/te-logs-cgi-bin/te-logs-error404' >> /etc/apache2/conf-available/te-logs.conf && \
    echo '            DirectoryIndex index.html ${URL_PREFIX}/te-logs-cgi-bin/te-logs-index' >> /etc/apache2/conf-available/te-logs.conf && \
    echo '        </DirectoryMatch>' >> /etc/apache2/conf-available/te-logs.conf

    sed -i "/export SHARED_URL/a export URL_PREFIX=\"$URL_PREFIX\"" /home/te-logs/cgi-bin/te-logs-error404
    sed -i "/tools_bin=/i export URL_PREFIX=\"$URL_PREFIX\"" /home/te-logs/cgi-bin/te-logs-index

    chmod +x /home/te-logs/cgi-bin/te-logs-error404
    chmod +x /home/te-logs/cgi-bin/te-logs-index
    chmod +x /home/te-logs/bin/publish-incoming-logs
    chmod +x /home/te-logs/bin/publish-logs-unpack.sh

    # publish-incoming-logs is run through "docker exec", that is as root.
    # Directories root makes are root-owned and 750 until the permission
    # watcher reaches them, and until then nothing else can write into them:
    # neither Apache generating pages nor the django container unpacking an
    # upload. Drop to the storage owner first; the www-data group keeps the
    # tar removable from incoming/, which is group-writable.
    cat > /tmp/publish-as-owner <<'EOF'
if [ "$(id -u)" -eq 0 ]; then
    exec gosu "${HOST_UID:-1000}:www-data" "$0" "$@"
fi
EOF
    sed -i '1r /tmp/publish-as-owner' /home/te-logs/bin/publish-incoming-logs
    rm -f /tmp/publish-as-owner

    sed -i \
        -e 's|/logs/\* )|${URL_PREFIX}/logs/\* )|' \
        -e 's|root_dir_uri="/logs"|root_dir_uri="${URL_PREFIX}/logs"|' \
        -e 's|/te-logs-cgi-bin/|${URL_PREFIX}/te-logs-cgi-bin/|g' \
    /app/te/build/inst/default/bin/te-logs-error404.sh

    sed -i \
        -e 's|/te-logs-cgi-bin/|${URL_PREFIX}/te-logs-cgi-bin/|g' \
    /app/te/build/inst/default/bin/te-logs-index.sh

    sed -i 's/--negotiate//' /home/te-logs/bin/publish-logs-unpack.sh

    sed -i \
        -e "s,@@TE_INSTALL@@,/app/te/build/inst,g" \
        -e "s,/srv/logs,/home/te-logs/logs,g" \
        -e "s,root_dir=\"/srv/logs\",root_dir=\"/home/te-logs/logs\",g" \
        -e "s,@@BUBLIK_URL@@,${BUBLIK_FQDN}${EXT_PORT_SUFFIX}${URL_PREFIX},g" \
        -e "s,@@LOGS_URL@@,${BUBLIK_FQDN}${EXT_PORT_SUFFIX}${URL_PREFIX}/logs,g" \
        -e "s,@@LOGS_DIR@@,/home/te-logs/logs,g" \
        -e "s,@@LOGS_INCOMING@@,/home/te-logs/incoming,g" \
        -e "s,@@LOGS_BAD@@,/home/te-logs/bad,g" \
        -e "s,@@LOGS_SHARED_URL@@,${URL_PREFIX}/static_te_html,g" \
        /home/te-logs/cgi-bin/te-logs-index \
        /home/te-logs/cgi-bin/te-logs-error404 \
        /app/te/build/inst/default/bin/te-logs-error404.sh \
        /app/te/build/inst/default/bin/te-logs-index.sh \
        /home/te-logs/bin/publish-incoming-logs

    sed -i \
        -e "s,@@LOGS_CGI_BIN@@,/home/te-logs/cgi-bin,g" \
        -e "s,@@LOGS_DIR@@,/home/te-logs/logs,g" \
        -e "s,@@LOGS_URL_PATH@@,${URL_PREFIX}/logs,g" \
        /etc/apache2/conf-available/te-logs.conf

    echo "Templates processed successfully."
}

echo "Setting up required directories..."
ensure_directory "/home/te-logs/logs"
ensure_directory "/home/te-logs/incoming"
ensure_directory "/home/te-logs/bad"
ensure_directory "/home/te-logs/cgi-bin"
ensure_directory "/home/te-logs/bin"

setup_permissions "/home/te-logs/incoming" "/home/te-logs/bad" "/home/te-logs/cgi-bin" "/home/te-logs/bin"
# Apache runs as HOST_UID (setup_service_user below) and generates log pages into
# the run directories; the django container, also HOST_UID, unpacks uploaded
# tarballs into them. So the storage is owned by HOST_UID, not www-data, while
# the group stays www-data: hosts publishing over scp as a www-data member, and
# the setgid directories, keep working as before.
echo "Setting up permissions for /home/te-logs/logs"
chown -R "${HOST_UID:-1000}:www-data" /home/te-logs/logs
chmod -R 2775 /home/te-logs/logs
find /home/te-logs/logs -type f -exec chmod 664 {} \; 2>/dev/null || true

process_templates

setup_service_user "APACHE_RUN" "/etc/apache2/envvars"

echo "Configuring Apache to send logs to stdout/stderr"
sed -i 's|ErrorLog ${APACHE_LOG_DIR}/error.log|ErrorLog /dev/stderr|' /etc/apache2/apache2.conf
sed -i 's|CustomLog ${APACHE_LOG_DIR}/access.log combined|CustomLog /dev/stdout combined|' /etc/apache2/sites-available/000-default.conf

a2enmod cgi
a2enconf te-logs

sed -i \
    -e 's/Listen 80/Listen ${BUBLIK_DOCKER_TE_LOG_SERVER_PORT}/' \
    /etc/apache2/ports.conf

fix_permissions_watcher &

echo "Starting Apache"
exec apache2ctl -D FOREGROUND
