NASM ?= nasm

bin/KBTEST.COM: src/kbtest.asm
	mkdir -p bin
	$(NASM) -f bin -o $@ $<

clean:
	rm -rf bin

.PHONY: clean
