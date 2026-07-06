#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Default Settings
# ============================================================

IMAGE_NAME="aoc2026-env"
CONT_NAME="aoc2026-container"
USERNAME="${USER:-aoc}"

# 使用固定 UID/GID，避免跟 ubuntu:26.04 內建 UID/GID 1000 撞到
USER_UID="10001" 
USER_GID="10001"

HOSTNAME_IN_CONTAINER="aoc2026"
DOCKERFILE="Dockerfile"

# 預設把目前專案資料夾掛到 container 的 /workspace
MOUNTS=("${PWD}:/workspace")

# ============================================================
# Help Message
# ============================================================

help() {
    cat <<HELP

Usage:
  ./docker.sh <command> [options]

Commands:
  build      Build Docker image
  run        Run container or enter existing container
  clean      Remove container and image
  rebuild    Remove container/image and build again
  help       Show this help message

Options:
  --image-name <name>     Docker image name
                          default: aoc2026-env

  --cont-name <name>      Docker container name
                          default: aoc2026-container

  --username <name>       Username inside Docker image
                          default: current Linux user

  --uid <uid>             UID inside Docker image
                          default: 10001

  --gid <gid>             GID inside Docker image
                          default: 10001

  --hostname <name>       Hostname inside container
                          default: aoc2026

  --mount <path>          Bind mount directory into container.
                          Can be used multiple times.

                          Example 1:
                            --mount ./lab0
                            Mount to /workspace/lab0

                          Example 2:
                            --mount ./lab0:/workspace/lab0
                            Mount to assigned container path

Examples:
  ./docker.sh build

  ./docker.sh run

  ./docker.sh run \\
      --username \$USER \\
      --mount ./lab0 \\
      --image-name aoc2026-env \\
      --cont-name aoc2026-container

  ./docker.sh build \\
      --image-name aoc2026-env-v2 \\
      --username \$USER \\
      --uid 10001 \\
      --gid 10001

  ./docker.sh run \\
      --image-name aoc2026-env-v2 \\
      --cont-name aoc2026-container-v2

  ./docker.sh clean

  ./docker.sh rebuild

HELP
}

# ============================================================
# Basic Check Functions
# ============================================================

check_docker() {
    if ! command -v docker > /dev/null 2>&1; then
        echo "[ERROR] docker command not found."
        exit 1
    fi
}

check_dockerfile() {
    if [[ ! -f "${DOCKERFILE}" ]]; then
        echo "[ERROR] Dockerfile not found: ${DOCKERFILE}"
        echo "[INFO] Please run this script in the directory containing Dockerfile."
        exit 1
    fi
}

need_value() {
    option_name="$1"
    option_value="${2:-}"

    if [[ -z "${option_value}" ]]; then
        echo "[ERROR] Missing value for ${option_name}"
        exit 1
    fi
}

# ============================================================
# Parse Command
# ============================================================

COMMAND="${1:-help}"

if [[ $# -gt 0 ]]; then
    shift
fi

# ============================================================
# Parse CLI Arguments
# ============================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --image-name)
            need_value "$1" "${2:-}"
            IMAGE_NAME="$2"
            shift 2
            ;;

        --cont-name)
            need_value "$1" "${2:-}"
            CONT_NAME="$2"
            shift 2
            ;;

        --username)
            need_value "$1" "${2:-}"
            USERNAME="$2"
            shift 2
            ;;

        --uid)
            need_value "$1" "${2:-}"
            USER_UID="$2"
            shift 2
            ;;

        --gid)
            need_value "$1" "${2:-}"
            USER_GID="$2"
            shift 2
            ;;

        --hostname)
            need_value "$1" "${2:-}"
            HOSTNAME_IN_CONTAINER="$2"
            shift 2
            ;;

        --mount)
            need_value "$1" "${2:-}"
            MOUNTS+=("$2")
            shift 2
            ;;

        -h|--help)
            help
            exit 0
            ;;

        *)
            echo "[ERROR] Unknown argument: $1"
            echo
            help
            exit 1
            ;;
    esac
done

# ============================================================
# Docker State Helper Functions
# ============================================================

image_exists() {
    docker image inspect "${IMAGE_NAME}" > /dev/null 2>&1
}

container_exists() {
    docker container inspect "${CONT_NAME}" > /dev/null 2>&1
}

container_status() {
    if container_exists; then
        docker container inspect -f '{{.State.Status}}' "${CONT_NAME}"
    else
        echo "not-existed"
    fi
}

# ============================================================
# Mount Helper
# ============================================================

make_mount_args() {
    MOUNT_ARGS=()

    for mount in "${MOUNTS[@]}"; do
        # Case 1:
        #   --mount ./lab0:/workspace/lab0
        # 使用者自己指定 host path 和 container path
        if [[ "${mount}" == *":"* ]]; then
            host_path="${mount%%:*}"
            cont_path="${mount#*:}"

            if [[ ! -e "${host_path}" ]]; then
                echo "[ERROR] Mount path does not exist: ${host_path}"
                exit 1
            fi

            abs_host_path="$(realpath "${host_path}")"
            MOUNT_ARGS+=("-v" "${abs_host_path}:${cont_path}")

        # Case 2:
        #   --mount ./lab0
        # 自動掛到 /workspace/lab0
        else
            if [[ ! -e "${mount}" ]]; then
                echo "[ERROR] Mount path does not exist: ${mount}"
                exit 1
            fi

            abs_host_path="$(realpath "${mount}")"
            base_name="$(basename "${abs_host_path}")"

            MOUNT_ARGS+=("-v" "${abs_host_path}:/workspace/${base_name}")
        fi
    done
}

# ============================================================
# 1. Build Image
# ============================================================

build_image() {
    check_docker
    check_dockerfile

    echo "[INFO] Image name      : ${IMAGE_NAME}"
    echo "[INFO] Dockerfile      : ${DOCKERFILE}"
    echo "[INFO] Username        : ${USERNAME}"
    echo "[INFO] UID/GID         : ${USER_UID}/${USER_GID}"
    echo

    echo "[INFO] Checking image: ${IMAGE_NAME}"

    if image_exists; then
        echo "[INFO] Image '${IMAGE_NAME}' already exists."
        echo
        echo "[INFO] If you want to remove it manually:"
        echo "       docker image rm ${IMAGE_NAME}"
        echo
        echo "[INFO] If you want to rebuild it:"
        echo "       ./docker.sh rebuild --image-name ${IMAGE_NAME} --cont-name ${CONT_NAME}"
        echo
        echo "[INFO] If you want to create a new image, use another image name:"
        echo "       ./docker.sh build --image-name ${IMAGE_NAME}-v2"
        return 0
    fi

    echo "[INFO] Building image: ${IMAGE_NAME}"
    echo

    docker build \
        -t "${IMAGE_NAME}" \
        -f "${DOCKERFILE}" \
        --build-arg USERNAME="${USERNAME}" \
        --build-arg USER_UID="${USER_UID}" \
        --build-arg USER_GID="${USER_GID}" \
        .

    echo
    echo "[INFO] Build finished: ${IMAGE_NAME}"
}

# ============================================================
# 2. Run Container
# ============================================================

run_container() {
    check_docker

    if ! image_exists; then
        echo "[INFO] Image '${IMAGE_NAME}' does not exist."
        echo "[INFO] Building image first..."
        echo
        build_image
    fi

    status="$(container_status)"

    echo "[INFO] Image name      : ${IMAGE_NAME}"
    echo "[INFO] Container name  : ${CONT_NAME}"
    echo "[INFO] Container status: ${status}"
    echo

    case "${status}" in
        running)
            echo "[INFO] Container is running."
            echo "[INFO] Entering container with docker exec..."
            docker exec -it "${CONT_NAME}" /bin/bash
            ;;

        exited|created)
            echo "[INFO] Container exists but is stopped."
            echo "[INFO] Starting container..."
            docker start "${CONT_NAME}" > /dev/null

            echo "[INFO] Entering container..."
            docker exec -it "${CONT_NAME}" /bin/bash
            ;;

        not-existed)
            echo "[INFO] Container does not exist."
            echo "[INFO] Creating and entering new container..."

            make_mount_args

            docker run -it \
                --name "${CONT_NAME}" \
                --hostname "${HOSTNAME_IN_CONTAINER}" \
                "${MOUNT_ARGS[@]}" \
                "${IMAGE_NAME}" \
                /bin/bash
            ;;

        paused)
            echo "[INFO] Container is paused."
            echo "[INFO] Unpausing container..."
            docker unpause "${CONT_NAME}"

            echo "[INFO] Entering container..."
            docker exec -it "${CONT_NAME}" /bin/bash
            ;;

        restarting)
            echo "[ERROR] Container is restarting. Please wait and try again."
            echo "[INFO] Check status with:"
            echo "       docker ps -a"
            exit 1
            ;;

        *)
            echo "[ERROR] Unsupported container status: ${status}"
            echo "[INFO] Check containers with:"
            echo "       docker ps -a"
            exit 1
            ;;
    esac
}

# ============================================================
# 3. Clean Container and Image
# ============================================================

clean_all() {
    check_docker

    if container_exists; then
        status="$(container_status)"

        if [[ "${status}" == "running" ]]; then
            echo "[INFO] Stopping container: ${CONT_NAME}"
            docker stop "${CONT_NAME}"
        fi

        if [[ "${status}" == "paused" ]]; then
            echo "[INFO] Unpausing container: ${CONT_NAME}"
            docker unpause "${CONT_NAME}"
        fi

        echo "[INFO] Removing container: ${CONT_NAME}"
        docker rm "${CONT_NAME}"
    else
        echo "[INFO] Container '${CONT_NAME}' does not exist."
    fi

    if image_exists; then
        echo "[INFO] Removing image: ${IMAGE_NAME}"
        docker image rm "${IMAGE_NAME}"
    else
        echo "[INFO] Image '${IMAGE_NAME}' does not exist."
    fi
}

# ============================================================
# 4. Rebuild Image
# ============================================================

rebuild_image() {
    clean_all
    echo
    build_image
}

# ============================================================
# Main
# ============================================================

case "${COMMAND}" in
    build)
        build_image
        ;;

    run)
        run_container
        ;;

    clean)
        clean_all
        ;;

    rebuild)
        rebuild_image
        ;;

    help|-h|--help)
        help
        ;;

    *)
        echo "[ERROR] Unknown command: ${COMMAND}"
        echo
        help
        exit 1
        ;;
esac
