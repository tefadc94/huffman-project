#!/bin/bash
set -e

echo "=== Prueba con libros de Gutenberg ==="

if [ ! -d "gutenberg_top100" ] || [ -z "$(ls -A gutenberg_top100 2>/dev/null)" ]; then
    echo "Error: No hay libros descargados. Ejecute primero ./download_gutenberg_top100.sh"
    exit 1
fi

echo "1. Comprimiendo con version SERIAL..."
./compress_serial gutenberg_top100 gutenberg_serial.huf

echo "2. Comprimiendo con version FORK (4 procesos)..."
./compress_fork gutenberg_top100 gutenberg_fork.huf 4

echo "3. Comprimiendo con version PTHREAD (4 hilos)..."
./compress_pthread gutenberg_top100 gutenberg_pthread.huf 4

echo "4. Verificando que los tres archivos son identicos..."
if cmp -s gutenberg_serial.huf gutenberg_fork.huf && cmp -s gutenberg_serial.huf gutenberg_pthread.huf; then
    echo "   OK: Las tres versiones producen el mismo archivo comprimido"
else
    echo "   ERROR: Los archivos comprimidos no coinciden"
    exit 1
fi

echo "5. Descomprimiendo con version SERIAL..."
mkdir -p restored_serial
./decompress_serial gutenberg_serial.huf restored_serial

echo "6. Verificando integridad de los archivos descomprimidos..."
if diff -r gutenberg_top100 restored_serial > /dev/null; then
    echo "   OK: La descompresion recupera exactamente los archivos originales"
else
    echo "   ERROR: Los archivos no coinciden"
    exit 1
fi

echo ""
echo "=== TAMANOS ==="
ORIG_SIZE=$(du -sb gutenberg_top100 | cut -f1)
COMP_SIZE=$(stat -c%s gutenberg_serial.huf)
RATIO=$(echo "scale=2; $COMP_SIZE * 100 / $ORIG_SIZE" | bc)
echo "Tamano original: $ORIG_SIZE bytes"
echo "Tamano comprimido: $COMP_SIZE bytes"
echo "Ratio de compresion: $RATIO%"

echo ""
echo "=== PRUEBA COMPLETADA EXITOSAMENTE ==="
