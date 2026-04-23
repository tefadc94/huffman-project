#!/bin/bash

# ======================================================
# Script de instalación completo para entorno root
# Si no se es root, se reinicia con su -
# ======================================================

# Verificar si ya somos root
if [ "$EUID" -ne 0 ]; then
    echo "No se es root. Relanzando el script con 'su -'..."
    # Relanzamos el script con su -, pasando la ruta actual
    exec su -c "cd \"$PWD\" && bash \"$0\""
    exit 0
fi

# A partir de aquí se ejecuta como root
echo "=== Instalación completa del proyecto Huffman como root ==="

# 1. Actualizar repositorios e instalar dependencias
echo "Instalando paquetes necesarios (git, gcc, make, wget)..."
apt update
apt install -y git gcc make wget

# 2. Clonar el repositorio si no existe
REPO_URL="https://github.com/tefadc94/huffman-project.git"
REPO_DIR="huffman-project"

if [ ! -d "$REPO_DIR" ]; then
    echo "Clonando repositorio desde $REPO_URL ..."
    git clone "$REPO_URL"
else
    echo "El directorio $REPO_DIR ya existe. Se usará el existente."
fi

cd "$REPO_DIR"

# 3. Limpiar y compilar todo
echo "Compilando los programas..."
make clean
make all

# 4. Asegurar que los scripts tengan permisos de ejecución
chmod +x download_gutenberg_top100.sh benchmark.sh install_alt.sh

# 5. Descargar los 100 libros (si no existen)
if [ ! -d "gutenberg_top100" ] || [ -z "$(ls -A gutenberg_top100 2>/dev/null)" ]; then
    echo "Descargando exactamente 100 libros de Gutenberg..."
    ./download_gutenberg_top100.sh
fi

# 6. Mostrar instrucciones finales
echo ""
echo "=== Instalación completada ==="
echo "Ahora puedes ejecutar el benchmark:"
echo "  cd $PWD && ./benchmark.sh"
echo "O comprimir/descomprimir manualmente:"
echo "  ./compress_serial gutenberg_top100 salida.huf"
echo "  ./decompress_serial salida.huf restaurado"
