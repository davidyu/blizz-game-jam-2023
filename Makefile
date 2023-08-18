all: $(patsubst %.asm, %, $(wildcard.asm))

# all gb projects

%: %.asm
	rgbasm -L -o $@.o $^
	rgblink -o $@.gb $@.o
	rgbfix -v -p 0xFF $@.gb
	grep -xq "$@.o" .gitignore || echo $@.o >> .gitignore
