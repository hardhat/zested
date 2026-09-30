ZAS?=z88dk-z80asm
INCLUDE=-I../Zeal-8-bit-OS/kernel_headers/z88dk-z80asm -Ilib
LIB=$(wildcard lib/*.asm)
OBJ=main.o
TEST_BIN=tests/test_core.bin tests/test_editor.bin tests/test_search.bin tests/test_undo.bin

all: zested.bin

main.o: main.asm $(LIB)
	$(ZAS) $(INCLUDE) -o=main.o main.asm
	
zested.bin: $(OBJ)
	$(ZAS) $(INCLUDE) -m -l -s -b -o=zested.bin $(OBJ)
	cp zested.bin s

tests/test_core.bin: tests/test_core.asm tests/harness.asm $(LIB)
	$(ZAS) $(INCLUDE) -Itests -m -l -s -b -o=$@ tests/test_core.asm

tests/test_editor.bin: tests/test_editor.asm tests/harness.asm tests/edhelpers.asm $(LIB)
	$(ZAS) $(INCLUDE) -Itests -m -l -s -b -o=$@ tests/test_editor.asm

tests/test_search.bin: tests/test_search.asm tests/harness.asm tests/edhelpers.asm $(LIB)
	$(ZAS) $(INCLUDE) -Itests -m -l -s -b -o=$@ tests/test_search.asm

tests/test_undo.bin: tests/test_undo.asm tests/harness.asm tests/edhelpers.asm $(LIB)
	$(ZAS) $(INCLUDE) -Itests -m -l -s -b -o=$@ tests/test_undo.asm

# Runs the unit tests headless in zeal-native; fails on any failed check.
test: $(TEST_BIN)
	sh tests/run_tests.sh tests/test_core.bin core
	sh tests/run_tests.sh tests/test_editor.bin editor
	sh tests/run_tests.sh tests/test_search.bin search
	sh tests/run_tests.sh tests/test_undo.bin undo

clean:
	-rm $(OBJ)
	-rm zested.bin
	-rm main.sym zested.map main.lis
	-rm tests/*.bin tests/*.map tests/*.sym tests/*.lis tests/*.o
