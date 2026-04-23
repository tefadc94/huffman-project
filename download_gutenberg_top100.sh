#!/bin/bash
set -e

echo "=== Descargando exactamente 100 libros de Gutenberg (últimos 30 días) ==="

TARGET_DIR="gutenberg_top100"
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# 1. Eliminar cualquier archivo basura (temporales, vacíos, duplicados)
rm -f book_*.tmp book_*.txt.* 2>/dev/null
find . -maxdepth 1 -name 'book_*.txt' -size 0c -delete 2>/dev/null

# 2. Obtener IDs de la página (primeros 200)
TOP_URL="https://www.gutenberg.org/browse/scores/top"
echo "Obteniendo lista de IDs desde $TOP_URL ..."
wget -q -O top.html "$TOP_URL"
DYNAMIC_IDS=$(grep -oP '/ebooks/\d+' top.html | sed 's/\/ebooks\///' | sort -nu | head -200)
rm top.html

# Lista de respaldo (IDs conocidos)
FALLBACK_IDS=(
    84 1342 1661 2701 11 43 174 98 1400 1260
    345 76 1952 161 23 135 844 158 219 100
    829 25344 2824 2542 120 1260 1661 2701 84 1342
    1260 174 98 1400 11 43 84 1342 1661 2701
    345 76 1952 161 23 135 844 158 219 100
    829 25344 2824 2542 120 1260 1661 2701 84 1342
    98 1400 11 43 174 345 76 1952 161 23
    135 844 158 219 100 829 25344 2824 2542 120
    1260 1661 2701 84 1342 98 1400 11 43 174
    345 76 1952 161 23 135 844 158 219 100
    730 55 1051 209 1184 1399 1652 1818 1900 2000
)

# Combinar y eliminar duplicados
ALL_CANDIDATES=$(echo -e "${DYNAMIC_IDS}\n$(printf '%s\n' "${FALLBACK_IDS[@]}")" | sort -nu)

# 3. Eliminar archivos cuyo ID ya no está en la lista de candidatos
for f in book_*.txt; do
    if [ -f "$f" ]; then
        id=$(echo "$f" | sed 's/book_//;s/\.txt//')
        if ! echo "$ALL_CANDIDATES" | grep -qx "$id"; then
            echo "Eliminando obsoleto: $f"
            rm -f "$f"
        fi
    fi
done 2>/dev/null || true

# 4. Descargar hasta alcanzar 100 exitosos (con reintentos)
SUCCESS=0
FAILED=0

for id in $ALL_CANDIDATES; do
    if [ $SUCCESS -ge 100 ]; then
        break
    fi
    # Si ya existe un archivo válido, lo contamos y saltamos
    if [ -f "book_${id}.txt" ] && [ -s "book_${id}.txt" ]; then
        SUCCESS=$((SUCCESS+1))
        echo "[$SUCCESS/100] ID $id ya existe, omitiendo."
        continue
    fi
    echo -n "[$SUCCESS/100] Intentando ID: $id ... "
    RETRIES=3
    DOWNLOADED=0
    for ((r=1; r<=RETRIES; r++)); do
        if wget -q --timeout=15 --tries=1 -O "book_${id}.tmp" "https://www.gutenberg.org/files/${id}/${id}-0.txt"; then
            if [ -s "book_${id}.tmp" ]; then
                mv "book_${id}.tmp" "book_${id}.txt"
                DOWNLOADED=1
                break
            else
                rm -f "book_${id}.tmp"
            fi
        fi
        if wget -q --timeout=15 --tries=1 -O "book_${id}.tmp" "https://www.gutenberg.org/files/${id}/${id}.txt"; then
            if [ -s "book_${id}.tmp" ]; then
                mv "book_${id}.tmp" "book_${id}.txt"
                DOWNLOADED=1
                break
            else
                rm -f "book_${id}.tmp"
            fi
        fi
        sleep 1
    done
    if [ $DOWNLOADED -eq 1 ]; then
        SUCCESS=$((SUCCESS+1))
        echo "OK"
    else
        FAILED=$((FAILED+1))
        echo "FAIL"
    fi
    sleep 0.5
done

# 5. Limpiar archivos vacíos y temporales que pudieran quedar
find . -maxdepth 1 -name 'book_*.txt' -size 0c -delete
rm -f book_*.tmp 2>/dev/null

# 6. Asegurar exactamente 100 archivos (los mejores según ranking)
# Crear lista de archivos existentes y no vacíos
EXISTING_FILES=()
for f in book_*.txt; do
    if [ -f "$f" ] && [ -s "$f" ]; then
        EXISTING_FILES+=("$f")
    fi
done

# Si hay más de 100, ordenar según la posición en ALL_CANDIDATES y eliminar los extra
if [ ${#EXISTING_FILES[@]} -gt 100 ]; then
    echo "Hay más de 100 archivos. Eliminando excedentes según ranking..."
    # Crear un array con IDs y posiciones
    TEMP_FILE=$(mktemp)
    for f in "${EXISTING_FILES[@]}"; do
        id=$(echo "$f" | sed 's/book_//;s/\.txt//')
        # Buscar la posición en ALL_CANDIDATES (primera aparición)
        pos=$(echo "$ALL_CANDIDATES" | grep -n "^${id}$" | cut -d: -f1)
        if [ -z "$pos" ]; then
            pos=999999
        fi
        echo "$pos $f"
    done > "$TEMP_FILE"
    # Ordenar por posición
    sort -n "$TEMP_FILE" | head -100 | while read -r pos f; do
        echo "$f"
    done > /tmp/keep_files.txt
    # Eliminar los que no están en la lista de mantener
    for f in "${EXISTING_FILES[@]}"; do
        if ! grep -qx "$f" /tmp/keep_files.txt; then
            echo "Eliminando excedente: $f"
            rm -f "$f"
        fi
    done
    rm -f "$TEMP_FILE" /tmp/keep_files.txt
fi

# 7. Conteo final
FINAL_COUNT=$(find . -maxdepth 1 -name 'book_*.txt' -size +0c | wc -l)
cd ..

echo ""
echo "=== RESUMEN FINAL ==="
echo "Libros descargados exitosamente: $FINAL_COUNT (objetivo: 100)"
echo "Carpeta: $(pwd)/$TARGET_DIR"
if [ $FINAL_COUNT -eq 100 ]; then
    echo "¡Éxito! Se tienen exactamente 100 libros."
elif [ $FINAL_COUNT -lt 100 ]; then
    echo "ERROR: Solo se descargaron $FINAL_COUNT libros (necesarios 100)."
    exit 1
else
    echo "ERROR: Quedaron $FINAL_COUNT libros (más de 100). Se recomienda eliminar la carpeta y volver a ejecutar."
    exit 1
fi
