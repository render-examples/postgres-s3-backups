#!/bin/bash

set -o errexit -o pipefail

copy_table() {
    local table_name="$1"
    local last_updated_at="$2"
    local max_created_at="$3"
    local temp_table_name="temp_$table_name"
    local non_generated_columns
    local insert_command

    # Validate last_updated_at argument
    if ! [[ $last_updated_at =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}([ T][0-9]{2}:[0-9]{2}:[0-9]{2})?$ ]]; then
        echo "Error: last_updated_at is not a valid date or datetime string."
        return 1
    fi

    echo "Copying $table_name"

    # Create a temporary table in the target database
    psql -c "CREATE TABLE IF NOT EXISTS $temp_table_name (LIKE $table_name INCLUDING DEFAULTS);" $TARGET_DATABASE
    psql -c "TRUNCATE TABLE $temp_table_name;" $TARGET_DATABASE

    # Copy data from source to temporary table in target
    psql -c "COPY (SELECT * FROM $table_name WHERE updated_at > '$last_updated_at' AND created_at < '$max_created_at') TO STDOUT;" $SOURCE_DATABASE | psql -c "COPY $temp_table_name FROM STDIN;" $TARGET_DATABASE

    # Generate the INSERT INTO ... ON CONFLICT command
    non_generated_columns=$(psql -qtAX -c "SELECT string_agg('\"' || column_name || '\"', ', ') FROM information_schema.columns WHERE table_name = '$table_name' AND is_generated = 'NEVER';" $TARGET_DATABASE)
    insert_command=$(psql -qtAX -c "SELECT 'INSERT INTO $table_name ($non_generated_columns) SELECT $non_generated_columns FROM $temp_table_name ON CONFLICT (id) DO UPDATE SET ' || string_agg('\"' || column_name || '\"' || ' = EXCLUDED.' || column_name, ', ') FROM information_schema.columns WHERE table_name = '$table_name' AND column_name <> 'id' AND is_generated = 'NEVER';" $TARGET_DATABASE)

    # if table name is soundings, then we need a special constraint
    if [[ $table_name == "soundings" ]]; then
        insert_command="INSERT INTO soundings (id, mission_id, entrance_transmission_id, exit_transmission_id, distance, distance_with_gps, distance_with_temperature, distance_with_pressure, distance_with_humidity, min_altitude, max_altitude, height_agl, entered_at, exited_at, entrance_cell, exit_cell, created_at, updated_at) SELECT id, mission_id, entrance_transmission_id, exit_transmission_id, distance, distance_with_gps, distance_with_temperature, distance_with_pressure, distance_with_humidity, min_altitude, max_altitude, height_agl, entered_at, exited_at, entrance_cell, exit_cell, created_at, updated_at FROM temp_soundings ON CONFLICT (mission_id, entered_at) DO UPDATE SET id = EXCLUDED.id, entrance_transmission_id = EXCLUDED.entrance_transmission_id, exit_transmission_id = EXCLUDED.exit_transmission_id, distance = EXCLUDED.distance, distance_with_gps = EXCLUDED.distance_with_gps, distance_with_temperature = EXCLUDED.distance_with_temperature, distance_with_pressure = EXCLUDED.distance_with_pressure, distance_with_humidity = EXCLUDED.distance_with_humidity, min_altitude = EXCLUDED.min_altitude, max_altitude = EXCLUDED.max_altitude, height_agl = EXCLUDED.height_agl, exited_at = EXCLUDED.exited_at, entrance_cell = EXCLUDED.entrance_cell, exit_cell = EXCLUDED.exit_cell, created_at = EXCLUDED.created_at, updated_at = EXCLUDED.updated_at"
    fi

    echo "$insert_command"

    # Execute the command
    psql -c "$insert_command" $TARGET_DATABASE

    psql -c "DROP TABLE $temp_table_name;" $TARGET_DATABASE

    echo
}

copy_all_tables() {
    local last_updated_at="$1"
    local max_created_at="$2"
    local tables_with_updated_at
    local priority_tables=("users" "missions" "transmissions" "ballast_assemblies" "modems" "main_boards" "sensor_boards" "sensor_suites" "apexes")
    local priority_tables_string

    # Validate last_updated_at argument
    if ! [[ $last_updated_at =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}([ T][0-9]{2}:[0-9]{2}:[0-9]{2})?$ ]]; then
        echo "Error: last_updated_at is not a valid date or datetime string."
        return 1
    fi

    # Copy special tables first if they exist
    for special_table in "${priority_tables[@]}"; do
        if psql -qtAX -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$special_table');" $TARGET_DATABASE | grep -q 't'; then
            copy_table "$special_table" "$last_updated_at" "$max_created_at"
        fi
    done

    # Convert priority_tables array to a comma-separated string
    priority_tables_string=$(printf ",'%s'" "${priority_tables[@]}")
    priority_tables_string="${priority_tables_string:1}"

    # Get list of other tables with 'updated_at' column, excluding special tables
    tables_with_updated_at=$(psql -qtAX -c "SELECT table_name FROM information_schema.columns WHERE column_name = 'updated_at' AND table_schema = 'public' AND table_name NOT LIKE 'temp_%' AND table_name NOT IN ($priority_tables_string) AND table_name NOT IN ('ar_internal_metadata');" $TARGET_DATABASE)

    # Loop through other tables and call copy_table for each
    for table in $tables_with_updated_at; do
        copy_table "$table" "$last_updated_at" "$max_created_at"
    done
}

main() {
    local last_updated_at="$1"
    local current_timestamp

    local current_timestamp=$(date +%s)
    local two_weeks_ago_timestamp=$((current_timestamp - (14 * 24 * 60 * 60)))
    local default_last_updated_at=$(date -j -f "%s" "$two_weeks_ago_timestamp" +"%Y-%m-%d")

    # Get current UTC timestamp
    current_timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")

    if [[ $DEFAULT_START =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}([ T][0-9]{2}:[0-9]{2}:[0-9]{2})?$ ]]; then
        default_last_updated_at="$DEFAULT_START"
    fi

    # if last_updated_at wasn't set or if it was invalid...
    if ! [[ $last_updated_at =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}([ T][0-9]{2}:[0-9]{2}:[0-9]{2})?$ ]]; then
      # Check if last_incremental_copy.txt exists and read from it
      if [[ -f "last_incremental_copy.txt" ]]; then
          last_updated_at=$(cat "last_incremental_copy.txt")

          if ! [[ $last_updated_at =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}([ T][0-9]{2}:[0-9]{2}:[0-9]{2})?$ ]]; then
              echo "last_updated_at is not a valid date or datetime string; falling back to default"
              last_updated_at="$default_last_updated_at"
          fi
      else
          last_updated_at="$default_last_updated_at"
      fi
    fi

    echo "Copying data since: $last_updated_at"
    echo

    # Run the copy_all_tables function with the determined date
    copy_all_tables "$last_updated_at" "$current_timestamp"

    # Write the current UTC timestamp to last_incremental_copy.txt
    echo "$current_timestamp" > "last_incremental_copy.txt"
}

main "$@"
