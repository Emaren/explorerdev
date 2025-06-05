#!/bin/bash
set -e

mkdir -p dist/chains
if [ -d src/chains ]; then
  cp -r src/chains/* dist/chains/ 2>/dev/null || true
fi

mkdir -p dist/logos
if [ -d src/logos ]; then
  cp -r src/logos/* dist/logos/ 2>/dev/null || true
fi
