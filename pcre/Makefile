ALL_CFLAGS = $(CFLAGS) -I pcre
OCAMLOPT=ocamlopt
OCAMLC=ocamlc
SRC = pcre.ml pcre_stubs.c

all: bytecode native

bytecode: pcre.cma

native: pcre.cmxa

pcre.cma: pcre_stubs.o pcre.ml
	$(OCAMLC) -a -o pcre.cma $(LIBS) pcre.ml

pcre.cmxa: pcre.ml pcre_stubs.o
	$(OCAMLOPT) -a -o pcre.cmxa $(LIBS) pcre.ml

pcre_stubs.o: pcre_stubs.c
	$(OCAMLC) $(ALL_CFLAGS) pcre_stubs.c

clean:
	rm -f pcre.cma pcre.cmi pcre.cmx pcre.cmxa pcre.o pcre.obj pcre_stubs.obj pcre_stubs.o
	rm -f pcre.a libpcre.a libpcre.lib pcre.cmo

.PHONY: all bytecode native clean
Makefile: ;
$(SRC): ;
