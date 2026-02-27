#!/bin/bash

# ============================================================
#  install.sh — Instalador de udpxy (Optinetx)
#  Repositorio: https://github.com/greathy19/optinev
# ============================================================

set -e

REPO_RAW="https://raw.githubusercontent.com/greathy19/optinev/main"
ZIP_NAME="udpxy-Optinetx.zip"
INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="udpxy"
UDPXY_PORT="7782"         # Puerto udpxy
UDPXY_MCAST_IF="eth0"    # Interfaz de red para multicast, ajusta según tu sistema
UDPXY_CLIENTS="120"      # Máximo de clientes simultáneos

# ============================================================
# Colores
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()    { echo -e "${GREEN}[✔]${NC} $1"; }
warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
error()  { echo -e "${RED}[✘]${NC} $1"; exit 1; }

# ============================================================
# 1. Verificar que se ejecuta como root
# ============================================================
if [ "$EUID" -ne 0 ]; then
    error "Este script debe ejecutarse como root. Usa: sudo bash install.sh"
fi

echo ""
echo "=============================================="
echo "   Instalador udpxy - Optinetx"
echo "=============================================="
echo ""

# ============================================================
# 2. Instalar dependencias del sistema
# ============================================================
log "Instalando dependencias del sistema..."

if command -v apt-get &>/dev/null; then
    apt-get update -qq
    apt-get install -y wget unzip build-essential curl net-tools &>/dev/null
elif command -v yum &>/dev/null; then
    yum install -y wget unzip gcc make curl net-tools &>/dev/null
elif command -v apk &>/dev/null; then
    apk add --no-cache wget unzip build-base curl net-tools &>/dev/null
elif command -v opkg &>/dev/null; then
    opkg update &>/dev/null
    opkg install wget unzip &>/dev/null
else
    warn "Gestor de paquetes no reconocido. Asegúrate de tener: wget, unzip, gcc, make"
fi

log "Dependencias instaladas."

# ============================================================
# 3. Descargar el ZIP desde el repositorio
# ============================================================
WORK_DIR=$(mktemp -d)
cd "$WORK_DIR"

log "Descargando $ZIP_NAME desde GitHub..."
wget -q --show-progress "$REPO_RAW/$ZIP_NAME" -O "$ZIP_NAME" || \
    error "No se pudo descargar $ZIP_NAME. Verifica tu conexión."

log "Archivo descargado en $WORK_DIR/$ZIP_NAME"

# ============================================================
# 4. Descomprimir
# ============================================================
log "Descomprimiendo..."
unzip -q "$ZIP_NAME" -d udpxy_src

# Entrar al directorio descomprimido (puede tener subcarpeta)
SRC_DIR=$(find udpxy_src -maxdepth 2 -name "Makefile" | head -1 | xargs dirname 2>/dev/null || echo "udpxy_src")
cd "$SRC_DIR"

# ============================================================
# 5. Compilar (si hay Makefile) o copiar binario precompilado
# ============================================================
if [ -f "Makefile" ]; then
    log "Compilando udpxy desde código fuente..."
    make clean &>/dev/null || true
    make &>/dev/null || error "Error al compilar. Revisa las dependencias de compilación."
    log "Compilación exitosa."

    # Copiar binario compilado
    if [ -f "udpxy" ]; then
        cp udpxy "$INSTALL_DIR/udpxy"
    elif [ -f "udpxrec" ]; then
        cp udpxrec "$INSTALL_DIR/udpxrec" 2>/dev/null || true
        cp udpxy "$INSTALL_DIR/udpxy" 2>/dev/null || true
    fi
else
    # Si viene como binario precompilado
    log "Instalando binario precompilado..."
    BINARY=$(find . -type f -name "udpxy" | head -1)
    if [ -z "$BINARY" ]; then
        BINARY=$(find . -type f -executable | head -1)
    fi
    [ -z "$BINARY" ] && error "No se encontró el binario de udpxy."
    cp "$BINARY" "$INSTALL_DIR/udpxy"
fi

chmod +x "$INSTALL_DIR/udpxy"
log "udpxy instalado en $INSTALL_DIR/udpxy"

# ============================================================
# 6. Crear servicio systemd (si está disponible)
# ============================================================
if command -v systemctl &>/dev/null; then
    log "Creando servicio systemd..."
    cat > /etc/systemd/system/udpxy.service <<EOF
[Unit]
Description=udpxy - UDP multicast to HTTP proxy
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/udpxy -p $UDPXY_PORT -c $UDPXY_CLIENTS
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable udpxy &>/dev/null
    systemctl restart udpxy
    log "Servicio udpxy habilitado y arrancado."

elif command -v rc-service &>/dev/null; then
    # OpenRC (OpenWRT, Alpine)
    log "Creando script init OpenRC..."
    cat > /etc/init.d/udpxy <<EOF
#!/sbin/openrc-run
description="udpxy multicast proxy"
command="$INSTALL_DIR/udpxy"
command_args="-p $UDPXY_PORT -c $UDPXY_CLIENTS"
command_background=true
pidfile="/run/udpxy.pid"
EOF
    chmod +x /etc/init.d/udpxy
    rc-update add udpxy default
    rc-service udpxy start
    log "Servicio udpxy arrancado (OpenRC)."

else
    warn "No se detectó systemd ni OpenRC."
    warn "Inicia udpxy manualmente con:"
    echo ""
    echo "    $INSTALL_DIR/udpxy -p $UDPXY_PORT -c $UDPXY_CLIENTS"
    echo ""
fi

# ============================================================
# 7. Verificar instalación
# ============================================================
echo ""
log "Verificando instalación..."
if "$INSTALL_DIR/udpxy" -v &>/dev/null 2>&1; then
    VERSION=$("$INSTALL_DIR/udpxy" -v 2>&1 | head -1)
    log "Versión: $VERSION"
fi

# ============================================================
# 8. Limpiar archivos temporales
# ============================================================
cd /
rm -rf "$WORK_DIR"
log "Archivos temporales eliminados."

echo ""
echo "=============================================="
echo -e "${GREEN}  ✔  Instalación completada!${NC}"
echo "=============================================="
echo ""
echo "  Puerto :  $UDPXY_PORT"
echo "  Clientes: $UDPXY_CLIENTS (máx simultáneos)"
echo "  Interfaz: $UDPXY_MCAST_IF"
echo "  Binario:  $INSTALL_DIR/udpxy"
echo ""
echo "  Accede desde el navegador:"
echo "  http://$(hostname -I | awk '{print $1}'):$UDPXY_PORT/status"
echo ""
echo "  Para cambiar puerto o interfaz edita:"
echo "  /etc/systemd/system/udpxy.service"
echo ""
