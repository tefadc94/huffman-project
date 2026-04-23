#!/bin/bash
set -e

echo "=== Benchmark de aceleracion (Speedup) ==="

# Verificar ejecutables
for prog in compress_serial compress_fork compress_pthread decompress_serial decompress_fork decompress_pthread; do
    if [ ! -x "./$prog" ]; then
        echo "Error: No se encuentra el ejecutable $prog"
        echo "Ejecute 'make all' primero"
        exit 1
    fi
done

# Verificar que exista la carpeta de libros de Gutenberg y que no esté vacía
TEST_DIR="gutenberg_top100"
if [ ! -d "$TEST_DIR" ] || [ -z "$(ls -A $TEST_DIR 2>/dev/null)" ]; then
    echo "Error: No se encuentra la carpeta '$TEST_DIR' con libros de Gutenberg."
    echo "Ejecute primero: ./download_gutenberg_top100.sh"
    exit 1
fi

echo "Usando libros de Gutenberg en: $TEST_DIR"
NUM_FILES=$(ls -1 $TEST_DIR/*.txt 2>/dev/null | wc -l)
echo "Archivos encontrados: $NUM_FILES"

# Para verificación: comprimir todos los libros en un archivo y luego descomprimirlos en una carpeta de verificación
echo ""
echo "--- Verificación de compresión/descompresión (resultados visibles) ---"
VERIF_DIR="verification_output"
echo "Comprimiendo todos los libros en 'full_verification.huf' ..."
./compress_serial "$TEST_DIR" full_verification.huf > /dev/null
echo "Descomprimiendo en carpeta '$VERIF_DIR' ..."
rm -rf "$VERIF_DIR"
mkdir -p "$VERIF_DIR"
./decompress_serial full_verification.huf "$VERIF_DIR" > /dev/null
echo "Verificación completada. Los archivos descomprimidos están en: $(pwd)/$VERIF_DIR"
echo "Puede comparar con los originales en $TEST_DIR (por ejemplo, diff -r)"
echo ""

# Ahora el benchmark de tiempos (sin guardar los descomprimidos, para no afectar E/S)
echo "--- Iniciando mediciones de rendimiento (no se guardan los resultados descomprimidos) ---"
echo ""

# Crear directorio temporal para descompresión durante las pruebas (se usará /tmp)
TEMP_DECOMP_DIR=$(mktemp -d /tmp/benchmark_decomp_XXXXXX)
# Asegurar que se borre al salir
trap "rm -rf $TEMP_DECOMP_DIR" EXIT

# Función para extraer tiempo
get_time() {
    local output="$1"
    echo "$output" | grep -oP 'Time: \K\d+' | head -1
}

# Compresión Serial
echo "1. Compresion SERIAL..."
OUT=$(./compress_serial "$TEST_DIR" /dev/null 2>&1)
SERIAL_COMP=$(get_time "$OUT")
echo "   Tiempo: ${SERIAL_COMP} ms"

# Compresión Fork
for procs in 2 4 8; do
    echo "2. Compresion FORK (${procs} procesos)..."
    OUT=$(./compress_fork "$TEST_DIR" /dev/null "$procs" 2>&1)
    TIME=$(get_time "$OUT")
    SPEEDUP=$(echo "scale=2; $SERIAL_COMP / $TIME" | bc)
    echo "   Tiempo: ${TIME} ms, Speedup: ${SPEEDUP}x"
    eval FORK_COMP_TIME_${procs}=$TIME
    eval FORK_COMP_SPEEDUP_${procs}=$SPEEDUP
done

# Compresión Pthread
for threads in 2 4 8; do
    echo "3. Compresion PTHREAD (${threads} hilos)..."
    OUT=$(./compress_pthread "$TEST_DIR" /dev/null "$threads" 2>&1)
    TIME=$(get_time "$OUT")
    SPEEDUP=$(echo "scale=2; $SERIAL_COMP / $TIME" | bc)
    echo "   Tiempo: ${TIME} ms, Speedup: ${SPEEDUP}x"
    eval PTHREAD_COMP_TIME_${threads}=$TIME
    eval PTHREAD_COMP_SPEEDUP_${threads}=$SPEEDUP
done

# Preparar archivo comprimido para descompresión (usando el mismo directorio de prueba)
echo ""
echo "Generando archivo comprimido temporal para pruebas de descompresión..."
TEMP_HUF="temp_benchmark.huf"
./compress_serial "$TEST_DIR" "$TEMP_HUF" > /dev/null

# Descompresión Serial (escribiendo en directorio temporal)
echo "4. Descompresion SERIAL..."
OUT=$(./decompress_serial "$TEMP_HUF" "$TEMP_DECOMP_DIR" 2>&1)
SERIAL_DECOMP=$(get_time "$OUT")
echo "   Tiempo: ${SERIAL_DECOMP} ms"

# Descompresión Fork
for procs in 2 4 8; do
    echo "5. Descompresion FORK (${procs} procesos)..."
    OUT=$(./decompress_fork "$TEMP_HUF" "$TEMP_DECOMP_DIR" "$procs" 2>&1)
    TIME=$(get_time "$OUT")
    SPEEDUP=$(echo "scale=2; $SERIAL_DECOMP / $TIME" | bc)
    echo "   Tiempo: ${TIME} ms, Speedup: ${SPEEDUP}x"
    eval FORK_DECOMP_TIME_${procs}=$TIME
    eval FORK_DECOMP_SPEEDUP_${procs}=$SPEEDUP
done

# Descompresión Pthread
for threads in 2 4 8; do
    echo "6. Descompresion PTHREAD (${threads} hilos)..."
    OUT=$(./decompress_pthread "$TEMP_HUF" "$TEMP_DECOMP_DIR" "$threads" 2>&1)
    TIME=$(get_time "$OUT")
    SPEEDUP=$(echo "scale=2; $SERIAL_DECOMP / $TIME" | bc)
    echo "   Tiempo: ${TIME} ms, Speedup: ${SPEEDUP}x"
    eval PTHREAD_DECOMP_TIME_${threads}=$TIME
    eval PTHREAD_DECOMP_SPEEDUP_${threads}=$SPEEDUP
done

# Limpiar archivo temporal
rm -f "$TEMP_HUF"
# El directorio temporal se eliminará automáticamente con trap

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
printf "  %-20s %-12s %-10s\n" "Fork (8)"   "${FORK_COMP_TIME_8}"   "${FORK_COMP_SPEEDUP_8}"
printf "  %-20s %-12s %-10s\n" "Pthread (2)" "${PTHREAD_COMP_TIME_2}" "${PTHREAD_COMP_SPEEDUP_2}"
printf "  %-20s %-12s %-10s\n" "Pthread (4)" "${PTHREAD_COMP_TIME_4}" "${PTHREAD_COMP_SPEEDUP_4}"
printf "  %-20s %-12s %-10s\n" "Pthread (8)" "${PTHREAD_COMP_TIME_8}" "${PTHREAD_COMP_SPEEDUP_8}"
echo ""
echo "DESCOMPRESION:"
printf "  %-20s %-12s %-10s\n" "Version" "Tiempo(ms)" "Speedup"
printf "  %-20s %-12s %-10s\n" "Serial" "$SERIAL_DECOMP" "1.00"
printf "  %-20s %-12s %-10s\n" "Fork (2)"   "${FORK_DECOMP_TIME_2}"   "${FORK_DECOMP_SPEEDUP_2}"
printf "  %-20s %-12s %-10s\n" "Fork (4)"   "${FORK_DECOMP_TIME_4}"   "${FORK_DECOMP_SPEEDUP_4}"
printf "  %-20s %-12s %-10s\n" "Fork (8)"   "${FORK_DECOMP_TIME_8}"   "${FORK_DECOMP_SPEEDUP_8}"
printf "  %-20s %-12s %-10s\n" "Pthread (2)" "${PTHREAD_DECOMP_TIME_2}" "${PTHREAD_DECOMP_SPEEDUP_2}"
printf "  %-20s %-12s %-10s\n" "Pthread (4)" "${PTHREAD_DECOMP_TIME_4}" "${PTHREAD_DECOMP_SPEEDUP_4}"
printf "  %-20s %-12s %-10s\n" "Pthread (8)" "${PTHREAD_DECOMP_TIME_8}" "${PTHREAD_DECOMP_SPEEDUP_8}"
echo ""
echo "Benchmark completado."
echo "Los archivos descomprimidos de verificación están en: $(pwd)/$VERIF_DIR"
