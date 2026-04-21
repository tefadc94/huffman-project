#!/bin/bash
set -e

echo "=== Instalacion del proyecto Huffman ==="
echo "Instalando dependencias (gcc, make, wget)..."
sudo apt update
sudo apt install -y gcc make wget

echo "Compilando programas..."
make clean 2>/dev/null || true
make all

echo "Compilacion completada. Ejecutables disponibles:"
ls -lh compress_* decompress_*

echo ""
echo "Para probar con libros de Gutenberg, ejecute:"
echo "  ./download_gutenberg_top100.sh"
echo "  ./test_with_gutenberg.sh"
