#!/bin/bash

# ### Purpose

# Run a configuration-driven processing pipeline against a directory of CSV
# files: validate them, filter rows by criteria, merge the survivors, and write
# a summary report.

# ### Usage

# ```
# ./pipeline.sh <config_file>
# ```

# For example:

# ```
# ./pipeline.sh pipeline.conf
# ```


check_col_and_val() {
   
   for acceptable_col in "${acceptable_cols[@]}"; do
      ((FILTER_COLUMN_idx++))
      if [[ "$FILTER_COLUMN" == "$acceptable_col" ]]; then
         echo "Pass: FILTER_COLUMN ($FILTER_COLUMN is one of: ${acceptable_cols[*]})"
         "check_val_${FILTER_COLUMN}"
         return 0
      fi
   done
   echo "Error: FILTER_COLUMN ($FILTER_COLUMN not one of: ${acceptable_cols[*]})"
   exit 2
}

check_val_transaction_id() {
   check_val_PATTERN_FORM '^T[0-9]{8}$'
}
check_val_date() {
   check_val_PATTERN_FORM '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1])$'
}
check_val_store_id() {
   check_val_PATTERN_FORM '^store_[0-9]{3}$'
}
check_val_product() {
   check_val_PATTERN_FORM '^(gadget|widget|kit|tool)-[a-z]+$' 
}
check_val_units() {
   check_val_PATTERN_FORM '^[1-9]+[0-9]*$'
}
check_val_revenue() {
   check_val_PATTERN_FORM '^[1-9]+[0-9]*\.[0-9]{2}$'
}
check_val_status() {
   check_val_ARRAY_FORM
}

check_val_ARRAY_FORM() {
   local acceptable_vals_varname="acceptable_vals_${FILTER_COLUMN}"
   declare -n acceptable_vals="$acceptable_vals_varname"
   for acceptable_val in "${acceptable_vals[@]}"; do
      if [[ "$FILTER_VALUE" == "$acceptable_val" ]]; then
         echo "Pass: FILTER_VALUE ($FILTER_VALUE is one of: ${acceptable_vals[*]})"
         return 0
      fi
   done
   echo "Error: FILTER_VALUE ($FILTER_VALUE not one of: ${acceptable_vals[*]})"
   exit 2
}

check_val_PATTERN_FORM(){
   local pattern=$1
   if [[ "$FILTER_VALUE" =~ $pattern ]]; then
      echo "Pass: FILTER_VALUE ($FILTER_VALUE has form: $pattern)"
      return 0
   fi
   echo "Error: FILTER_VALUE ($FILTER_VALUE does not have form: $pattern)"
   exit 2
}


configuration() {
   source "$config_file"

   if [[ ! -z "$FILTER_COLUMN" ]]; then
      if [[ ! -z "$FILTER_VALUE" ]]; then
         check_col_and_val
      else
         echo "Error: FILTER_VALUE ($FILTER_VALUE) missing/valueless in config"
         exit 2
      fi
   else
      echo "Error: FILTER_COLUMN ($FILTER_COLUMN) missing/valueless in config"
      exit 2
   fi

   if [[ ! -z "$SOURCE_DIR" ]]; then
      if [[ ! -r "$SOURCE_DIR" ]]; then
         echo "Error: SOURCE_DIR ($SOURCE_DIR) does not exist or not readable"
         exit 2
      fi
   else
      echo "Error: SOURCE_DIR missing/valueless in config"
      exit 2
   fi

   keys=("DATE_COLUMN" "DATE_AFTER" "OUTPUT_DIR" "MERGED_FILE" "REPORT_FILE")
   values=("$DATE_COLUMN" "$DATE_AFTER" "$OUTPUT_DIR" "$MERGED_FILE" "$REPORT_FILE")
   for i in "${!keys[@]}"; do
      if [[ -z "${values[$i]}" ]]; then
         echo "Error: ${keys[$i]} missing/valueless in config"
         exit 2
      fi
   done

   echo "[1/4] Completed: configuration..."
}

validate() {
   local total_errors
   local files
   shopt -s nullglob
   files=("$SOURCE_DIR"/*.csv)
   if [[ ${#files[@]} -eq 0 ]]; then
      echo "$SOURCE_DIR does not contain any .csv files"
      exit 1
   fi
   touch "$tmp_file"
   for file in "${files[@]}"; do
      file_name=$(basename "$file")
      total_errors=$(bash validate.sh "$file" --return-total-errors)
      if [[ $total_errors == 0 ]]; then
         passed_files+=("$file")
      else
         failed_files+=("$file")
         printf "\t\t%s (%d validation problems)\n" "$file_name" "$total_errors" >> "$tmp_file"
      fi   
   done
   printf "\n" >> "$tmp_file"
   echo "[2/4] Completed: validate..."
}

filter_and_merge() {
   merged_file="$OUTPUT_DIR/$MERGED_FILE"
   if [[ ! -d "$OUTPUT_DIR" ]]; then
      mkdir "$OUTPUT_DIR"
   fi
   if [[ ! -f "$merged_file" ]]; then
      touch "$merged_file"
   fi
   (IFS=','; echo "${acceptable_cols[*]}") > "$merged_file"
   for file in "${passed_files[@]}"; do
      counters=$(awk -v merged_file="$merged_file" -v FILTER_COLUMN_idx="$FILTER_COLUMN_idx" -v FILTER_VALUE="$FILTER_VALUE" -v DATE_AFTER="$DATE_AFTER" -v DATE_COLUMN="$DATE_COLUMN" -F',' '
      NR==1 {
         for (i = 1; i <= NF; i++) {
            if ($i == DATE_COLUMN) {
               date_idx = i
            }
         }
         next
      }
      NR>1 {
         total++
         if ($FILTER_COLUMN_idx == FILTER_VALUE) {
            if (date_idx != "" && date_idx <= NF && date_idx >= 1) {
               if ($date_idx >= DATE_AFTER) {
                  passing++
                  print >> merged_file
               }
            }
         }
      }
      END {
            printf "%d %d\n", passing, total
      }
      ' "$file")   
      read passing total <<< "$counters"
      ((total_rows_passing += passing))
      ((total_rows += total))
   done
   echo "[3/4] Completed: filter and merge..."
}

report() {
   report_file="$OUTPUT_DIR/$REPORT_FILE"
   if [[ ! -f "$report_file" ]]; then
      touch "$report_file"
   fi

   {
   printf "HW2 Pipeline Summary Report\n"
   printf "Generated: %s\n\n" "$(date "+%Y-%m-%dT%H:%M:%S")"

   printf "Configuration:\n"
   printf "\t%-20s %5s\n" "Source dir:" "$SOURCE_DIR"
   printf "\t%-20s %5s = %s\n" "Filter:" "$FILTER_COLUMN" "$FILTER_VALUE"
   printf "\t%-20s %5s\n" "Date filter:" "date >= $DATE_AFTER"
   printf "\t%-20s %5s\n\n" "Output:" "$OUTPUT_DIR/$MERGED_FILE"

   printf "Validation results:\n"
   printf "\t%-20s %5d\n" "CSV files found:" "${#files[@]}"
   printf "\t%-20s %5d\n" "Valid:" "${#passed_files[@]}"
   printf "\t%-20s %5d\n" "Invalid:" "${#failed_files[@]}"
   printf "\tSkipped files:\n"
   cat "$tmp_file"
   rm -f "$tmp_file"

   printf "Row counts:\n"
   printf "\t%-25s %5d\n" "Total input rows:" "$total_rows"
   printf "\t%-25s %5d\n" "Rows passing filter:" "$total_rows_passing"
   local num_rows=$(tail -n +2 "$merged_file" | wc -l)
   printf "\t%-25s %5d\n\n" "Rows in merged output:" "$num_rows"

   printf "Top 5 stores by total revenue:\n"
   awk -F',' '
   NR>1 {
      store_revenue[$3] += $6
   }
   END {
      for (store in store_revenue) {
        printf "%s\t%.2f\n", store, store_revenue[store]
      }
   }
   ' "$merged_file" | sort -k 2,2 -nr | head -n 5 |
   while read -r store revenue; do
      printf "\t%-15s $%'5.2f\n" "$store" "$revenue"
   done

   } > "$report_file"

   echo "[4/4] Completed: report..."
}

config_file=$1

SOURCE_DIR=""
FILTER_COLUMN=""
FILTER_VALUE=""
DATE_COLUMN=""
DATE_AFTER=""
OUTPUT_DIR=""
MERGED_FILE=""
REPORT_FILE=""
FILTER_COLUMN_idx=0

acceptable_cols=("transaction_id" "date" "store_id" "product" "units" "revenue" "status")
acceptable_vals_status=("completed" "cancelled" "pending" "refunded")

tmp_file=$(mktemp)
files=()
passed_files=()
failed_files=()
total_rows_passing=0
total_rows=0

configuration
validate
filter_and_merge
report

exit 0