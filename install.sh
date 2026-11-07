#!/usr/bin/env bash
# xuitheme — custom (Nexino VPN) subscription page for 3x-ui
# Install:   bash <(curl -Ls https://raw.githubusercontent.com/best4521/xuitheme/main/install.sh)
# Update:    same command again
# Uninstall: bash <(curl -Ls https://raw.githubusercontent.com/best4521/xuitheme/main/install.sh) uninstall
#
# Optional env: PORT=2096 (public sub port)  INTERNAL_PORT=2097  LOGO_URL=https://.../logo.png
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/best4521/xuitheme/main}"
DB=/etc/x-ui/x-ui.db
WEB=/var/www/xuitheme
NGX=/etc/nginx/conf.d/xuitheme.conf
STATE=/etc/xuitheme.env
INTERNAL_PORT="${INTERNAL_PORT:-2097}"

G='\033[1;32m'; R='\033[1;31m'; Y='\033[1;33m'; N='\033[0m'
ok(){ echo -e "${G}[✓]${N} $*"; }
info(){ echo -e "${Y}[*]${N} $*"; }
die(){ echo -e "${R}[x]${N} $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root."
[ -f "$DB" ] || die "3x-ui database not found ($DB). Is 3x-ui installed?"

pkg_install(){
  if command -v apt-get >/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null
  elif command -v dnf >/dev/null; then dnf install -y -q "$@" >/dev/null
  elif command -v yum >/dev/null; then yum install -y -q "$@" >/dev/null
  else die "No supported package manager (apt/dnf/yum)."; fi
}

dbget(){ sqlite3 "$DB" "SELECT value FROM settings WHERE key='$1' LIMIT 1;" 2>/dev/null || true; }
dbset(){
  local k="$1" v="${2//\'/\'\'}"
  sqlite3 "$DB" "INSERT INTO settings(key,value) SELECT '$k','$v' WHERE NOT EXISTS (SELECT 1 FROM settings WHERE key='$k'); UPDATE settings SET value='$v' WHERE key='$k';"
}
restart_xui(){
  if systemctl list-unit-files | grep -q '^x-ui'; then systemctl restart x-ui; else x-ui restart >/dev/null 2>&1 || true; fi
}
port_busy(){ ss -ltnH "( sport = :$1 )" 2>/dev/null | grep -q .; }

uninstall(){
  [ -f "$STATE" ] || die "xuitheme is not installed (no $STATE)."
  # shellcheck disable=SC1090
  . "$STATE"
  info "Restoring 3x-ui subscription settings..."
  command -v sqlite3 >/dev/null || pkg_install sqlite3
  dbset subListen "$OLD_LISTEN"
  dbset subPort "$PUBLIC_PORT"
  dbset subCertFile "$CERT"
  dbset subKeyFile "$KEY"
  dbset subURI "$OLD_URI"
  rm -f "$NGX" /etc/cron.d/xuitheme
  rm -rf "$WEB"
  systemctl reload nginx 2>/dev/null || systemctl stop nginx 2>/dev/null || true
  # nginx must release the port before x-ui takes it back
  if ! ls /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/* >/dev/null 2>&1; then systemctl stop nginx || true; fi
  sleep 1
  restart_xui
  rm -f "$STATE"
  ok "Uninstalled. 3x-ui serves its default subscription page on port $PUBLIC_PORT again."
  exit 0
}

[ "${1:-}" = "uninstall" ] && uninstall

echo -e "${G}=== xuitheme installer ===${N}"
info "Installing dependencies (nginx, sqlite3, curl)..."
pkg_install nginx sqlite3 curl openssl
ok "Dependencies ready."

# ---------- read current config ----------
if [ -f "$STATE" ]; then
  info "Existing install found — updating."
  # shellcheck disable=SC1090
  . "$STATE"
  PUBLIC_PORT="${PORT:-$PUBLIC_PORT}"
else
  cur_port="$(dbget subPort)"
  cur_listen="$(dbget subListen)"
  if [ "$cur_listen" = "127.0.0.1" ] && [ "$cur_port" = "$INTERNAL_PORT" ]; then
    die "Sub already points to 127.0.0.1:$INTERNAL_PORT but $STATE is missing. Set it back in the panel (Sub port, cert) and re-run."
  fi
  PUBLIC_PORT="${PORT:-${cur_port:-2096}}"
  CERT="$(dbget subCertFile)"; KEY="$(dbget subKeyFile)"
  if [ -z "$CERT" ] || [ ! -f "$CERT" ]; then CERT="$(dbget webCertFile)"; KEY="$(dbget webKeyFile)"; fi
  DOMAIN="$(dbget subDomain)"
  OLD_LISTEN="$cur_listen"
  OLD_URI="$(dbget subURI)"
fi
[ -n "$PUBLIC_PORT" ] || PUBLIC_PORT=2096
[ "$PUBLIC_PORT" != "$INTERNAL_PORT" ] || die "PORT and INTERNAL_PORT must differ."

SUBPATH="$(dbget subPath)"; SUBPATH="${SUBPATH:-/sub/}"
[[ "$SUBPATH" == /* ]] || SUBPATH="/$SUBPATH"
[[ "$SUBPATH" == */ ]] || SUBPATH="$SUBPATH/"

SSL=0
if [ -n "${CERT:-}" ] && [ -f "$CERT" ] && [ -n "${KEY:-}" ] && [ -f "$KEY" ]; then
  SSL=1
  if [ -z "${DOMAIN:-}" ]; then
    DOMAIN="$(openssl x509 -in "$CERT" -noout -subject 2>/dev/null | sed -n 's/.*CN *= *\([^,/]*\).*/\1/p')"
  fi
else
  CERT=""; KEY=""
  info "No TLS certificate found in 3x-ui settings — page will be served over plain HTTP."
fi
SCHEME=$([ "$SSL" = 1 ] && echo https || echo http)

info "Public port: $PUBLIC_PORT  | internal x-ui sub: 127.0.0.1:$INTERNAL_PORT"
info "Sub path: $SUBPATH  | domain: ${DOMAIN:-<none>}  | TLS: $([ $SSL = 1 ] && echo yes || echo no)"

# ---------- backup ----------
mkdir -p /root/backups
BK="/root/backups/x-ui.db.xuitheme.$(date +%F-%H%M%S)"
cp "$DB" "$BK"; ok "Database backup: $BK"

# ---------- assets ----------
info "Downloading page assets..."
mkdir -p "$WEB"
for f in index.html logo.png qrious.min.js Vazirmatn.woff2; do
  curl -fsSL "$REPO_RAW/assets/$f" -o "$WEB/$f.tmp" || die "Download failed: $f"
  mv -f "$WEB/$f.tmp" "$WEB/$f"
done
if [ -n "${LOGO_URL:-}" ]; then curl -fsSL "$LOGO_URL" -o "$WEB/logo.png" && ok "Custom logo applied."; fi
ok "Assets installed in $WEB"

# ---------- nginx ----------
rm -f /etc/nginx/conf.d/subpage.conf            # legacy manual install
[ -L /etc/nginx/sites-enabled/default ] && rm -f /etc/nginx/sites-enabled/default   # frees :80 for acme.sh
V6=""; [ -f /proc/net/if_inet6 ] && V6=1
if [ "$SSL" = 1 ]; then
  L4="listen $PUBLIC_PORT ssl http2;"; L6="listen [::]:$PUBLIC_PORT ssl http2;"
  SSLBLOCK="ssl_certificate     $CERT;
    ssl_certificate_key $KEY;
    ssl_protocols TLSv1.2 TLSv1.3;"
else
  L4="listen $PUBLIC_PORT;"; L6="listen [::]:$PUBLIC_PORT;"; SSLBLOCK=""
fi
[ -n "$V6" ] || L6=""

cat > "$NGX" <<NG
# managed by xuitheme — https://github.com/best4521/xuitheme
map \$http_accept \$xt_browser { default 0; "~*text/html" 1; }
map "\$xt_browser\$http_x_raw" \$xt_page { default 0; "1" 1; }
server {
    $L4
    $L6
    server_name _;
    $SSLBLOCK

    location /_sp/ { alias $WEB/; expires 7d; }
    location = /__xtpage { internal; default_type text/html; alias $WEB/index.html; add_header Cache-Control "no-store"; }

    location ~ ^${SUBPATH}[^/]+/?\$ {
        if (\$xt_page) { rewrite ^ /__xtpage last; }
        proxy_pass http://127.0.0.1:$INTERNAL_PORT;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $SCHEME;
        proxy_hide_header Profile-Web-Page-Url;
        add_header Profile-Web-Page-Url "$SCHEME://\$http_host\$uri" always;
    }
    location / {
        proxy_pass http://127.0.0.1:$INTERNAL_PORT;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $SCHEME;
    }
}
NG
nginx -t >/dev/null 2>&1 || { nginx -t; rm -f "$NGX"; die "nginx config test failed — nothing changed in 3x-ui."; }
ok "nginx config written: $NGX"

# ---------- 3x-ui ----------
info "Moving 3x-ui subscription server to 127.0.0.1:$INTERNAL_PORT ..."
dbset subEnable true
dbset subListen 127.0.0.1
dbset subPort "$INTERNAL_PORT"
dbset subCertFile ""
dbset subKeyFile ""
if [ -n "${DOMAIN:-}" ]; then dbset subURI "$SCHEME://$DOMAIN:$PUBLIC_PORT$SUBPATH"; fi

cat > "$STATE" <<ST
PUBLIC_PORT='$PUBLIC_PORT'
CERT='$CERT'
KEY='$KEY'
DOMAIN='${DOMAIN:-}'
OLD_LISTEN='${OLD_LISTEN:-}'
OLD_URI='${OLD_URI:-}'
ST

restart_xui
for i in $(seq 1 20); do port_busy "$INTERNAL_PORT" && break; sleep 1; done
port_busy "$INTERNAL_PORT" || die "3x-ui did not start its sub server on $INTERNAL_PORT. Check: journalctl -u x-ui -n 50"
for i in $(seq 1 10); do ss -ltnpH "( sport = :$PUBLIC_PORT )" | grep -qv nginx || break; sleep 1; done
systemctl enable nginx >/dev/null 2>&1 || true
systemctl restart nginx
ok "3x-ui restarted, nginx serving port $PUBLIC_PORT."

echo "30 5 * * * root systemctl reload nginx >/dev/null 2>&1" > /etc/cron.d/xuitheme   # pick up renewed certs

echo
ok "Done! Open any client's subscription link in a browser:"
echo -e "   ${G}$SCHEME://${DOMAIN:-<server>}:$PUBLIC_PORT${SUBPATH}<subId>${N}"
echo "   VPN apps keep receiving the normal subscription — links stay the same."
echo -e "   ${Y}Note:${N} don't change the Sub port/cert in the 3x-ui panel (keep 127.0.0.1:$INTERNAL_PORT)."
