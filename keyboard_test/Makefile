NASM ?= nasm

all: bin/KBTEST.COM bin/ENHKB.COM

bin/KBTEST.COM: src/kbtest.asm
	mkdir -p bin
	$(NASM) -f bin -o $@ $<

bin/ENHKB.COM: src/enhkb.asm
	mkdir -p bin
	$(NASM) -f bin -o $@ $<

clean:
	rm -rf bin

.PHONY: all clean
