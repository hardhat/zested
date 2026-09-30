ZAS?=z88dk-z80asm
INCLUDE=-I../Zeal-8-bit-OS/kernel_headers/z88dk-z80asm -Ilib
LIB=$(wildcard lib/*.asm)
OBJ=main.o
TEST_BIN=tests/test_core.bin

all: zested.bin

main.o: main.asm $(LIB)
	$(ZAS) $(INCLUDE) -o=main.o main.asm
	
zested.bin: $(OBJ)
	$(ZAS) $(INCLUDE) -m -l -s -b -o=zested.bin $(OBJ)
	cp zested.bin s

$(TEST_BIN): tests/test_core.asm tests/harness.asm $(LIB)
	$(ZAS) $(INCLUDE) -Itests -m -l -s -b -o=$(TEST_BIN) tests/test_core.asm

# Runs the unit tests headless in zeal-native; fails on any failed check.
test: $(TEST_BIN)
	sh tests/run_tests.sh $(TEST_BIN)

clean:
	-rm $(OBJ)
	-rm zested.bin
	-rm main.sym zested.map main.lis
	-rm tests/test_core.bin tests/test_core.map tests/test_core.sym tests/test_core.lis tests/test_core.o
