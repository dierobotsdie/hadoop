#!/usr/bin/env bash

add_plugin shellcheck

SHELLCHECK_TIMER=0

SHELLCHECK=${SHELLCHECK:-shellcheck}

function shellcheck_private_findbash
{
  local i

  for i in $(find . -d -name bin -o -name sbin); do
     ls $i/* | ${GREP} -v cmd
  done
}

function shellcheck_preapply
{
  local i

  big_console_header "shellcheck plugin: prepatch"

  start_clock

  for i in $(shellcheck_private_findbash | sort); do
    ${SHELLCHECK} -f gcc ${i} >> "${PATCH_DIR}/${PATCH_BRANCH}shellcheck-result.txt"
  done
    
  if [[ $? != 0 ]] ; then
    echo "Pre-patch ${PATCH_BRANCH} shellcheck check is broken?"
    add_jira_table 0 shellcheck "Pre-patch ${PATCH_BRANCH} shellcheck is broken."
    return 1
  fi

  # keep track of how much as elapsed for us already
  SHELLCHECK_TIMER=$(stop_clock)
  return 0
}

function shellcheck_postapply
{
  local i

  big_console_header "shellcheck plugin: postpatch"

  start_clock

  # add our previous elapsed to our new timer
  # by setting the clock back
  ((TIMER=TIMER-SHELLCHECK_TIMER))

  # we re-check this in case one has been added
  for i in $(shellcheck_private_findbash | sort); do
    ${SHELLCHECK} -f gcc "${i}" >> "${PATCH_DIR}/patchshellcheck-result.txt"
  done

  if [[ $? != 0 ]] ; then
    echo "Post-patch shellcheck compilation is broken."
    add_jira_table -1 shellcheck "Post-patch shellcheck compilation is broken."
    return 1
  fi

  numPrepatch=$(wc -l "${PATCH_DIR}/${PATCH_BRANCH}shellcheck-result.txt" | ${AWK} '{print $1}')
  numPostpatch=$(wc -l "${PATCH_DIR}/patchshellcheck-result.txt" | ${AWK} '{print $1}')

  if [[ ${numPostpatch} != "" && ${numPrepatch} != "" ]] ; then
    if [[ ${numPostpatch} -gt ${numPrepatch} ]] ; then

      ${DIFF} -u "${PATCH_DIR}/${PATCH_BRANCH}shellcheck-result.txt" \
        "${PATCH_DIR}/patchshellcheck-result.txt" \
        > "${PATCH_DIR}/diffpatchshellcheck.txt"

      rm -f "${PATCH_DIR}/${PATCH_BRANCH}shellcheck-result.txt" \
        "${PATCH_DIR}/patchshellcheck-result.txt" 2>/dev/null

      add_jira_table -1 shellcheck "The applied patch generated "\
        "$((numPostpatch-numPrepatch))" \
        " additional shellcheck issues."
      add_jira_footer shellcheck "@@BASE@@/diffpatchshellcheck.txt"
      return 1
    fi
  fi
  add_jira_table +1 shellcheck "There were no new shellcheck issues."
  return 0
}
