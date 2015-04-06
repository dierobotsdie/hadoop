#!/usr/bin/env bash

add_plugin whitespace

function whitespace_preapply
{
  local count

  big_console_header "Checking for whitespace at the end of lines"
  start_clock

  ${GREP} '^+' "${PATCH_DIR}/patch" | ${GREP} -c '[[:space:]]$' > "${PATCH_DIR}/whitespace.txt"

  count=$(wc -l "${PATCH_DIR}/whitespace.txt")

  if [[ ${count} -gt 0 ]]; then
    add_jira_table -1 whitspace "The patch has ${count}"\
      " lines that end in whitespace."
    add_jira_footer whitespace "@@BASE@@/whitespace.txt"
  fi

  add_jira_table +1 whitspace "The patch has no "\
        " lines that end in whitespace."
}
