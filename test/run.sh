#!/bin/bash -e
tmpdir=$(mktemp -d)
trap 'rm -rf "$world"' EXIT

[ -f game.conf ] || { echo "Must be run in game root folder." >&2; exit 1; }

mkdir -p "$tmpdir/world"
cp -v test/world.mt "$tmpdir/world/"
chmod -R a+rwX "$tmpdir" # needed because server runs as unprivileged user inside container

[ -z "$DOCKER_IMAGE" ] && DOCKER_IMAGE="ghcr.io/luanti-org/luanti:master"
confinside=
docker run --rm -i \
	-v "$PWD/test/minetest.conf":/etc/minetest/minetest.conf \
	-v "$tmpdir":/var/lib/minetest/.minetest \
	-v "$PWD":/var/lib/minetest/.minetest/games/minetest_classic \
	"$DOCKER_IMAGE"

exit 0
