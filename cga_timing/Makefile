NASM ?= nasm

bin/CGA15.COM: src/cga15.asm
	mkdir -p bin
	$(NASM) -f bin -o $@ $<

clean:
	rm -rf bin

.PHONY: clean
