function expand_template() {
  # top-level '-e' has no effect here
  set -e

  local template_file=${1?Missing template file}

  PROJECT=$PROJECT \
  DEFAULT_USERNAME=$DEFAULT_USERNAME \
  DEFAULT_PASSWORD=$DEFAULT_PASSWORD \
    envsubst < "$template_file"
}
