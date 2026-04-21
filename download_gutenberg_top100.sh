#!/bin/bash
set -e

echo "=== Descargando Top 100 libros de Gutenberg ==="
mkdir -p gutenberg_top100
cd gutenberg_top100

TOP_URL="https://www.gutenberg.org/browse/scores/top"
echo "Obteniendo lista de IDs desde $TOP_URL ..."
wget -q -O top.html "$TOP_URL"
grep -oP '/ebooks/\d+' top.html | sed 's/\/ebooks\///' | sort -u | head -100 > book_ids.txt
rm top.html

COUNT=$(wc -l < book_ids.txt)
echo "Encontrados $COUNT IDs de libros."

SUCCESS=0
FAILED=0

while read -r id; do
    echo -n "Descargando ID: $id ... "
    if wget -q --timeout=15 --tries=2 -O "book_${id}.txt" "https://www.gutenberg.org/files/${id}/${id}-0.txt"; then
        if [ -s "book_${id}.txt" ]; then
            SUCCESS=$((SUCCESS + 1))
            echo "OK"
        else
            rm -f "book_${id}.txt"
            FAILED=$((FAILED + 1))
            echo "FAIL (vacio)"
        fi
    else
        if wget -q --timeout=15 --tries=2 -O "book_${id}.txt" "https://www.gutenberg.org/files/${id}/${id}.txt"; then
            if [ -s "book_${id}.txt" ]; then
                SUCCESS=$((SUCCESS + 1))
                echo "OK (alternativo)"
            else
                rm -f "book_${id}.txt"
                FAILED=$((FAILED + 1))
                echo "FAIL (vacio alternativo)"
            fi
        else
            FAILED=$((FAILED + 1))
            echo "FAIL (no se pudo descargar)"
        fi
    fi
    sleep 0.5
done < book_ids.txt

cd ..
echo "Descarga completada: $SUCCESS exitosos, $FAILED fallidos."
echo "Libros guardados en: $(pwd)/gutenberg_top100"
