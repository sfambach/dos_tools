NASM ?= nasm

bin/TRIEMU.COM: src/triemu.asm
	mkdir -p bin
	$(NASM) -f bin -o $@ $<

clean:
	rm -rf bin

.PHONY: clean
