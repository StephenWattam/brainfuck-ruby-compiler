LD=ld
LDFLAGS=-s 
ENTRY_POINT=_start # ld -e $(ENTRY_POINT)

GAS=as
GASFLAGS= -mtune=i686 -o test


all:	
	mkdir -p test
	ruby bfcompile.rb i=mandel.b o=test/test.s -foptimise -tapesize=30000 -eof=0 -simtime=3600 -attemptstatic -dotfile=test/test.dot

#	-dotfile=test/test.dot -simtime=20 -attemptstatic
#	-debugcodegen -noboundcheck
	$(GAS) $(GASFLAGS) test/test.s -o test/test.o
	$(LD) $(LDFLAGS) test/test.o -o test/test
	#zgrv test/test.dot

test: all
	echo "--------"
	echo "TEST" | ./test/test

clean:
	rm -rv test/*
	rmdir test
