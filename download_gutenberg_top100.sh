#!/bin/bash
set -e

echo "=== Descargando al menos 100 libros de Gutenberg (UTF-8) ==="

# Fuente: https://www.gutenberg.org/browse/scores/top
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
    # IDs adicionales para llegar a >200
    730 55 1051 209 1184 1399 1652 1818 1900 2000
    2121 2250 2360 2450 2600 2750 2900 3000 3100 3200
    3300 3400 3500 3600 3700 3800 3900 4000 4100 4200
    4300 4400 4500 4600 4700 4800 4900 5000 5100 5200
    5300 5400 5500 5600 5700 5800 5900 6000 6100 6200
    6300 6400 6500 6600 6700 6800 6900 7000 7100 7200
    7300 7400 7500 7600 7700 7800 7900 8000 8100 8200
    8300 8400 8500 8600 8700 8800 8900 9000 9100 9200
)

mkdir -p gutenberg_top100
cd gutenberg_top100

# 1. Obtener IDs dinámicos de la página Top 100 (últimos 30 días)
TOP_URL="https://www.gutenberg.org/browse/scores/top"
echo "Obteniendo IDs dinámicos desde $TOP_URL ..."
wget -q -O top.html "$TOP_URL"
DYNAMIC_IDS=$(grep -oP '/ebooks/\d+' top.html | sed 's/\/ebooks\///' | sort -u)
rm top.html

# 2. Combinar dinámicos + fijos, eliminar duplicados, y expandir a una lista ordenada
ALL_IDS=$(echo -e "${DYNAMIC_IDS}\n$(printf '%s\n' "${FALLBACK_IDS[@]}")" | sort -nu)
TOTAL_IDS=$(echo "$ALL_IDS" | wc -l)
echo "Total de IDs únicos en la lista: $TOTAL_IDS"

# 3. Descargar hasta alcanzar 100 exitosos
SUCCESS=0
FAILED=0
ATTEMPT=0

for id in $ALL_IDS; do
    # Si ya tenemos 100, salir
    if [ $SUCCESS -ge 100 ]; then
        break
    fi
    
    # Si el archivo ya existe y no está vacío, contar como éxito y saltar
    if [ -f "book_${id}.txt" ] && [ -s "book_${id}.txt" ]; then
        SUCCESS=$((SUCCESS + 1))
        echo "[$SUCCESS/100] ID $id ya descargado, omitiendo."
        continue
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    echo -n "[$SUCCESS/100] Intentando ID: $id (intento $ATTEMPT) ... "
    
    # Intentar formato -0.txt (UTF-8)
    if wget -q --timeout=15 --tries=2 -O "book_${id}.tmp" "https://www.gutenberg.org/files/${id}/${id}-0.txt"; then
        if [ -s "book_${id}.tmp" ]; then
            mv "book_${id}.tmp" "book_${id}.txt"
            SUCCESS=$((SUCCESS + 1))
            echo "OK"
        else
            rm -f "book_${id}.tmp"
            FAILED=$((FAILED + 1))
            echo "FAIL (archivo vacío)"
        fi
    else
        # Intentar formato alternativo sin -0
        if wget -q --timeout=15 --tries=2 -O "book_${id}.tmp" "https://www.gutenberg.org/files/${id}/${id}.txt"; then
            if [ -s "book_${id}.tmp" ]; then
                mv "book_${id}.tmp" "book_${id}.txt"
                SUCCESS=$((SUCCESS + 1))
                echo "OK (alternativo)"
            else
                rm -f "book_${id}.tmp"
                FAILED=$((FAILED + 1))
                echo "FAIL (vacío alternativo)"
            fi
        else
            FAILED=$((FAILED + 1))
            echo "FAIL (no se pudo descargar)"
        fi
    fi
    sleep 0.5
done

cd ..

echo ""
echo "=== RESUMEN FINAL ==="
echo "Libros descargados exitosamente: $SUCCESS"
echo "Fallidos: $FAILED"
echo "Total de IDs intentados: $ATTEMPT"
echo "Ubicación: $(pwd)/gutenberg_top100"

if [ $SUCCESS -ge 100 ]; then
    echo "¡Éxito! Se descargaron $SUCCESS libros (>=100)."
else
    echo "Advertencia: Solo se descargaron $SUCCESS libros (<100)."
    echo "Puede deberse a que los IDs adicionales no están disponibles en UTF-8."
    echo "Para obtener más, ejecute nuevamente el script; omitirá los ya descargados."
fi
