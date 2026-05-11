#!/bin/bash

# ### Purpose

# Take every file in a drop directory, validate it, and either archive it or
# quarantine it. Log every action.

# ### Usage

# ```
# ./organize.sh <drop_dir> <archive_dir> <quarantine_dir>
# ```

# For example:

# ```
# ./organize.sh ./drop ./archive ./quarantine
# ```

# ### `--watch` flag: 
# after the initial pass, sleeps for 30 seconds and
# re-scans the drop directory, repeating until the user sends SIGINT (Ctrl-C).
# On SIGINT, log a clean shutdown message and exit 0. Use `trap` to handle the
# signal.

timestamp() {
   timestamp=$(date "+%Y.%m.%d-%H.%M.%S")
}

organize() {
   for file in "$drop_dir"/*.csv; do
      file_name=$(basename "$file")
      timestamp
      echo "[$timestamp] Processing $file (quiet validation)" >> "$log_file"
      bash validate.sh --quiet "$file"
      error=$?
      date=$(date -r "$file" +%Y/%m/%d)

      if [[ "$error" == 0 ]]; then
         mv_file_dir="$archive_dir/$date"
         mkdir -p "$mv_file_dir"
         mv_file="$mv_file_dir/$file_name"
         if [[ -f "$mv_file" ]]; then
            timestamp
            echo "[$timestamp] $file already found in $archive_dir, not archived" >> "$log_file"
         else
            mv "$file" "$mv_file"
            timestamp
            echo "[$timestamp] ARCHIVED: $file -> $archive_dir" >> "$log_file"
         fi

      elif [[ "$error" == 1 ]]; then
         mv_file="$quarantine_dir/$file_name"
         mv "$file" "$mv_file"
         bash validate.sh "$mv_file" 2> "$mv_file.reason"
         timestamp
         echo "[$timestamp] QUARANTINED: $file -> $quarantine_dir" >> "$log_file"

      else
         timestamp
         echo "[$timestamp] ERROR: $file (validate exited $error)" >> "$log_file"
      fi
      echo >> "$log_file"
   done
}

watch_loop() {
   trap 'timestamp; echo "[$timestamp] Caught SIGINT, executing clean shutdown" >> "$log_file"; exit' SIGINT
   while [[ "$watch" == true ]]; do
      timestamp
      echo "[$timestamp] Scanning again in 30s..." >> "$log_file"
      sleep 30
      organize
   done
}

if [[ "$1" == "--watch" ]]; then
   watch=true
   shift
fi

drop_dir="$1"
archive_dir="$2"
quarantine_dir="$3"

log_dir="logs"
log_file="logs/organize.log"
mkdir -p "$log_dir"
touch "$log_file"

if [[ -n "$archive_dir" ]]; then
   mkdir -p "$archive_dir"
fi

if [[ -n "$quarantine_dir" ]]; then
   mkdir -p "$quarantine_dir"
fi

if [[ -d "$drop_dir" ]]; then
   shopt -s nullglob
   files=("$drop_dir"/*)
   if [[ ${#files[@]} -gt 0 ]]; then
      organize
      [[ "$watch" == true ]] && watch_loop
   else
      exit 0
   fi
else
    echo "drop_dir $drop_dir not found." >> "$log_file"
    exit 2
fi

