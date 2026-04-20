CC = gcc
CFLAGS = -Wall -O2 -pthread

TARGETS = compress_serial compress_fork compress_pthread \
          decompress_serial decompress_fork decompress_pthread

all: $(TARGETS)

compress_serial: common.o compress_serial.o
	$(CC) $(CFLAGS) -o $@ $^

compress_fork: common.o compress_fork.o
	$(CC) $(CFLAGS) -o $@ $^

compress_pthread: common.o compress_pthread.o
	$(CC) $(CFLAGS) -o $@ $^

decompress_serial: common.o decompress_serial.o
	$(CC) $(CFLAGS) -o $@ $^

decompress_fork: common.o decompress_fork.o
	$(CC) $(CFLAGS) -o $@ $^

decompress_pthread: common.o decompress_pthread.o
	$(CC) $(CFLAGS) -o $@ $^

common.o: common.c common.h
	$(CC) $(CFLAGS) -c common.c

compress_serial.o: compress_serial.c common.h
	$(CC) $(CFLAGS) -c compress_serial.c

compress_fork.o: compress_fork.c common.h
	$(CC) $(CFLAGS) -c compress_fork.c

compress_pthread.o: compress_pthread.c common.h
	$(CC) $(CFLAGS) -c compress_pthread.c

decompress_serial.o: decompress_serial.c common.h
	$(CC) $(CFLAGS) -c decompress_serial.c

decompress_fork.o: decompress_fork.c common.h
	$(CC) $(CFLAGS) -c decompress_fork.c

decompress_pthread.o: decompress_pthread.c common.h
	$(CC) $(CFLAGS) -c decompress_pthread.c

clean:
	rm -f *.o $(TARGETS)

.PHONY: all clean
