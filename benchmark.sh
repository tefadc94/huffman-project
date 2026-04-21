#!/bin/bash
set -e

echo "=== Benchmark de aceleracion (Speedup) ==="

# Verificar si existen los ejecutables
for prog in compress_serial compress_fork compress_pthread decompress_serial decompress_fork decompress_pthread; do
    if [ ! -x "./$prog" ]; then
        echo "Error: No se encuentra el ejecutable $prog"
        echo "Ejecute 'make all' primero"
        exit 1
    fi
done

# Usar libros de Gutenberg si existen, si no crear datos de prueba
if [ -d "gutenberg_top100" ] && [ "$(ls -A gutenberg_top100 2>/dev/null)" ]; then
    TEST_DIR="gutenberg_top100"
    echo "Usando libros de Gutenberg descargados en: $TEST_DIR"
else
    echo "No se encontraron libros de Gutenberg. Creando directorio de prueba artificial..."
    mkdir -p benchmark_test
    for i in {1..50}; do
        echo "Archivo de prueba $i con contenido repetitivo." > benchmark_test/file_$i.txt
        for j in {1..200}; do
            echo "Linea $j del archivo $i para compresion." >> benchmark_test/file_$i.txt
        done
    done
    TEST_DIR="benchmark_test"
    echo "Usando datos artificiales en: $TEST_DIR"
fi

echo ""
echo "Iniciando mediciones... (puede tomar un minuto)"
echo ""

# Función para extraer el tiempo en milisegundos de la salida del programa
# Los programas ya imprimen "Time: X ms"
get_time() {
    local output="$1"
    echo "$output" | grep -oP 'Time: \K\d+' | head -1
}

# --- Compresion Serial ---
echo "1. Compresion SERIAL..."
OUT=$(./compress_serial "$TEST_DIR" /dev/null 2>&1)
SERIAL_COMP=$(get_time "$OUT")
echo "   Tiempo: ${SERIAL_COMP} ms"

# --- Compresion Fork ---
for procs in 2 4 8; do
    echo "2. Compresion FORK (${procs} procesos)..."
    OUT=$(./compress_fork "$TEST_DIR" /dev/null "$procs" 2>&1)
    TIME=$(get_time "$OUT")
    SPEEDUP=$(echo "scale=2; $SERIAL_COMP / $TIME" | bc)
    echo "   Tiempo: ${TIME} ms, Speedup: ${SPEEDUP}x"
    eval FORK_COMP_TIME_${procs}=$TIME
    eval FORK_COMP_SPEEDUP_${procs}=$SPEEDUP
done

# --- Compresion Pthread ---
for threads in 2 4 8; do
    echo "3. Compresion PTHREAD (${threads} hilos)..."
    OUT=$(./compress_pthread "$TEST_DIR" /dev/null "$threads" 2>&1)
    TIME=$(get_time "$OUT")
    SPEEDUP=$(echo "scale=2; $SERIAL_COMP / $TIME" | bc)
    echo "   Tiempo: ${TIME} ms, Speedup: ${SPEEDUP}x"
    eval PTHREAD_COMP_TIME_${threads}=$TIME
    eval PTHREAD_COMP_SPEEDUP_${threads}=$SPEEDUP
done

# --- Preparar archivo comprimido para descompresion ---
echo ""
echo "Generando archivo comprimido para pruebas de descompresion..."
./compress_serial "$TEST_DIR" temp_benchmark.huf > /dev/null

# --- Descompresion Serial ---
echo "4. Descompresion SERIAL..."
OUT=$(./decompress_serial temp_benchmark.huf /dev/null 2>&1)
SERIAL_DECOMP=$(get_time "$OUT")
echo "   Tiempo: ${SERIAL_DECOMP} ms"

# --- Descompresion Fork ---
for procs in 2 4 8; do
    echo "5. Descompresion FORK (${procs} procesos)..."
    OUT=$(./decompress_fork temp_benchmark.huf /dev/null "$procs" 2>&1)
    TIME=$(get_time "$OUT")
    SPEEDUP=$(echo "scale=2; $SERIAL_DECOMP / $TIME" | bc)
    echo "   Tiempo: ${TIME} ms, Speedup: ${SPEEDUP}x"
    eval FORK_DECOMP_TIME_${procs}=$TIME
    eval FORK_DECOMP_SPEEDUP_${procs}=$SPEEDUP
done

# --- Descompresion Pthread ---
for threads in 2 4 8; do
    echo "6. Descompresion PTHREAD (${threads} hilos)..."
    OUT=$(./decompress_pthread temp_benchmark.huf /dev/null "$threads" 2>&1)
    TIME=$(get_time "$OUT")
    SPEEDUP=$(echo "scale=2; $SERIAL_DECOMP / $TIME" | bc)
    echo "   Tiempo: ${TIME} ms, Speedup: ${SPEEDUP}x"
    eval PTHREAD_DECOMP_TIME_${threads}=$TIME
    eval PTHREAD_DECOMP_SPEEDUP_${threads}=$SPEEDUP
done

# Limpiar archivo temporal
rm -f temp_benchmark.huf
rm -rf benchmark_test 2>/dev/null

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
echo "Benchmark completado. "
