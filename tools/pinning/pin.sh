#!/bin/bash
# This script accepts no arguments and automates the process of updating
# Certbot's dependencies. Dependencies can be pinned to older versions by
# modifying pyproject.toml in the same directory as this file.
set -euo pipefail

# Since certbot-apache is crafted as an empty project on Windows, the
# result of pinning dependencies would not be accurate on that platform,
# so we forbid it.
if uname -a | grep -q -E 'CYGWIN|MINGW'; then
    echo "This script cannot be run on Windows"
    exit 1
fi

WORK_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
REPO_ROOT="$(dirname "$(dirname "${WORK_DIR}")")"
PIPSTRAP_CONSTRAINTS="${REPO_ROOT}/tools/pipstrap_constraints.txt"
RELATIVE_SCRIPT_PATH="$(realpath --relative-to "$REPO_ROOT" "$WORK_DIR")/$(basename "${BASH_SOURCE[0]}")"
REQUIREMENTS_FILE="$REPO_ROOT/tools/requirements.txt"
STRIP_HASHES="${REPO_ROOT}/tools/strip_hashes.py"

if ! command -v poetry >/dev/null; then
    echo "Please install poetry."
    echo "You may need to recreate Certbot's virtual environment and activate it."
    exit 1
fi

# Old eggs can cause outdated dependency information to be used by poetry so we
# delete them before generating the lock file. See
# https://github.com/python-poetry/poetry/issues/4103 for more info.
cd "${REPO_ROOT}"
rm -rf */*.egg-info

cd "${WORK_DIR}"

if [ -f poetry.lock ]; then
    rm poetry.lock
fi

poetry lock

TEMP_REQUIREMENTS=$(mktemp)
trap 'rm poetry.lock; rm $TEMP_REQUIREMENTS' EXIT

poetry export -o "${TEMP_REQUIREMENTS}" --without-hashes
# We need to remove local packages from the requirements file.
sed -i '/^acme @/d; /certbot/d;' "${TEMP_REQUIREMENTS}"
# Poetry currently will not include pip, setuptools, or wheel in lockfiles or
# requirements files. This was resolved by
# https://github.com/python-poetry/poetry/pull/2826, but as of writing this it
# hasn't been included in a release yet. For now, we continue to keep
# pipstrap's pinning separate which has the added benefit of having it continue
# to check hashes when pipstrap is run directly.
"${STRIP_HASHES}" "${PIPSTRAP_CONSTRAINTS}" >>  "${TEMP_REQUIREMENTS}"

cat << EOF > "$REQUIREMENTS_FILE"
# This file was generated by $RELATIVE_SCRIPT_PATH and can be updated using
# that script.
#
# It is normally used as constraints to pip, however, it has the name
# requirements.txt so that is scanned by GitHub. See
# https://docs.github.com/en/github/visualizing-repository-data-with-graphs/about-the-dependency-graph#supported-package-ecosystems
# for more info.
EOF
cat "${TEMP_REQUIREMENTS}" >> "${REQUIREMENTS_FILE}"
