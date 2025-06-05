#!/bin/bash

echo "🔍 Checking symbol/display consistency..."

for dir in chains/mainnet src/chains/mainnet public/chains/mainnet dist/chains/mainnet; do
  target="/var/www/explorerdev/$dir"
  if [ -d "$target" ]; then
    for f in "$target"/*.json; do
      [ -e "$f" ] || continue
      mismatches=$(jq -r '
        .assets[] | select(.symbol != .display)
        | "❌ Mismatch in '"$f"': symbol=\(.symbol), display=\(.display)"' "$f")
      if [ -n "$mismatches" ]; then
        echo "$mismatches"
        echo -n "⚠️  Fix this file by updating display to match symbol? (y/n): "
        read -r answer
        if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
          tmpfile=$(mktemp)
          jq '.
            assets |= map(
              if .symbol != .display then
                .display = .symbol
              else .
              end
            )' "$f" > "$tmpfile" && mv "$tmpfile" "$f"
          echo "✅ Fixed $f"
        fi
      else
        echo "✅ Match in $f"
      fi
    done
  fi
done
