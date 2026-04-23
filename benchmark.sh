#!/bin/bash
set -e

echo "=== Benchmark de Huffman (Serial, Fork, Pthread) ==="
echo "Verificacion automatica + medicion de speedup (2 y 4 nucleos)"

# Verificar ejecutables
for prog in compress_serial compress_fork compress_pthread decompress_serial decompress_fork decompress_pthread; do
    if [ ! -x "./$prog" ]; then
        echo "Error: No se encuentra el ejecutable $prog"
        echo "Ejecute 'make all' primero"
        exit 1
    fi
done

# --- Descarga automática de los 100 libros (si no existen) ---
TEST_DIR="gutenberg_top100"
if [ ! -d "$TEST_DIR" ] || [ -z "$(ls -A $TEST_DIR 2>/dev/null)" ]; then
    echo "No se encuentra la carpeta '$TEST_DIR' con libros de Gutenberg."
    echo "Ejecutando script de descarga automática..."
    if [ ! -x "./download_gutenberg_top100.sh" ]; then
        echo "Error: No se encuentra o no es ejecutable ./download_gutenberg_top100.sh"
        exit 1
    fi
    ./download_gutenberg_top100.sh
    if [ ! -d "$TEST_DIR" ] || [ -z "$(ls -A $TEST_DIR 2>/dev/null)" ]; then
        echo "Error: No se pudo descargar ningún libro. Abortando benchmark."
        exit 1
    fi
fi

echo "Usando libros de Gutenberg en: $TEST_DIR"
NUM_FILES=$(ls -1 $TEST_DIR/*.txt 2>/dev/null | wc -l)
echo "Archivos encontrados: $NUM_FILES (deben ser 100 para prueba completa)"
echo ""

# ====================================================
# FASE 1: VERIFICACIÓN DE CORRECCIÓN (todas las versiones)
# ====================================================
echo "=== FASE 1: Verificacion de compresion/descompresion ==="

# Serial
echo "1. Comprimiendo con serial -> verification_serial.huf"
./compress_serial "$TEST_DIR" verification_serial.huf > /dev/null
echo "   Descomprimiendo (serial) en verification_serial/"
rm -rf verification_serial
mkdir -p verification_serial
./decompress_serial verification_serial.huf verification_serial > /dev/null

# Fork (2 procesos)
echo "2. Comprimiendo con fork (2 procesos) -> verification_fork.huf"
./compress_fork "$TEST_DIR" verification_fork.huf 2 > /dev/null
echo "   Descomprimiendo (fork) en verification_fork/"
rm -rf verification_fork
mkdir -p verification_fork
./decompress_fork verification_fork.huf verification_fork 2 > /dev/null

# Pthread (2 hilos)
echo "3. Comprimiendo con pthread (2 hilos) -> verification_pthread.huf"
./compress_pthread "$TEST_DIR" verification_pthread.huf 2 > /dev/null
echo "   Descomprimiendo (pthread) en verification_pthread/"
rm -rf verification_pthread
mkdir -p verification_pthread
./decompress_pthread verification_pthread.huf verification_pthread 2 > /dev/null

echo ""
echo "--- Comparacion automatica de resultados ---"

compare_dirs() {
    if diff -r "$1" "$2" > /dev/null; then
        echo "  OK: $1 y $2 son identicos"
        return 0
    else
        echo "  ERROR: $1 y $2 difieren"
        return 1
    fi
}

compare_dirs "$TEST_DIR" verification_serial
compare_dirs "$TEST_DIR" verification_fork
compare_dirs "$TEST_DIR" verification_pthread
compare_dirs verification_serial verification_fork
compare_dirs verification_serial verification_pthread

echo ""

# ====================================================
# FASE 2: BENCHMARK DE RENDIMIENTO (2 y 4 nucleos)
# ====================================================
echo "=== FASE 2: Mediciones de rendimiento (speedup) ==="
echo ""

TEMP_DECOMP_DIR=$(mktemp -d /tmp/benchmark_decomp_XXXXXX)
trap "rm -rf $TEMP_DECOMP_DIR" EXIT

get_time() {
    local output="$1"
    echo "$output" | grep -oP 'Time: \K\d+' | head -1
}

# Compresión Serial
echo "--- Compresion SERIAL ---"
OUT=$(./compress_serial "$TEST_DIR" /dev/null 2>&1)
SERIAL_COMP=$(get_time "$OUT")
echo "   Tiempo: ${SERIAL_COMP} ms"

# Compresión Fork
for procs in 2 4; do
    echo "--- Compresion FORK (${procs} procesos) ---"
    OUT=$(./compress_fork "$TEST_DIR" /dev/null "$procs" 2>&1)
    TIME=$(get_time "$OUT")
    SPEEDUP=$(echo "scale=2; $SERIAL_COMP / $TIME" | bc)
    echo "   Tiempo: ${TIME} ms, Speedup: ${SPEEDUP}x"
    eval FORK_COMP_TIME_${procs}=$TIME
    eval FORK_COMP_SPEEDUP_${procs}=$SPEEDUP
done

# Compresión Pthread
for threads in 2 4; do
    echo "--- Compresion PTHREAD (${threads} hilos) ---"
    OUT=$(./compress_pthread "$TEST_DIR" /dev/null "$threads" 2>&1)
    TIME=$(get_time "$OUT")
    SPEEDUP=$(echo "scale=2; $SERIAL_COMP / $TIME" | bc)
    echo "   Tiempo: ${TIME} ms, Speedup: ${SPEEDUP}x"
    eval PTHREAD_COMP_TIME_${threads}=$TIME
    eval PTHREAD_COMP_SPEEDUP_${threads}=$SPEEDUP
done

# Preparar archivo comprimido para descompresión (usamos serial)
echo ""
echo "Generando archivo temporal para pruebas de descompresión..."
TEMP_HUF="temp_benchmark.huf"
./compress_serial "$TEST_DIR" "$TEMP_HUF" > /dev/null

# Descompresión Serial
echo "--- Descompresion SERIAL ---"
OUT=$(./decompress_serial "$TEMP_HUF" "$TEMP_DECOMP_DIR" 2>&1)
SERIAL_DECOMP=$(get_time "$OUT")
echo "   Tiempo: ${SERIAL_DECOMP} ms"

# Descompresión Fork
for procs in 2 4; do
    echo "--- Descompresion FORK (${procs} procesos) ---"
    OUT=$(./decompress_fork "$TEMP_HUF" "$TEMP_DECOMP_DIR" "$procs" 2>&1)
    TIME=$(get_time "$OUT")
    SPEEDUP=$(echo "scale=2; $SERIAL_DECOMP / $TIME" | bc)
    echo "   Tiempo: ${TIME} ms, Speedup: ${SPEEDUP}x"
    eval FORK_DECOMP_TIME_${procs}=$TIME
    eval FORK_DECOMP_SPEEDUP_${procs}=$SPEEDUP
done

# Descompresión Pthread
for threads in 2 4; do
    echo "--- Descompresion PTHREAD (${threads} hilos) ---"
    OUT=$(./decompress_pthread "$TEMP_HUF" "$TEMP_DECOMP_DIR" "$threads" 2>&1)
    TIME=$(get_time "$OUT")
    SPEEDUP=$(echo "scale=2; $SERIAL_DECOMP / $TIME" | bc)
    echo "   Tiempo: ${TIME} ms, Speedup: ${SPEEDUP}x"
    eval PTHREAD_DECOMP_TIME_${threads}=$TIME
    eval PTHREAD_DECOMP_SPEEDUP_${threads}=$SPEEDUP
done

rm -f "$TEMP_HUF"

# Mostrar tabla resumen
echo ""
echo "=========================================="
echo "        TABLA DE SPEEDUP FINAL"
echo "=========================================="
echo ""
echo "COMPRESION:"
printf "  %-20s %-12s %-10s\n" "Version" "Tiempo(ms)" "Speedup"
printf "  %-20s %-12s %-10s\n" "Serial" "$SERIAL_COMP" "1.00"
printf "  %-20s %-12s %-10s\n" "Fork (2)"   "${FORK_COMP_TIME_2}"   "${FORK_COMP_SPEEDUP_2}"
printf "  %-20s %-12s %-10s\n" "Fork (4)"   "${FORK_COMP_TIME_4}"   "${FORK_COMP_SPEEDUP_4}"
printf "  %-20s %-12s %-10s\n" "Pthread (2)" "${PTHREAD_COMP_TIME_2}" "${PTHREAD_COMP_SPEEDUP_2}"
printf "  %-20s %-12s %-10s\n" "Pthread (4)" "${PTHREAD_COMP_TIME_4}" "${PTHREAD_COMP_SPEEDUP_4}"
echo ""
echo "DESCOMPRESION:"
printf "  %-20s %-12s %-10s\n" "Version" "Tiempo(ms)" "Speedup"
printf "  %-20s %-12s %-10s\n" "Serial" "$SERIAL_DECOMP" "1.00"
printf "  %-20s %-12s %-10s\n" "Fork (2)"   "${FORK_DECOMP_TIME_2}"   "${FORK_DECOMP_SPEEDUP_2}"
printf "  %-20s %-12s %-10s\n" "Fork (4)"   "${FORK_DECOMP_TIME_4}"   "${FORK_DECOMP_SPEEDUP_4}"
printf "  %-20s %-12s %-10s\n" "Pthread (2)" "${PTHREAD_DECOMP_TIME_2}" "${PTHREAD_DECOMP_SPEEDUP_2}"
printf "  %-20s %-12s %-10s\n" "Pthread (4)" "${PTHREAD_DECOMP_TIME_4}" "${PTHREAD_DECOMP_SPEEDUP_4}"
echo ""
echo "Benchmark completado."
