all:
	dub build

install:
	mkdir -p ~/.erln8/bin
	cp erln8 ~/.erln8/bin/erln8
	cp erln8 ~/.erln8/bin/reo
	cp erln8 ~/.erln8/bin/reo3

on_a_plane:
	dub build --nodeps

clean:
	dub clean
	rm -f ./reo
	rm -f ./reo3
	rm -f ./erln8
