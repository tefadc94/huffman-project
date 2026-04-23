
#!/bin/bash
set -e

echo "=== Descargando exactamente 100 libros de Gutenberg (últimos 30 días) ==="

TARGET_DIR="gutenberg_top100"
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# 1. Obtener IDs dinámicos de la página (tomamos hasta 200 para tener margen)
TOP_URL="https://www.gutenberg.org/browse/scores/top"
echo "Obteniendo lista de IDs desde $TOP_URL ..."
wget -q -O top.html "$TOP_URL"

# Extraer todos los IDs únicos y tomar los primeros 200 (los más populares)
DYNAMIC_IDS=$(grep -oP '/ebooks/\d+' top.html | sed 's/\/ebooks\///' | sort -nu | head -200)
rm top.html

# 2. Lista de respaldo (IDs conocidos, en caso de que los dinámicos fallen)
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
    2121 2250 2360 2450 2600 2750 2900 3000 3100 3200
)

# 3. Combinar dinámicos + respaldo, eliminar duplicados y mantener orden (los primeros son los mejores)
ALL_CANDIDATES=$(echo -e "${DYNAMIC_IDS}\n$(printf '%s\n' "${FALLBACK_IDS[@]}")" | sort -nu)

# 4. Eliminar archivos obsoletos (cuyo ID no esté en la lista de candidatos)
echo "Limpiando archivos de IDs que ya no están en el top..."
for f in book_*.txt; do
    if [ -f "$f" ]; then
        id=$(echo "$f" | sed 's/book_//;s/\.txt//')
        if ! echo "$ALL_CANDIDATES" | grep -qx "$id"; then
            echo "Eliminando obsoleto: $f"
            rm -f "$f"
        fi
    fi
done 2>/dev/null || true

# 5. Descargar hasta alcanzar 100 libros exitosos, reintentando fallos
SUCCESS=0
FAILED=0
# Contar cuántos ya tenemos (archivos válidos no vacíos)
CURRENT_COUNT=$(find . -maxdepth 1 -name 'book_*.txt' -size +0c | wc -l)
echo "Ya se tienen $CURRENT_COUNT libros válidos."

# Si ya tenemos al menos 100, nos saltamos la descarga (pero luego ajustaremos)
if [ $CURRENT_COUNT -ge 100 ]; then
    echo "Ya hay suficientes libros. No se descargarán nuevos."
else
    for id in $ALL_CANDIDATES; do
        if [ $SUCCESS -ge 100 ]; then
            break
        fi
        # Si el archivo ya existe y no está vacío, lo contamos como éxito y omitimos
        if [ -f "book_${id}.txt" ] && [ -s "book_${id}.txt" ]; then
            SUCCESS=$((SUCCESS+1))
            echo "[$SUCCESS/100] ID $id ya existe, omitiendo."
            continue
        fi
        echo -n "[$SUCCESS/100] Intentando ID: $id ... "
        # Reintentar hasta 3 veces por ID
        RETRIES=3
        DOWNLOADED=0
        for ((r=1; r<=RETRIES; r++)); do
            # Intentar formato -0.txt
            if wget -q --timeout=15 --tries=1 -O "book_${id}.tmp" "https://www.gutenberg.org/files/${id}/${id}-0.txt"; then
                if [ -s "book_${id}.tmp" ]; then
                    mv "book_${id}.tmp" "book_${id}.txt"
                    DOWNLOADED=1
                    break
                else
                    rm -f "book_${id}.tmp"
                fi
            fi
            # Segundo intento con formato alternativo
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
            echo "FAIL (después de $RETRIES intentos)"
        fi
        sleep 0.5
    done
fi

# 6. Si después de todo no llegamos a 100, mostrar error
if [ $SUCCESS -lt 100 ]; then
    echo "ERROR: Solo se descargaron $SUCCESS libros (necesarios 100)."
    echo "Puede intentar ejecutar de nuevo más tarde o revisar la conexión."
    exit 1
fi

# 7. Asegurar que solo queden exactamente 100 archivos (eliminar los sobrantes)
# Ordenamos los archivos según el orden de los candidatos (los primeros son los mejores)
# Primero obtenemos la lista de IDs exitosos (archivos válidos)
EXISTING_IDS=()
for f in book_*.txt; do
    if [ -s "$f" ]; then
        id=$(echo "$f" | sed 's/book_//;s/\.txt//')
        EXISTING_IDS+=("$id")
    fi
done
# Crear array asociativo para saber posición en la lista de candidatos
declare -A POS
POSITION=1
for id in $ALL_CANDIDATES; do
    POS[$id]=$POSITION
    POSITION=$((POSITION+1))
done
# Ordenar los IDs existentes por su posición (menor posición = mejor ranking)
IFS=$'\n' SORTED_IDS=($(sort -n -k2 <(for id in "${EXISTING_IDS[@]}"; do echo "${POS[$id]} $id"; done) | cut -d' ' -f2))
# Tomar los primeros 100
KEEP_IDS=("${SORTED_IDS[@]:0:100}")
# Eliminar los que no están en KEEP_IDS
for id in "${EXISTING_IDS[@]}"; do
    keep=0
    for keep_id in "${KEEP_IDS[@]}"; do
        if [ "$id" == "$keep_id" ]; then
            keep=1
            break
        fi
    done
    if [ $keep -eq 0 ]; then
        echo "Eliminando excedente: book_${id}.txt"
        rm -f "book_${id}.txt"
    fi
done

# Verificación final
FINAL_COUNT=$(find . -maxdepth 1 -name 'book_*.txt' -size +0c | wc -l)
echo ""
echo "=== RESUMEN FINAL ==="
echo "Libros descargados exitosamente: $FINAL_COUNT (objetivo: 100)"
echo "Carpeta: $(pwd)"
if [ $FINAL_COUNT -eq 100 ]; then
    echo "¡Éxito! Se tienen exactamente 100 libros."
else
    echo "Advertencia: Hay $FINAL_COUNT libros. Algo salió mal."
fi
