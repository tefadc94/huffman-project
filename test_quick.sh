#!/bin/bash

echo "=== Creating test files ==="
mkdir -p test_input
echo "Hello World! This is a test file for Huffman compression." > test_input/file1.txt
echo "Another file with completely different content to test multiple files." > test_input/file2.txt
echo "Short" > test_input/file3.txt
for i in {1..100}; do
    echo "Line $i: The quick brown fox jumps over the lazy dog." >> test_input/large.txt
done

echo ""
echo "=== Testing Serial Compression ==="
./compress_serial test_input output_serial.huf

echo ""
echo "=== Testing Serial Decompression ==="
./decompress_serial output_serial.huf decompress_serial_out

echo ""
echo "=== Verifying ==="
if diff -r test_input decompress_serial_out > /dev/null; then
    echo "SUCCESS: Serial compression/decompression works!"
else
    echo "FAILED: Mismatch between original and decompressed"
fi

echo ""
echo "=== Testing Fork (2 processes) ==="
./compress_fork test_input output_fork.huf 2
./decompress_fork output_fork.huf decompress_fork_out 2

if diff -r test_input decompress_fork_out > /dev/null; then
    echo "SUCCESS: Fork version works!"
else
    echo "FAILED: Fork version mismatch"
fi

echo ""
echo "=== Testing Pthread (2 threads) ==="
./compress_pthread test_input output_pthread.huf 2
./decompress_pthread output_pthread.huf decompress_pthread_out 2

if diff -r test_input decompress_pthread_out > /dev/null; then
    echo "SUCCESS: Pthread version works!"
else
    echo "FAILED: Pthread version mismatch"
fi

echo ""
echo "=== All tests completed ==="
