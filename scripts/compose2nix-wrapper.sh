#!/usr/bin/env bash
set -euo pipefail

# Enable debugging output (set DEBUG=false to disable)
DEBUG=true
if $DEBUG; then
  echo "DEBUG: Starting compose2nix-wrapper script..."
fi

# Full paths for required commands.
GREP="/run/current-system/sw/bin/grep"
HEAD="/run/current-system/sw/bin/head"
SED="/run/current-system/sw/bin/sed"
SORT="/run/current-system/sw/bin/sort"
UNIQ="/run/current-system/sw/bin/uniq"
MKTEMP="/run/current-system/sw/bin/mktemp"
MV="/run/current-system/sw/bin/mv"
BASENAME="/run/current-system/sw/bin/basename"
FIND="/run/current-system/sw/bin/find"
NIX="/run/current-system/sw/bin/nix"
MKDIR="/run/current-system/sw/bin/mkdir"
ECHO="/run/current-system/sw/bin/echo"
DIRNAME="/run/current-system/sw/bin/dirname"

# Source directory for compose files
SOURCE_DIR="/etc/nixos/containers/templates"
# Set output directory and ensure it exists.
OUTPUT_DIR="/etc/nixos/containers"
if [ ! -d "$OUTPUT_DIR" ]; then
  $ECHO "Creating output directory $OUTPUT_DIR..."
  /run/wrappers/bin/sudo $MKDIR -p "$OUTPUT_DIR"
fi

# Process all yml files in the source directory
for COMPOSE_FILE in $($FIND "$SOURCE_DIR" -name "*.yml"); do
  # Get the project name from the filename without extension
  PROJECT_NAME=$($BASENAME "$COMPOSE_FILE" .yml)
  
  # Set the output file path
  OUTPUT_FILE="${OUTPUT_DIR}/${PROJECT_NAME}.nix"
  $ECHO "Processing '${COMPOSE_FILE}' for project '${PROJECT_NAME}'"
  $ECHO "Output file will be ${OUTPUT_FILE}"
  
  # Get compose file directory (for relative path resolution)
  COMPOSE_DIR=$($DIRNAME "$COMPOSE_FILE")
  
  # Run compose2nix to generate the initial Nix file
  if $DEBUG; then
    $ECHO "DEBUG: Running compose2nix for $PROJECT_NAME..."
  fi
  $NIX --extra-experimental-features "nix-command flakes" run github:aksiksi/compose2nix -- -inputs "$COMPOSE_FILE" -output "${OUTPUT_FILE}" -project "${PROJECT_NAME}"
  
  # Remove any unsupported autoUpdate lines
  $SED -i '/autoUpdate/d' "$OUTPUT_FILE"
  
  # Extract volume paths from the generated Nix file and build tmpfiles rules
  if $DEBUG; then
    $ECHO "DEBUG: Extracting volume paths for $PROJECT_NAME..."
  fi
  
  # Using gawk to process the volumes section and handle relative paths properly
  TMPFILES_RULES=""
  VOLUME_PATHS=""
  
  # Process potentially relative paths in the volumes section
  # Use process substitution to avoid subshell variable scoping issues
  while read -r vol; do
    # Remove quotes
    vol=${vol#\"}
    
    # Get host path (before the first colon)
    host_path=${vol%%:*}
    
    if $DEBUG; then
      $ECHO "DEBUG: Processing volume path: $host_path"
    fi
    
    if [[ "$host_path" == ./* ]]; then
      # Handle relative path - convert to absolute path under /var/lib/containers/storage/volumes/$PROJECT_NAME
      rel_path=${host_path#./}
      new_path="/var/lib/containers/storage/volumes/${PROJECT_NAME}/${rel_path}"
      
      # Replace in the Nix file
      $SED -i "s|\"$host_path:|\"$new_path:|g" "$OUTPUT_FILE"
      
      # Add tmpfiles rule for the new path
      TMPFILES_RULES+="    \"d $new_path 0755 root root - -\"\n"
      # Store volume path for service modification
      VOLUME_PATHS+="$new_path\n"
      
      if $DEBUG; then
        $ECHO "DEBUG: Converted relative path $host_path to $new_path"
      fi
    elif [[ "$host_path" == /home/* && "$host_path" != */run/* ]]; then
      # Redirect home paths to /var/lib/containers/storage/volumes/$PROJECT_NAME
      # Extract the path after /home/username/
      SUBPATH=$($SED -E 's|/home/[^/]+/(.*)|\1|' <<< "$host_path")
      # Create new path under container volumes directory
      NEW_PATH="/var/lib/containers/storage/volumes/${PROJECT_NAME}/${SUBPATH}"
      # Replace in the Nix file
      $SED -i "s|\"$host_path:|\"$NEW_PATH:|g" "$OUTPUT_FILE"
      # Add tmpfiles rule for the new path
      TMPFILES_RULES+="    \"d $NEW_PATH 0755 root root - -\"\n"
      # Store volume path for service modification
      VOLUME_PATHS+="$NEW_PATH\n"
      if $DEBUG; then
        $ECHO "DEBUG: Redirected $host_path to $NEW_PATH"
      fi
    elif [[ "$host_path" == /etc/nixos/* && ! -d "$host_path" ]]; then
      # Handle paths under /etc/nixos that don't exist yet
      volume_path="/var/lib/containers/storage/volumes/${PROJECT_NAME}/${host_path##*/}"
      
      # Replace in the Nix file
      $SED -i "s|\"$host_path:|\"$volume_path:|g" "$OUTPUT_FILE"
      
      # Add tmpfiles rule for this path
      TMPFILES_RULES+="    \"d $volume_path 0755 root root - -\"\n"
      # Store volume path for service modification
      VOLUME_PATHS+="$volume_path\n"
      
      if $DEBUG; then
        $ECHO "DEBUG: Redirected non-existent path $host_path to $volume_path"
      fi
    fi
  done < <($GREP -o '"[^"]*:[^"]*' "$OUTPUT_FILE")
    
  # Extract container images and build both pull service and activation script blocks.
  if $DEBUG; then
    $ECHO "DEBUG: Extracting container images for $PROJECT_NAME..."
  fi
  CONTAINER_IMAGES=$($GREP -o 'image = "[^"]*"' "$OUTPUT_FILE" | $SED 's/image = "\(.*\)"/\1/')
  if $DEBUG; then
    $ECHO "DEBUG: Found container images:" $CONTAINER_IMAGES
  fi

  PULL_SERVICES=""
  ACTIVATION_SCRIPT=""
  for IMAGE in $CONTAINER_IMAGES; do
    # Derive container name: take the part after the last slash and remove any tag.
    CONTAINER_NAME=$($ECHO "${IMAGE##*/}" | $SED 's/:.*$//')
    SERVICE_NAME="pull-$PROJECT_NAME-$($ECHO ${IMAGE##*/} | $SED 's/:/-/')-image"

    # Build the pull service block (manual pull option).
    PULL_SERVICES+="  # Auto-created image pull service\n"
    PULL_SERVICES+="  systemd.services.\"$SERVICE_NAME\" = {\n"
    PULL_SERVICES+="    description = \"Pull latest ${IMAGE##*/} image for $PROJECT_NAME\";\n"
    PULL_SERVICES+="    path = [ pkgs.podman ];\n"
    PULL_SERVICES+="    script = ''\n"
    PULL_SERVICES+="      podman pull $IMAGE\n"
    PULL_SERVICES+="    '';\n"
    PULL_SERVICES+="    serviceConfig = {\n"
    PULL_SERVICES+="      Type = \"oneshot\";\n"
    PULL_SERVICES+="    };\n"
    PULL_SERVICES+="    wantedBy = [ \"multi-user.target\" ];\n"
    PULL_SERVICES+="  };\n\n"
    if $DEBUG; then
      $ECHO "DEBUG: Created pull service $SERVICE_NAME for image $IMAGE"
    fi

    # Build activation script commands for each container.
    ACTIVATION_SCRIPT+="$ECHO \"Pulling latest image for $PROJECT_NAME/$CONTAINER_NAME...\"\n"
    ACTIVATION_SCRIPT+="\${pkgs.podman}/bin/podman pull $IMAGE || true\n"
    ACTIVATION_SCRIPT+="$ECHO \"Done pulling for $PROJECT_NAME/$CONTAINER_NAME.\"\n"
  done

  # Create a code block to ensure volume directories exist before container startup
  ENSURE_DIRS_BLOCK=""
  if [ -n "$VOLUME_PATHS" ]; then
    # Build an ExecStartPre snippet for each volume path
    EXEC_START_PRE_ITEMS=()
    while IFS= read -r path; do
      if [ -n "$path" ]; then
        EXEC_START_PRE_ITEMS+=("        \"\${pkgs.coreutils}/bin/mkdir -p $path\"")
      fi
    done < <(echo -e "$VOLUME_PATHS")
    
    # Now join the items with proper formatting (one per line, no trailing newline)
    EXEC_START_PRE=""
    for ((i=0; i<${#EXEC_START_PRE_ITEMS[@]}; i++)); do
      EXEC_START_PRE+="${EXEC_START_PRE_ITEMS[$i]}"
      # Add newline only if not the last item
      if ((i < ${#EXEC_START_PRE_ITEMS[@]} - 1)); then
        EXEC_START_PRE+="\n"
      fi
    done
    
    # Create a block to inject into each podman service
    if [ -n "$EXEC_START_PRE" ]; then
      # Remove trailing newline and comma
      EXEC_START_PRE=${EXEC_START_PRE%,\\n}
      
      # Create a special auto-created-prestart service instead of modifying the podman service directly
      # This avoids conflicts with the original podman service in the generated nix file
      ENSURE_DIRS_BLOCK="  # Auto-created service to ensure volume directories exist before container start\n"
      ENSURE_DIRS_BLOCK+="  systemd.services.\"ensure-$PROJECT_NAME-volumes\" = {\n"
      ENSURE_DIRS_BLOCK+="    description = \"Ensure volume directories exist for $PROJECT_NAME\";\n"
      ENSURE_DIRS_BLOCK+="    after = [ \"systemd-tmpfiles-setup.service\" ];\n"
      ENSURE_DIRS_BLOCK+="    before = [ \"podman-$PROJECT_NAME.service\" ];\n"
      ENSURE_DIRS_BLOCK+="    requiredBy = [ \"podman-$PROJECT_NAME.service\" ];\n"
      ENSURE_DIRS_BLOCK+="    serviceConfig = {\n"
      ENSURE_DIRS_BLOCK+="      Type = \"oneshot\";\n"
      ENSURE_DIRS_BLOCK+="      RemainAfterExit = true;\n"
      # Build mkdir commands into a script
      MKDIR_SCRIPT=""
      for ((i=0; i<${#EXEC_START_PRE_ITEMS[@]}; i++)); do
        # Extract just the path from the command (which is in the format "${pkgs.coreutils}/bin/mkdir -p /path/to/dir")
        path=$(echo "${EXEC_START_PRE_ITEMS[$i]}" | grep -o '/var/lib/containers/storage/volumes/[^ "]*')
        if [ -n "$path" ]; then
          MKDIR_SCRIPT+="mkdir -p $path; "
        fi
      done
      
      # Use a simpler single-line command to avoid quoting issues
      ENSURE_DIRS_BLOCK+="      ExecStart = \"\${pkgs.bash}/bin/bash -c \\\"$MKDIR_SCRIPT\\\"\";\n"
      ENSURE_DIRS_BLOCK+="    };\n"
      ENSURE_DIRS_BLOCK+="  };\n\n"
      
      if $DEBUG; then
        $ECHO "DEBUG: Created service modification block to ensure volume directories"
      fi
    fi
  fi

  # Reassemble the output file with the additional blocks.
  if $DEBUG; then
    $ECHO "DEBUG: Adding tmpfiles rules, pull services, and activation script to $OUTPUT_FILE"
  fi
  $SED -i '1s/^/# Auto-generated by compose2nix-wrapper\n/' "$OUTPUT_FILE"

  TMP_FILE=$($MKTEMP)
  FUNC_DECL=$($GREP -E '^\{.*\}:' "$OUTPUT_FILE" || $ECHO "{ pkgs, lib, config, ... }:")

  # Write the function declaration and opening brace.
  $ECHO "$FUNC_DECL" > "$TMP_FILE"
  $ECHO "{" >> "$TMP_FILE"

  # Insert tmpfiles rules if present.
  if [ -n "$TMPFILES_RULES" ]; then
    $ECHO "  # Auto-created directory rules" >> "$TMP_FILE"
    $ECHO -e "  systemd.tmpfiles.rules = [\n${TMPFILES_RULES}  ];" >> "$TMP_FILE"
    if $DEBUG; then
      $ECHO "DEBUG: Added tmpfiles rules."
    fi
  fi

  # Insert the manual pull services.
  if [ -n "$PULL_SERVICES" ]; then
    $ECHO -e "${PULL_SERVICES}" >> "$TMP_FILE"
    if $DEBUG; then
      $ECHO "DEBUG: Added pull services."
    fi
  fi
  
  # Insert the service modification to ensure directories exist
  if [ -n "$ENSURE_DIRS_BLOCK" ]; then
    $ECHO -e "${ENSURE_DIRS_BLOCK}" >> "$TMP_FILE"
    if $DEBUG; then
      $ECHO "DEBUG: Added service modifications for directory creation."
    fi
  fi

  # Insert the activation script block that pulls container images on every rebuild.
  if [ -n "$ACTIVATION_SCRIPT" ]; then
    $ECHO "  # Auto-created activation script to pull container images on rebuild" >> "$TMP_FILE"
    $ECHO "  system.activationScripts.pull${PROJECT_NAME}Containers = ''" >> "$TMP_FILE"
    # Indent each line of the activation script by 4 spaces.
    $ECHO -e "${ACTIVATION_SCRIPT}" | $SED 's/^/    /' >> "$TMP_FILE"
    $ECHO "  '';" >> "$TMP_FILE"
    if $DEBUG; then
      $ECHO "DEBUG: Added activation script for container image pulls."
    fi
  fi

  # Append the rest of the original file (skip the function declaration and opening brace).
  $SED -n '/^{$/,${p}' "$OUTPUT_FILE" | $SED '1d' >> "$TMP_FILE"
  $MV "$TMP_FILE" "$OUTPUT_FILE"
  if $DEBUG; then
    $ECHO "DEBUG: Replaced original file with updated version."
  fi

  # Fix any double slashes in paths.
  $SED -i 's|//|/|g' "$OUTPUT_FILE"

  $ECHO "Generated ${OUTPUT_FILE} with automatic directory creation, manual pull service, and an activation script for image pulls."
  $ECHO "---------------------------------------------"

done # End of for loop for processing each yml file

$ECHO "All Docker Compose files processed!"
$ECHO "Before installing, please verify the syntax is correct for each generated .nix file."
$ECHO "To install: /run/wrappers/bin/sudo /run/current-system/sw/bin/nixos-rebuild switch"