#!/bin/bash

LOG_FILE="/var/log/nginx/access.log"
# Set this to your own public IP (the one you browse from)
MY_IP="142.59.71.34"

declare -A seen_ip
declare -A hit_counts
declare -A last_ua

# Helper: truncate a string to max length $1, append “..” if truncated
truncate() {
  local max="$1"
  local s="$2"
  if (( ${#s} > max )); then
    echo "${s:0:$((max-2))}.."
  else
    echo "$s"
  fi
}

# Compute column widths dynamically
compute_widths() {
  # Get current terminal width
  local total_cols
  total_cols=$(tput cols)

  # Fixed‐width columns:
  IP_W=20
  HITS_W=6
  LOC_W=15
  TYPE_W=8
  STATUS_W=6
  PATH_W=10   # We show only the last 10 chars of any Path

  # There are 7 columns → 6 separators (“ | ”) of width 3 each = 18
  SEP_COUNT=6
  SEP_WIDTH=3
  TOTAL_SEP_WIDTH=$(( SEP_COUNT * SEP_WIDTH ))

  # Sum of fixed widths + separators + 1 for safety
  local used=$(( IP_W + HITS_W + LOC_W + TYPE_W + STATUS_W + PATH_W + TOTAL_SEP_WIDTH + 1 ))

  # Remaining space → UA column
  UA_W=$(( total_cols - used ))
  (( UA_W < 15 )) && UA_W=15
}

# Print header (single line) with dynamic widths
print_header() {
  compute_widths

  local fmt=" %-${IP_W}s | %-${HITS_W}s | %-${LOC_W}s | %-${TYPE_W}s | %-${STATUS_W}s | %-${PATH_W}s | %-${UA_W}s\n"
  printf "$fmt" "IP" "Hits" "Location" "Type" "Status" "Path" "User-Agent"

  # Separator line
  local total_line_width=$(( IP_W + HITS_W + LOC_W + TYPE_W + STATUS_W + PATH_W + UA_W + TOTAL_SEP_WIDTH + 1 ))
  printf '%*s\n' "$total_line_width" '' | tr ' ' '-'
}

# --- MAIN LOOP ---

clear
echo -e "\033[1;34m🔎 Wolo Traffic Monitor\033[0m"
echo "Monitoring: $LOG_FILE"
print_header

tail -n0 -F "$LOG_FILE" | while read -r line; do
  # Recompute widths if terminal resized
  compute_widths

  # Extract IP (field 1), Status (field 9), Path (field 7)
  ip=$(awk '{print $1}' <<<"$line")
  status=$(awk '{print $9}' <<<"$line")
  path=$(awk '{print $7}' <<<"$line")

  # Extract full UA via awk (sixth double-quoted segment)
  ua_full=$(awk -F\" '{print $6}' <<<"$line")

  # If no UA or no IP, skip
  [[ -z "$ip" || -z "$ua_full" ]] && continue

  # Increment hit count
  hit_counts["$ip"]=$(( hit_counts["$ip"] + 1 ))
  last_ua["$ip"]="$ua_full"

  # Only output when first seeing this IP
  if [[ -z "${seen_ip[$ip]}" ]]; then
    seen_ip["$ip"]=1

    # Lookup location once
    loc=$(geoiplookup "$ip" 2>/dev/null \
          | cut -d ',' -f2- \
          | sed 's/GeoIP.*: //' \
          | tr -d '\n')
    [[ -z "$loc" ]] && loc="Unknown"

    # Determine “Type” from UA
    if [[ "$ua_full" =~ (bot|crawl|spider|Barkrowler|Censys) ]]; then
      vtype="Bot"
    elif [[ "$ua_full" =~ (curl|wget|python|Scrapy) ]]; then
      vtype="Scraper"
    elif [[ "$ua_full" =~ (Mozilla|Chrome|Safari|Edge|Firefox) ]]; then
      vtype="User"
    else
      vtype="Other"
    fi

    # Mark your own IP
    if [[ "$ip" == "$MY_IP" ]]; then
      ip_label="$ip (me)"
    else
      ip_label="$ip"
    fi

    # Color by Type
    if [[ "$vtype" == "Bot" ]]; then
      color="\033[0;31m"
    elif [[ "$vtype" == "Scraper" ]]; then
      color="\033[0;33m"
    elif [[ "$vtype" == "User" ]]; then
      color="\033[0;32m"
    else
      color="\033[0;36m"
    fi

    # Truncate Path to its last 10 chars
    if (( ${#path} > PATH_W )); then
      path_short="${path: -PATH_W}"
    else
      path_short="$path"
    fi

    # --- Extract device/OS from first parentheses using =~ ---
    if [[ "$ua_full" =~ \(([^\)]*)\) ]]; then
      ua_inner="${BASH_REMATCH[1]}"
    else
      ua_inner="Unknown"
    fi

    # --- Determine Browser token ---
    if [[ "$ua_full" =~ "Edg/" ]]; then
      browser="Edge"
    elif [[ "$ua_full" =~ "Chrome/" ]] && [[ ! "$ua_full" =~ "Edg/" ]]; then
      browser="Chrome"
    elif [[ "$ua_full" =~ "Firefox/" ]]; then
      browser="Firefox"
    elif [[ "$ua_full" =~ "Safari/" ]] && [[ ! "$ua_full" =~ "Chrome/" ]]; then
      browser="Safari"
    else
      browser="Unknown"
    fi

    # Combine into “device/OS | Browser”
    ua_display="$ua_inner | $browser"

    # Truncate columns to fit widths
    loc_short=$(truncate $LOC_W "$loc")
    vtype_short=$(truncate $TYPE_W "$vtype")
    status_short=$(truncate $STATUS_W "$status")
    path_short=$(truncate $PATH_W "$path_short")
    ua_short=$(truncate $UA_W "$ua_display")

    # Print one line
    fmt=" %-${IP_W}s | %-${HITS_W}s | %-${LOC_W}s | %-${TYPE_W}s | %-${STATUS_W}s | %-${PATH_W}s | %-${UA_W}s\033[0m\n"
    printf "$color$fmt" \
           "$ip_label" \
           "${hit_counts[$ip]}" \
           "$loc_short" \
           "$vtype_short" \
           "$status_short" \
           "$path_short" \
           "$ua_short"
  fi
done
