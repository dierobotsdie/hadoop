#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

add_plugin checkstyle

CHECKSTYLE_TIMER=0

function checkstyle_preapply
{

  big_console_header "checkstyle plugin: prepatch"

  start_clock
  echo "${MVN} test checkstyle:checkstyle -DskipTests -D${PROJECT_NAME}PatchProcess > ${PATCH_DIR}/${PATCH_BRANCH}checkstyle.txt 2>&1"
  ${MVN} test checkstyle:checkstyle -DskipTests -D${PROJECT_NAME}PatchProcess > "${PATCH_DIR}/${PATCH_BRANCH}checkstyle.txt" 2>&1
  if [[ $? != 0 ]] ; then
    echo "Pre-patch ${PATCH_BRANCH} checkstyle compilation is broken?"
    add_jira_table -1 checkstyle "Pre-patch ${PATCH_BRANCH} checkstyle compilation may be broken."
    return 1
  fi

  cat $(find . -name checkstyle-result.xml) > "${PATCH_DIR}/${PATCH_BRANCH}checkstyle-result.xml"

  # keep track of how much as elapsed for us already
  CHECKSTYLE_TIMER=$(stop_clock)
  return 0
}

function checkstyle_postapply
{

  big_console_header "checkstyle plugin: postpatch"

  start_clock

  # add our previous elapsed to our new timer
  # by setting the clock back
  ((TIMER=TIMER-CHECKSTYLE_TIMER))

  echo "${MVN} test checkstyle:checkstyle -DskipTests -D${PROJECT_NAME}PatchProcess > ${PATCH_DIR}/patchcheckstyle.txt 2>&1"
  ${MVN} test checkstyle:checkstyle -DskipTests -D${PROJECT_NAME}PatchProcess > "${PATCH_DIR}/patchcheckstyle.txt" 2>&1
  if [[ $? != 0 ]] ; then
    echo "Post-patch checkstyle compilation is broken."
    add_jira_table -1 checkstyle "Post-patch checkstyle compilation is broken."
    return 1
  fi

  cat $(find . -name checkstyle-result.xml) > ${PATCH_DIR}/patchcheckstyle-result.xml

  numPrepatch=$(wc -l "${PATCH_DIR}/${PATCH_BRANCH}checkstyle-result.xml" | ${AWK} '{print $1}')
  numPostpatch=$(wc -l "${PATCH_DIR}/patchcheckstyle-result.xml" | ${AWK} '{print $1}')

  if [[ ${numPostpatch} != "" && ${numPrepatch} != "" ]] ; then
    if [[ ${numPostpatch} -gt ${numPrepatch} ]] ; then

      ${DIFF} -u "${PATCH_DIR}/${PATCH_BRANCH}checkstyle-result.xml" \
        "${PATCH_DIR}/patchcheckstyle-result.xml" \
        > "${PATCH_DIR}/diffpatchcheckstyle.xml"

      rm -f "${PATCH_DIR}/${PATCH_BRANCH}checkstyle-result.xml" \
        "${PATCH_DIR}/patchcheckstyle-result.xml" 2>/dev/null

      add_jira_table -1 checkstyle "The applied patch generated "\
        "$((numPostpatch-numPrepatch))" \
        " additional checkstyle issues."
      add_jira_footer checkstyle "@@BASE@@/diffpatchcheckstyle.xml"
      return 1
    fi
  fi
  add_jira_table +1 checkstyle "There were no new checkstyle issues."
  return 0
}
