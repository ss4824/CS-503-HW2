#!/bin/bash

# ### Purpose

# Check a CSV file against the schema above and report any problems. Optionally
# produce a cleaned copy.

# ### Usage

# ```
# ./validate.sh [--fix] [--quiet] <file.csv>
# ```

# | Flag | Behavior |
# |---|---|
# | `--fix` | Produce a cleaned-up copy at `<file>.fixed.csv` instead of just reporting |
# | `--quiet` | Suppress the human-readable report; only set the exit code |
# | `--return-total-errors` | Return total errors to stdout
# | (none) | Print a report to stderr, set exit code |

quiet_true() {
   total_errors=0
   local file=$1

   # if file doesnt exist or not readable
   if [[ ! -r "$file" ]]; then
      ((total_errors++))
      exit_code=2
      return
   fi

   # if file empty 
   if [[ ! -s "$file" ]]; then
      ((total_errors++))
      exit_code=1
      return
   fi

   # if header row not the 7 column names in order
   expected_header='transaction_id,date,store_id,product,units,revenue,status'
   if [[ "$(head -1 "$file")" != "$expected_header" ]]; then
      ((total_errors++))
      exit_code=1
   fi

   # if any row does not have 7 values
   errors=$(awk -F',' '
   NR>1 && NF != 7 {
      errors++
   } 
   END {
      print errors+0
   }
   ' "$file")

   if [[ "$errors" -gt 0 ]]; then
      ((total_errors += errors))
      exit_code=1
   fi

   # if any values contain leading/trailing whitespace
   errors=$(awk -F',' '
   NR>1 {
      sub(/\r$/, "")
      for (i = 1; i <= NF; i++) {
         if ($i ~ /^[[:space:]]+/ || $i ~ /[[:space:]]+$/) {
            errors++
         }
      }
   }
   END {
      print errors+0
   }
   ' "$file")

   if [[ "$errors" -gt 0 ]]; then
      ((total_errors += errors))
      exit_code=1
   fi

   # if any rows are byte-identical
   errors=$(awk -F ',' '
   NR>1 && (++rows[$0] > 1) {
      errors++
   } 
   END {
      print errors+0
   }
   ' "$file")

   if [[ "$errors" -gt 0 ]]; then
      ((total_errors += errors))
      exit_code=1
   fi

   # if any line ends with something besides \n
   errors=$(awk '
   NR>1 && sub(/\r$/, "") {
      errors++
   } 
   END {
      print errors+0
   }
   ' "$file")

   if [[ "$errors" -gt 0 ]]; then
      ((total_errors += errors))
      exit_code=1
   fi
}

quiet_false() {
   total_errors=0 
   local file=$1

   # if file doesnt exist or not readable
   if [[ ! -r "$file" ]]; then
      printf "%s: File does not exist or not readable\n" "$file" >> "/dev/stderr"
      ((total_errors++))
      exit_code=2
   fi

   # if file empty 
   if [[ ! -s "$file" ]]; then
      printf "%s: File empty\n" "$file" >> "/dev/stderr"
      ((total_errors++))
      exit_code=1
   fi

   # if header row not the 7 column names in order
   expected_header='transaction_id,date,store_id,product,units,revenue,status'
   if [[ "$(head -1 "$file")" != "$expected_header" ]]; then
      ((total_errors++))
      exit_code=1
      printf "%s: File header does not match the expected value\n" "$file" >> "/dev/stderr"
   fi

   # if any row does not have 7 values
   errors=$(awk -F',' -v file="$file" '
   NR>1 && NF != 7 {
      printf "%s: Line %d does not have 7 values\n", file, NR >> "/dev/stderr"
      errors++
   } 
   END {
      print errors+0
   }
   ' "$file")

   if [[ "$errors" -gt 0 ]]; then
      ((total_errors += errors))
      exit_code=1
   fi

   # if any values contain leading/trailing whitespace
   errors=$(awk -F',' -v file="$file" '
   NR>1 {
      sub(/\r$/, "")
      for (i = 1; i <= NF; i++) {
         if ($i ~ /^[[:space:]]+/ || $i ~ /[[:space:]]+$/) {
            printf "%s: Line %d Col %d has leading/trailing whitespace\n", file, NR, i >> "/dev/stderr"
            errors++
         }
      }
   }
   END {
      print errors+0
   }
   ' "$file")

   if [[ "$errors" -gt 0 ]]; then
      ((total_errors += errors))
      exit_code=1
   fi

   # if any rows are byte-identical
   errors=$(awk -v file="$file" '
   NR>1 && (++rows[$0] > 1) {
      printf "%s: Line %d is byte-identical to a previous line\n", file, NR >> "/dev/stderr"
      errors++
   } 
   END {
      print errors+0
   }
   ' "$file")

   if [[ "$errors" -gt 0 ]]; then
      ((total_errors += errors))
      exit_code=1
   fi

   # if any line ends with something besides \n
   errors=$(awk -v file="$file" '
   NR>1 && sub(/\r$/, "") {
      printf "%s: Line %d has CRLF line ending\n", file, NR >> "/dev/stderr"
      errors++
   } 
   END {
      print errors+0
   }
   ' "$file")

   if [[ "$errors" -gt 0 ]]; then
      ((total_errors += errors))
      exit_code=1
   fi

   print_num_problems "$task"
}

print_num_problems() {
   local action=$1
   if [[ "$total_errors" -gt 0 ]]; then
      printf "INVALID (%d problem(s) found in %s after %s)\n" "$total_errors" "$file" "$action" >> "/dev/stderr"
   else
      printf "VALID (%d problems found in %s after %s)\n" "$total_errors" "$file" "$action" >> "/dev/stderr"
   fi
}

exit_code=0
fix=false
quiet=false
return_total_errors=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix) fix=true ;;
        --quiet) quiet=true ;;
        --return-total-errors) return_total_errors=true ;;
        *) file="$1" ;;
    esac
    shift
done

task="validation"
if [[ "$fix" == true ]]; then
   task="fixing"
   fixed_file="${file%%.*}.fixed.csv"
   tmp_file=$(mktemp)
   awk -F',' '
   BEGIN { 
      OFS=","
   }
   NR==1 { 
      print
      next 
   }
   NR>1 {
      sub(/\r$/, "")
      for (i = 1; i <= NF; i++) {
         gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
      }
      if (!row_forms[$0]++)
         print
   }' "$file" > "$tmp_file" && mv "$tmp_file" "$fixed_file"
   quiet_true "$fixed_file"
else
   if [[ "$quiet" == true ]]; then
      quiet_true "$file"
   else
      quiet_false "$file"
   fi
fi

if [[ "$return_total_errors" == true ]]; then
   printf "%d" "$total_errors"
fi

exit $exit_code
