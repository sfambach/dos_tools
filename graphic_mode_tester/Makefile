NASM ?= nasm

bin/GMTEST.COM: src/gmtest.asm
	mkdir -p bin
	$(NASM) -f bin -o $@ $<

screenshots: bin/GMTEST.COM
	tools/screenshots.sh

clean:
	rm -rf bin

.PHONY: screenshots clean
