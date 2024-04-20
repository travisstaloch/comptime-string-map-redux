#!/bin/bash

poop=../poop/zig-out/bin/poop
num=$((1000*1000))

set -xe
rm -rf zig-out/

function bench() {
  zig build -Doptimize=$1 -Dmode=rev -Dnum-iters=$num
  cp zig-out/bin/bench zig-out/bin/bench-rev
  zig build -Doptimize=$1 -Dmode=std -Dnum-iters=$num
  cp zig-out/bin/bench zig-out/bin/bench-std
  
  $poop -d 3000 "zig-out/bin/bench-std" "zig-out/bin/bench-rev"
}

bench Debug
bench ReleaseSafe
bench ReleaseSmall
bench ReleaseFast
