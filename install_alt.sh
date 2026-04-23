#!/bin/bash
set -e

echo "=== Instalacion alternativa del proyecto Huffman ==="
echo "Compilando programas..."

# Verificar herramientas necesarias
for cmd in gcc make wget; do
    if ! command -v $cmd &> /dev/null; then
        echo "Instalando $cmd..."
        apt update && apt install -y $cmd
    fi
done

# Compilar todo (limpiar primero)
make clean
make all

echo "Compilacion completada. Ejecutables:"
ls -lh compress_* decompress_*

# Opcional: descargar 100 libros si no existen
if [ ! -d "gutenberg_top100" ] || [ -z "$(ls -A gutenberg_top100 2>/dev/null)" ]; then
    echo "Descargando Top 100 libros de Gutenberg..."
    chmod +x download_gutenberg_top100.sh
    ./download_gutenberg_top100.sh
fi

echo ""
echo "Para ejecutar el benchmark (verificacion + speedup):"
echo "  ./benchmark.sh"
echo ""
echo "Para comprimir/descomprimir manualmente:"
echo "  ./compress_serial gutenberg_top100 salida.huf"
echo "  ./decompress_serial salida.huf restaurado"
