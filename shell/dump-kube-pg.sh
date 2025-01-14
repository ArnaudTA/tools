#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

# Default
DB_USER="postgres"
EXPORT_DIR="./db-dumps"
DATE_TIME=$(date +"%Y-%m-%dT%H-%M")

# Declare script helper
TEXT_HELPER="\nThis script aims to perform a dump on a kubernetes postgres pod and copy locally the dump file.
Following flags are available:

  -c    Name of the pod's container.

  -d    Name of the postgres database.

  -f    Local dump file to restore.

  -m    Mode tu run. Available modes are :
          dump     - Dump the database locally.
          restore  - Restore local dump into pod.

  -n    Kubernetes namespace target where the database pod is running.
        Default is '$NAMESPACE'

  -o    Output directory where to export files.
        Default is '$EXPORT_DIR'

  -p    Password of the database user that will run the dump command.

  -r    Name of the pod to run the dump on.

  -u    Database user used to dump the database.
        Default is '$DB_USER'

  -h    Print script help.\n\n"

print_help() {
  printf "$TEXT_HELPER"
}

# Parse options
while getopts c:d:f:m:n:o:p:r:u:h flag; do
  case "${flag}" in
    c)
      CONTAINER_NAME=${OPTARG};;
    d)
      DB_NAME=${OPTARG};;
    f)
      DUMP_FILE=${OPTARG};;
    m)
      MODE=${OPTARG};;
    n)
      NAMESPACE=${OPTARG};;
    o)
      EXPORT_DIR=${OPTARG};;
    p)
      DB_PASS=${OPTARG};;
    r)
      POD_NAME=${OPTARG};;
    u)
      DB_USER=${OPTARG};;
    h | *)
      print_help
      exit 0;;
  esac
done


if [ "$MODE" = "dump" ] && [ -z "$POD_NAME" ]; then
  printf "\n${red}Error.${no_color} Argument missing : pod name (flag -r)".
  exit 1
elif [ "$MODE" = "dump" ] && [ -z "$DB_NAME" ]; then
  printf "\n${red}Error.${no_color} Argument missing : database name (flag -d)".
  exit 1
elif [ "$MODE" = "restore" ] && [ -z "$DUMP_FILE" ]; then
  printf "\n${red}Error.${no_color} Argument DUMP_FILE : database file dump (flag -f)".
  exit 1
fi


# Add namespace if provided
[[ ! -z "$NAMESPACE" ]] && NAMESPACE_ARG="--namespace=$NAMESPACE"
[[ ! -z "$CONTAINER_NAME" ]] && CONTAINER_ARG="--container=$CONTAINER_NAME"
[[ ! -z "$DB_NAME" ]] && DB_NAME_ARG="-d $DB_NAME"


isRW () {
  kubectl exec ${POD_NAME} -- bash -c "[ -w $1 ] && echo 'true' || echo 'false'"
}


printf "Settings:
  > MODE: ${MODE}
  > DB_NAME: ${DB_NAME}
  > DB_USER: ${DB_USER}
  > DB_PASS: ${DB_PASS}
  > NAMESPACE: ${NAMESPACE:-$(kubectl config view --minify -o jsonpath='{..namespace}')}
  > POD_NAME: ${POD_NAME}
  > CONTAINER_NAME: ${CONTAINER_NAME}\n"


# Check container fs permissions to store the dump file
if [ "$(isRW /tmp)" = true ]; then
  DUMP_PATH="/tmp"
elif [ "$(isRW /var/lib/postgresql/data)" = true ]; then
  DUMP_PATH="/var/lib/postgresql/data"
elif [ "$(isRW /bitnami/postgresql/data)" = true ]; then
  DUMP_PATH="/bitnami/postgresql/data"
else
  printf "\n\n${red}[Dump wrapper].${no_color} Error: Container filesystem is read-only for path '/tmp', '/var/lib/postgresql/data' and '/bitnami/postgresql/data'.\n\n"
  exit 1
fi


# Dump database
if [ "$MODE" = "dump" ]; then
  # Create output directory
  mkdir -p $EXPORT_DIR

  # Dump database
  printf "\n\n${red}[Dump wrapper].${no_color} Dump database.\n\n"
  kubectl $NAMESPACE_ARG exec ${POD_NAME} ${CONTAINER_ARG} -- bash -c "PGPASSWORD='${DB_PASS}' pg_dump -Fc -U '${DB_USER}' '${DB_NAME}' > ${DUMP_PATH}/${DATE_TIME}_${DB_NAME}.dump"

  # Copy dump locally
  printf "\n\n${red}[Dump wrapper].${no_color} Copy dump file locally.\n\n"
  kubectl $NAMESPACE_ARG cp ${POD_NAME}:${DUMP_PATH:1}/${DATE_TIME}_${DB_NAME}.dump ${EXPORT_DIR}/${DATE_TIME}_${DB_NAME}.dump ${CONTAINER_ARG}
fi


# Restore database
if [ "$MODE" = "restore" ]; then
  # Copy local dump into pod
  printf "\n\n${red}[Dump wrapper].${no_color} Copy local dump file into container (path: '$DUMP_PATH/$(basename $DUMP_FILE)').\n\n"
  kubectl $NAMESPACE_ARG cp ${DUMP_FILE} ${POD_NAME}:${DUMP_PATH:1}/$(basename ${DUMP_FILE}) ${CONTAINER_ARG}

  # Restore database
  printf "\n\n${red}[Dump wrapper].${no_color} Restore database.\n\n"
  kubectl $NAMESPACE_ARG exec ${POD_NAME} ${CONTAINER_ARG} -- bash -c "pg_restore -Fc ${DB_NAME_ARG} ${DUMP_PATH}/$(basename ${DUMP_FILE})"
fi
