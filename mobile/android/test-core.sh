#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
if command -v javac >/dev/null 2>&1; then
  javac -encoding UTF-8 --release 17 -d "$test_dir" app/src/main/java/com/consegvida/app/core/*.java tests/ProgressTests.java
else
  java -m jdk.compiler/com.sun.tools.javac.Main -encoding UTF-8 --release 17 -d "$test_dir" app/src/main/java/com/consegvida/app/core/*.java tests/ProgressTests.java
fi
java -ea -cp "$test_dir" com.consegvida.app.core.ProgressTests
