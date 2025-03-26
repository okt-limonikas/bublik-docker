#!/bin/bash

source /app/bublik/entrypoint-common.sh

setup_umask

process_templates() {
    echo "Processing templates..."
    
    PORT_SUFFIX=""
    if [ "${BUBLIK_DOCKER_PROXY_PORT}" != "80" ]; then
        PORT_SUFFIX=":${BUBLIK_DOCKER_PROXY_PORT}"
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
        -e "s,@@BUBLIK_URL@@,${BUBLIK_FQDN}${PORT_SUFFIX}${URL_PREFIX},g" \
        -e "s,@@LOGS_URL@@,${BUBLIK_FQDN}${PORT_SUFFIX}${URL_PREFIX}/logs,g" \
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

setup_permissions "/home/te-logs/logs" "/home/te-logs/incoming" "/home/te-logs/bad" "/home/te-logs/cgi-bin" "/home/te-logs/bin"

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

echo "Starting Apache"
exec apache2ctl -D FOREGROUND