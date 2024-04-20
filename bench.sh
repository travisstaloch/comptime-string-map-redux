#!/bin/bash

num=1000000
poop=../poop/zig-out/bin/poop
set -xe

opt=Debug
zig build-exe bench.zig -O$opt
$poop "./bench std $num" "./bench rev $num"

opt=ReleaseSafe
zig build-exe bench.zig -O$opt
$poop "./bench std $num" "./bench rev $num"

opt=ReleaseSmall
zig build-exe bench.zig -O$opt
$poop "./bench std $num" "./bench rev $num"

opt=ReleaseFast
zig build-exe bench.zig -O$opt
$poop "./bench std $num" "./bench rev $num"

