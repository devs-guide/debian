#!/usr/bin/env bash
# Safe parser and iterator for actions/publication.manifest.

if [[ -z "${ROOT:-}" ]]; then
  printf '[actions.publication][error] ROOT must be set before sourcing actions/lib/publication.sh\n' >&2
  return 1 2>/dev/null || exit 1
fi

: "${PUBLICATION_LABEL:=actions.publication}"

publication.error() {
  printf '[%s][error] %s\n' "${PUBLICATION_LABEL}" "$*" >&2
}

publication.relative.path.is.safe() {
  local path="${1:-}"
  local segment=""
  local -a segments=()

  [[ -n "${path}" && "${path}" != /* && "${path}" != */ && "${path}" != *'//'*
    && "${path}" != *$'\n'* && "${path}" != *$'\r'* && "${path}" != *'|'*
    && "${path}" != *[[:space:]]* ]] || return 1

  IFS='/' read -r -a segments <<< "${path}"
  ((${#segments[@]} > 0)) || return 1
  for segment in "${segments[@]}"; do
    [[ "${segment}" =~ ^[A-Za-z0-9][A-Za-z0-9._+@-]*$ ]] || return 1
    [[ "${segment}" != . && "${segment}" != .. ]] || return 1
  done
}

publication.manifest.validate() {
  local manifest="${1:-}"
  local line_number=0
  local kind=""
  local source=""
  local destination=""
  local extra=""
  local source_path=""
  local seen_sources="|"
  local seen_destinations="|"
  local existing_kind=""
  local existing_source=""
  local existing_destination=""
  local index=0
  local -a source_kinds=()
  local -a source_paths=()
  local -a destination_kinds=()
  local -a destination_paths=()

  [[ -f "${manifest}" && -r "${manifest}" && -s "${manifest}" ]] || {
    publication.error "publication manifest is missing, unreadable, or empty: ${manifest:-unset}"
    return 1
  }

  while IFS='|' read -r kind source destination extra || \
    [[ -n "${kind}${source}${destination}${extra}" ]]; do
    line_number=$((line_number + 1))
    destination="${destination%$'\r'}"

    if [[ -z "${kind}${source}${destination}${extra}" || "${kind}" == \#* ]]; then
      continue
    fi
    if [[ -n "${extra}" || -z "${source}" || -z "${destination}" ]]; then
      publication.error "invalid field count at ${manifest}:${line_number}"
      return 1
    fi
    case "${kind}" in
      file|tree) ;;
      *)
        publication.error "unsupported entry type at ${manifest}:${line_number}: ${kind}"
        return 1
        ;;
    esac
    publication.relative.path.is.safe "${source}" || {
      publication.error "unsafe source at ${manifest}:${line_number}: ${source}"
      return 1
    }
    publication.relative.path.is.safe "${destination}" || {
      publication.error "unsafe destination at ${manifest}:${line_number}: ${destination}"
      return 1
    }
    [[ "${seen_sources}" != *"|${source}|"* ]] || {
      publication.error "duplicate source at ${manifest}:${line_number}: ${source}"
      return 1
    }
    [[ "${seen_destinations}" != *"|${destination}|"* ]] || {
      publication.error "duplicate destination at ${manifest}:${line_number}: ${destination}"
      return 1
    }
    for ((index = 0; index < ${#source_paths[@]}; index++)); do
      existing_kind="${source_kinds[index]}"
      existing_source="${source_paths[index]}"
      existing_destination="${destination_paths[index]}"
      if [[ "${existing_kind}" == tree && "${source}" == "${existing_source}/"* ]] || \
        [[ "${kind}" == tree && "${existing_source}" == "${source}/"* ]]; then
        publication.error "overlapping source trees at ${manifest}:${line_number}: ${source}"
        return 1
      fi
      if [[ "${destination_kinds[index]}" == tree && "${destination}" == "${existing_destination}/"* ]] || \
        [[ "${kind}" == tree && "${existing_destination}" == "${destination}/"* ]]; then
        publication.error "overlapping destination trees at ${manifest}:${line_number}: ${destination}"
        return 1
      fi
    done
    seen_sources="${seen_sources}${source}|"
    seen_destinations="${seen_destinations}${destination}|"
    source_kinds+=("${kind}")
    source_paths+=("${source}")
    destination_kinds+=("${kind}")
    destination_paths+=("${destination}")

    source_path="${ROOT}/${source}"
    if [[ "${kind}" == file && ( ! -f "${source_path}" || ! -s "${source_path}" || -L "${source_path}" ) ]]; then
      publication.error "file source is missing, empty, or is a symlink: ${source}"
      return 1
    fi
    if [[ "${kind}" == tree && ( ! -d "${source_path}" || -L "${source_path}" ) ]]; then
      publication.error "tree source is missing or is a symlink: ${source}"
      return 1
    fi
    if [[ "${kind}" == tree && -n "$(find "${source_path}" -type l -print -quit)" ]]; then
      publication.error "tree source contains a symlink: ${source}"
      return 1
    fi
    if [[ "${kind}" == tree && -n "$(find "${source_path}" -type f ! -size +0 -print -quit)" ]]; then
      publication.error "tree source contains an empty file: ${source}"
      return 1
    fi
    if [[ "${source}" == setup/* || "${destination}" == setup/* ]]; then
      if [[ "${kind}" != file || "${source}" != *.sh || "${destination}" != *.sh ]]; then
        publication.error "published setup entrypoints must be .sh files: ${source} -> ${destination}"
        return 1
      fi
    fi
  done < "${manifest}"

  [[ "${seen_sources}" != "|" ]] || {
    publication.error "publication manifest has no entries: ${manifest}"
    return 1
  }
}

publication.manifest.each() {
  local manifest="${1:-}"
  local callback="${2:-}"
  local kind=""
  local source=""
  local destination=""
  local extra=""

  publication.manifest.validate "${manifest}" || return 1
  [[ "${callback}" =~ ^[A-Za-z_][A-Za-z0-9_.]*$ ]] && declare -F "${callback}" >/dev/null 2>&1 || {
    publication.error "publication callback is unavailable: ${callback:-unset}"
    return 1
  }

  while IFS='|' read -r kind source destination extra || \
    [[ -n "${kind}${source}${destination}${extra}" ]]; do
    destination="${destination%$'\r'}"
    if [[ -z "${kind}${source}${destination}${extra}" || "${kind}" == \#* ]]; then
      continue
    fi
    "${callback}" "${kind}" "${source}" "${destination}" || return 1
  done < "${manifest}"
}

publication.manifest.contains() {
  local manifest="${1:-}"
  local expected_kind="${2:-}"
  local expected_source="${3:-}"
  local expected_destination="${4:-}"
  local kind=""
  local source=""
  local destination=""
  local extra=""

  while IFS='|' read -r kind source destination extra || \
    [[ -n "${kind}${source}${destination}${extra}" ]]; do
    destination="${destination%$'\r'}"
    if [[ "${kind}" == "${expected_kind}" && "${source}" == "${expected_source}"
      && "${destination}" == "${expected_destination}" && -z "${extra}" ]]; then
      return 0
    fi
  done < "${manifest}"
  return 1
}

publication.manifest.require.setup.runners() {
  local manifest="${1:-}"
  local setup_file=""
  local relative=""
  local runner_count=0

  [[ -d "${ROOT}/setup" ]] || {
    publication.error "setup source directory is unavailable: ${ROOT}/setup"
    return 1
  }
  while IFS= read -r setup_file; do
    runner_count=$((runner_count + 1))
    relative="${setup_file#"${ROOT}/"}"
    publication.manifest.contains "${manifest}" file "${relative}" "${relative}" || {
      publication.error "setup runner is missing its canonical .sh publication entry: ${relative}"
      return 1
    }
  done < <(find "${ROOT}/setup" -type f -name '*.sh' | sort)
  ((runner_count > 0)) || {
    publication.error "setup source directory contains no .sh runners"
    return 1
  }
}

publication.manifest.require.core.sources() {
  local manifest="${1:-}"

  publication.manifest.require.setup.runners "${manifest}" || return 1
  publication.manifest.contains "${manifest}" tree ansible ansible || {
    publication.error "canonical ansible tree publication entry is missing"
    return 1
  }
  publication.manifest.contains "${manifest}" file readme.md readme.md || {
    publication.error "canonical repository readme publication entry is missing"
    return 1
  }
}

publication.output.path.resolve() {
  local requested="${1:-}"
  local relative_base="${2:-${PWD}}"
  local candidate=""
  local destination_name=""
  local parent=""
  local resolved_parent=""

  [[ -n "${requested}" && "${requested}" != *$'\n'* && "${requested}" != *$'\r'* ]] || return 1
  [[ "${relative_base}" == /* ]] || return 1

  if [[ "${requested}" == /* ]]; then
    candidate="${requested}"
  else
    candidate="${relative_base%/}/${requested}"
  fi
  while [[ "${candidate}" != / && "${candidate}" == */ ]]; do
    candidate="${candidate%/}"
  done

  destination_name="${candidate##*/}"
  parent="${candidate%/*}"
  [[ -n "${parent}" ]] || parent="/"
  [[ -n "${destination_name}" && "${destination_name}" != . && "${destination_name}" != .. ]] || return 1
  [[ -d "${parent}" && ! -L "${candidate}" ]] || return 1

  resolved_parent="$(cd "${parent}" && pwd -P)" || return 1
  printf '%s/%s\n' "${resolved_parent%/}" "${destination_name}"
}

publication.output.path.is.safe() {
  local requested="${1:-}"
  local resolved=""
  local resolved_home=""
  local resolved_root=""

  [[ "${requested}" == /* ]] || return 1
  resolved="$(publication.output.path.resolve "${requested}" /)" || return 1
  resolved_root="$(cd "${ROOT}" && pwd -P)"
  if [[ -n "${HOME:-}" && -d "${HOME}" ]]; then
    resolved_home="$(cd "${HOME}" && pwd -P)"
  fi

  [[ "${resolved}" != / && "${resolved}" != /tmp && "${resolved}" != "${resolved_root}" ]] || return 1
  [[ -z "${resolved_home}" || "${resolved}" != "${resolved_home}" ]] || return 1
  case "${resolved}" in
    /Applications|/System|/Users|/bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|\
    /opt|/private|/proc|/root|/run|/sbin|/srv|/sys|/usr|/var)
      return 1
      ;;
  esac
  return 0
}
