#!/usr/bin/env bash
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.


#
# We'll want to set these up at some point...
#
#set -euo pipefail
#IFS=$'\n\t'

### Setup some variables.
### BUILD_URL is set by Hudson if it is run by patch process
### Read variables from properties file
this="${BASH_SOURCE-$0}"
BINDIR=$(cd -P -- "$(dirname -- "${this}")" >/dev/null && pwd -P)

# Defaults
if [[ -z "${MAVEN_HOME:-}" ]]; then
  MVN=mvn
else
  MVN=${MAVEN_HOME}/bin/mvn
fi

PROJECT_NAME=Hadoop
JENKINS=false
PATCH_DIR=/tmp
SUPPORT_DIR=/tmp
BASEDIR=$(pwd)
PS=${PS:-ps}
AWK=${AWK:-awk}
WGET=${WGET:-wget}
GIT=${GIT:-git}
EGREP=${EGREP:-egrep}
GREP=${GREP:-grep}
PATCH=${PATCH:-patch}
DIFF=${DIFF:-diff}
JIRACLI=${JIRA:-jira}
FINDBUGS_HOME=${FINDBUGS_HOME:-}
ECLIPSE_HOME=${ECLIPSE_HOME:-}
BUILD_NATIVE=${BUILD_NATIVE:-true}
CHANGED_MODULES=""

declare -a JIRA_COMMENT_TABLE
declare -a JIRA_FOOTER_TABLE

JFC=0
JTC=0

function find_java_home
{
  if [[ -z ${JAVA_HOME:-} ]]; then
    case $(uname -s) in
      Darwin)
        if [[ -z "${JAVA_HOME}" ]]; then
          if [[ -x /usr/libexec/java_home ]]; then
            export JAVA_HOME="$(/usr/libexec/java_home)"
          else
            export JAVA_HOME=/Library/Java/Home
          fi
        fi
      ;;
      *)
      ;;
    esac
  fi
  
  if [[ -z ${JAVA_HOME:-} ]]; then
    echo "JAVA_HOME is not defined."
    add_jira_table -1 pre-patch "JAVA_HOME is not defined."
    return 1
  fi
  return 0
}

function colorstripper
{
  local string=$1
  shift 1
  
  local green=""
  local white=""
  local red=""
  local blue=""
  
  echo "${string}" | \
  sed -e "s,{color:red},${red},g" \
  -e "s,{color:green},${green},g" \
  -e "s,{color:blue},${blue},g" \
  -e "s,{color},${white},g"
  
}

function findlargest
{
  local column=$1
  shift
  local a=("$@")
  local sizeofa=${#a[@]}
  local i=0
  
  until [[ ${i} -gt ${sizeofa} ]]; do
    string=$( echo ${a[$i]} | cut -f$((column + 1)) -d\| )
    if [[ ${#string} -gt $maxlen ]]; then
      maxlen=${#string}
    fi
    i=$((i+1))
  done
  echo "${maxlen}"
}

function add_jira_table
{
  local value=$1
  local subsystem=$2
  shift 2
  
  local color
  
  case ${value} in
    1|+1)
      value="+1"
      color="green"
    ;;
    -1)
      color="red"
    ;;
    0)
      color="blue"
    ;;
    null)
    ;;
  esac
  
  if [[ -z ${color} ]]; then
    JIRA_COMMENT_TABLE[${JTC}]="|  | ${subsystem} | $* |"
    JTC=$(( JTC+1 ))
  else
    JIRA_COMMENT_TABLE[${JTC}]="| {color:${color}}${value}{color} | ${subsystem} | $* |"
    JTC=$(( JTC+1 ))
  fi
}

function add_jira_footer
{
  local subsystem=$1
  shift 1
  
  JIRA_FOOTER_TABLE[${JFC}]="| ${subsystem} | $* |"
  JFC=$(( JFC+1 ))
}

function big_console_header
{
  local text="$*"
  local spacing=$(( (70+${#text}) /2 ))
  printf "\n\n"
  echo "======================================================================="
  echo "======================================================================="
  printf "%*s\n"  ${spacing} "${text}"
  echo "======================================================================="
  echo "======================================================================="
  printf "\n\n"
}

###############################################################################
# Find the maven module containing the given file.
function findModule
{
  local dir=$(dirname "$1")
  
  while builtin true; do
    if [[ -f "${dir}/pom.xml" ]];then
      echo "${dir}"
      return
    else
      dir=$(dirname "${dir}")
    fi
  done
}

function findChangedModules
{
  # Come up with a list of changed files into ${TMP}
  local tmp_paths=/tmp/tmp.paths.$$
  local tmp_modules=/tmp/tmp.modules.$$
  
  local module
  local changed_modules=""
  
  ${GREP} '^+++ \|^--- ' "${PATCH_DIR}/patch" | cut -c '5-' | ${GREP} -v /dev/null | sort -u > ${tmp_paths}
  
  # if all of the lines start with a/ or b/, then this is a git patch that
  # was generated without --no-prefix
  if ! ${GREP} -qv '^a/\|^b/' ${tmp_paths} ; then
    ${SED} -i -e 's,^[ab]/,,' ${tmp_paths}
  fi
  
  # Now find all the modules that were changed
  
  while read file; do
    findModule "${file}" >> ${tmp_modules}
  done < <(cut -f 1 "${tmp_paths}" | sort -u)
  rm ${tmp_paths}
  
  # Filter out modules without code
  while read module; do
    ${GREP} "<packaging>pom</packaging>" "${module}/pom.xml" > /dev/null
    if [[ "$?" != 0 ]]; then
      changed_modules="${changed_modules} ${module}"
    fi
  done < <(sort -u "${changed_modules}")
  rm ${tmp_modules}
  echo "${changed_modules}"
}

function printUsage
{
  echo "Usage: $0 [options] patch-file | defect-number"
  echo
  echo "Where:"
  echo "  patch-file is a local patch file containing the changes to test"
  echo "  defect-number is a JIRA defect number (e.g. 'HADOOP-1234') to test (Jenkins only)"
  echo
  echo "Options:"
  echo "--patch-dir=<dir>      The directory for working and output files (default '/tmp')"
  echo "--basedir=<dir>        The directory to apply the patch to (default current directory)"
  echo "--mvn-cmd=<cmd>        The 'mvn' command to use (default \$MAVEN_HOME/bin/mvn, or 'mvn')"
  echo "--ps-cmd=<cmd>         The 'ps' command to use (default 'ps')"
  echo "--awk-cmd=<cmd>        The 'awk' command to use (default 'awk')"
  echo "--git-cmd=<cmd>        The 'git' command to use (default 'git')"
  echo "--grep-cmd=<cmd>       The 'grep' command to use (default 'grep')"
  echo "--patch-cmd=<cmd>      The 'patch' command to use (default 'patch')"
  echo "--diff-cmd=<cmd>       The 'diff' command to use (default 'diff')"
  echo "--findbugs-home=<path> Findbugs home directory (default FINDBUGS_HOME environment variable)"
  echo "--dirty-workspace      Allow the local git workspace to have uncommitted changes"
  echo "--run-tests            Run all tests below the base directory"
  echo "--build-native=<bool>  If true, then build native components (default 'true')"
  echo
  echo "Jenkins-only options:"
  echo "--jenkins              Run by Jenkins (runs tests and posts results to JIRA)"
  echo "--support-dir=<dir>    The directory to find support files in"
  echo "--wget-cmd=<cmd>       The 'wget' command to use (default 'wget')"
  echo "--jira-cmd=<cmd>       The 'jira' command to use (default 'jira')"
  echo "--jira-password=<pw>   The password for the 'jira' command"
  echo "--eclipse-home=<path>  Eclipse home directory (default ECLIPSE_HOME environment variable)"
}

function parseArgs
{
  for i in "$@"
  do
    case $i in
      --java-home)
        JAVA_HOME=${i#*=}
      ;;
      --jenkins)
        JENKINS=true
      ;;
      --patch-dir=*)
        PATCH_DIR=${i#*=}
      ;;
      --support-dir=*)
        SUPPORT_DIR=${i#*=}
      ;;
      --basedir=*)
        BASEDIR=${i#*=}
      ;;
      --mvn-cmd=*)
        MVN=${i#*=}
      ;;
      --ps-cmd=*)
        PS=${i#*=}
      ;;
      --awk-cmd=*)
        AWK=${i#*=}
      ;;
      --wget-cmd=*)
        WGET=${i#*=}
      ;;
      --git-cmd=*)
        GIT=${i#*=}
      ;;
      --grep-cmd=*)
        GREP=${i#*=}
      ;;
      --patch-cmd=*)
        PATCH=${i#*=}
      ;;
      --diff-cmd=*)
        DIFF=${i#*=}
      ;;
      --jira-cmd=*)
        JIRACLI=${i#*=}
      ;;
      --jira-password=*)
        JIRA_PASSWD=${i#*=}
      ;;
      --findbugs-home=*)
        FINDBUGS_HOME=${i#*=}
      ;;
      --eclipse-home=*)
        ECLIPSE_HOME=${i#*=}
      ;;
      --dirty-workspace)
        DIRTY_WORKSPACE=true
      ;;
      --run-tests)
        RUN_TESTS=true
      ;;
      --build-native=*)
        BUILD_NATIVE=${i#*=}
      ;;
      *)
        PATCH_OR_DEFECT=$i
      ;;
    esac
  done
  if [[ ${BUILD_NATIVE} == "true" ]] ; then
    NATIVE_PROFILE=-Pnative
    REQUIRE_TEST_LIB_HADOOP=-Drequire.test.libhadoop
  fi
  if [[ -z "${PATCH_OR_DEFECT}" ]]; then
    printUsage
    exit 1
  fi
  if [[ ${JENKINS} == "true" ]] ; then
    echo "Running in Jenkins mode"
    defect=${PATCH_OR_DEFECT}
    # shellcheck disable=SC2034
    ECLIPSE_PROPERTY="-Declipse.home=$ECLIPSE_HOME"
  else
    echo "Running in developer mode"
    JENKINS=false
    ### PATCH_FILE contains the location of the patchfile
    PATCH_FILE=${PATCH_OR_DEFECT}
    if [[ ! -e "${PATCH_FILE}" ]] ; then
      echo "Unable to locate the patch file ${PATCH_FILE}"
      cleanupAndExit 0
    fi
    ### Check if ${PATCH_DIR} exists. If it does not exist, create a new directory
    if [[ ! -e "${PATCH_DIR}" ]] ; then
      mkdir "${PATCH_DIR}"
      if [[ $? == 0 ]] ; then
        echo "${PATCH_DIR} has been created"
      else
        echo "Unable to create ${PATCH_DIR}"
        cleanupAndExit 0
      fi
    fi
    ### Obtain the patch filename to append it to the version number
    defect=$(basename "${PATCH_FILE}")
  fi
}

function checkout
{
  big_console_header "Testing patch for ${defect}."
  
  ### When run by a developer, if the workspace contains modifications, do not continue
  ### unless the --dirty-workspace option was set
  status=$(${GIT} status --porcelain)
  if [[ ${JENKINS} == "false" ]] ; then
    if [[ "${status}" != "" && -z ${DIRTY_WORKSPACE} ]] ; then
      echo "ERROR: can't run in a workspace that contains the following modifications"
      echo "${status}"
      cleanupAndExit 1
    fi
    echo
  else
    cd "${BASEDIR}"
    ${GIT} reset --hard
    ${GIT} clean -xdf
    ${GIT} checkout trunk
    ${GIT} pull --rebase
  fi
  GIT_REVISION=$(${GIT} rev-parse --verify --short HEAD)
  return $?
}

function prebuildWithoutPatch
{
  local mypwd
  
  big_console_header "Pre-build trunk to verify trunk stability and javac warnings"
  if [[ ! -d hadoop-common-project ]]; then
    pushd "${BINDIR}/.." >/dev/null
    mypwd=$(pwd)
    echo "Compiling ${mypwd}"
    echo "${MVN} clean test -DskipTests > ${PATCH_DIR}/trunkCompile.txt 2>&1"
    ${MVN} clean test -DskipTests > "${PATCH_DIR}/trunkCompile.txt" 2>&1
    if [[ $? != 0 ]] ; then
      echo "Top-level trunk compilation is broken?"
      add_jira_table -1 pre-patch "Top-level trunk compilation may be broken."
      return 1
    fi
    popd >/dev/null
  fi
  echo "Compiling ${mypwd}"
  if [[ -d "${mypwd}"/hadoop-hdfs-project/hadoop-hdfs/target/test/data/dfs ]]; then
    echo "Changing permission ${mypwd}/hadoop-hdfs-project/hadoop-hdfs/target/test/data/dfs to avoid broken builds "
    chmod +x -R "${mypwd}/hadoop-hdfs-project/hadoop-hdfs/target/test/data/dfs"
  fi
  echo "${MVN} clean test -DskipTests -D${PROJECT_NAME}PatchProcess -Ptest-patch > ${PATCH_DIR}/trunkJavacWarnings.txt 2>&1"
  ${MVN} clean test -DskipTests -D${PROJECT_NAME}PatchProcess -Ptest-patch > "${PATCH_DIR}/trunkJavacWarnings.txt" 2>&1
  if [[ $? != 0 ]] ; then
    echo "Trunk compilation is broken?"
    add_jira_table -1 pre-patch "Trunk compilation may be broken."
    return 1
  fi
  
  echo "${MVN} clean test javadoc:javadoc -DskipTests -Pdocs -D${PROJECT_NAME}PatchProcess > ${PATCH_DIR}/trunkJavadocWarnings.txt 2>&1"
  ${MVN} clean test javadoc:javadoc -DskipTests -Pdocs -D${PROJECT_NAME}PatchProcess > "${PATCH_DIR}/trunkJavadocWarnings.txt" 2>&1
  if [[ $? != 0 ]] ; then
    echo "Trunk javadoc compilation is broken?"
    add_jira_table -1 pre-patch "Trunk JavaDoc compilation may be broken."
    return 1
  fi
  
  add_jira_table 0 pre-patch "Trunk compiliation is healthy."
  return 0
}

###############################################################################
function downloadPatch
{
  ### Download latest patch file (ignoring .htm and .html) when run from patch process
  if [[ ${JENKINS} == "true" ]] ; then
    ${WGET} -q -O "${PATCH_DIR}/jira" "http://issues.apache.org/jira/browse/${defect}"
    if [[ $(${GREP} -c 'Patch Available' "${PATCH_DIR}/jira") == 0 ]] ; then
      echo "${defect} is not \"Patch Available\".  Exiting."
      cleanupAndExit 0
    fi
    relativePatchURL=$(${GREP} -o '"/jira/secure/attachment/[0-9]*/[^"]*' "${PATCH_DIR}/jira" | ${GREP} -v -e 'htm[l]*$' | sort | tail -1 | ${GREP} -o '/jira/secure/attachment/[0-9]*/[^"]*')
    patchURL="http://issues.apache.org${relativePatchURL}"
    patchNum=$(echo "${patchURL}" | ${GREP} -o '[0-9]*/' | ${GREP} -o '[0-9]*')
    echo "${defect} patch is being downloaded at $(date) from"
    echo "${patchURL}"
    ${WGET} -q -O "${PATCH_DIR}/patch" "${patchURL}"
    # shellcheck disable=SC2034
    VERSION=${GIT_REVISION}_${defect}_PATCH-${patchNum}
    add_jira_header "Test results for " \
    "${patchURL}" \
    " against trunk revision ${GIT_REVISION}."
    
    ### Copy in any supporting files needed by this process
    cp -r "${SUPPORT_DIR}"/lib/* ./lib
    #PENDING: cp -f ${SUPPORT_DIR}/etc/checkstyle* ./src/test
    ### Copy the patch file to ${PATCH_DIR}
  else
    # shellcheck disable=SC2034
    VERSION=PATCH-${defect}
    cp "${PATCH_FILE}" "${PATCH_DIR}/patch"
    if [[ $? == 0 ]] ; then
      echo "Patch file ${PATCH_FILE} copied to ${PATCH_DIR}"
    else
      echo "Could not copy ${PATCH_FILE} to ${PATCH_DIR}"
      cleanupAndExit 0
    fi
  fi
}

function verifyPatch
{
  # Before building, check to make sure that the patch is valid
  export PATCH
  "${BINDIR}/smart-apply-patch.sh" "${PATCH_DIR}/patch" dryrun
  if [[ $? != 0 ]] ; then
    echo "PATCH APPLICATION FAILED"
    add_jira_table -1 patch "The patch command could not apply the patch during dryrun."
    return 1
  else
    return 0
  fi
}

function applyPatch
{
  big_console_header "Applye patch."
  
  export PATCH
  "${BINDIR}/smart-apply-patch.sh" "${PATCH_DIR}/patch"
  if [[ $? != 0 ]] ; then
    echo "PATCH APPLICATION FAILED"
    add_jira_table -1 patch "The patch command could not apply the patch."
    return 1
  fi
  return 0
}

function checkAuthor
{
  local authorTags
  
  big_console_header "Checking there are no @author tags in the patch."
  
  authorTags=$("${GREP}" -c -i '@author' "${PATCH_DIR}/patch")
  echo "There appear to be ${authorTags} @author tags in the patch."
  if [[ $authorTags != 0 ]] ; then
    add_jira_table -1 @author \
    "The patch appears to contain $authorTags @author tags which the Hadoop" \
    " community has agreed to not allow in code contributions."
    return 1
  fi
  add_jira_table +1 @author "The patch does not contain any @author tags."
  return 0
}

function checkTests
{
  local testReferences
  local patchIsDoc
  
  big_console_header "Checking there are new or changed tests in the patch."
  
  testReferences=$("${GREP}" -c -i -e '^+++.*/test' "${PATCH_DIR}/patch")
  echo "There appear to be ${testReferences} test files referenced in the patch."
  if [[ ${testReferences} == 0 ]] ; then
    if [[ ${JENKINS} == "true" ]] ; then
      # if component has documentation in it, we skip this part.
      # really need a better test here
      patchIsDoc=$("${GREP}" -c -i 'title="documentation' "${PATCH_DIR}/jira")
      if [[ ${patchIsDoc} != 0 ]] ; then
        echo "The patch appears to be a documentation patch that doesn't require tests."
        add_jira_table 0 "tests included" \
        "The patch appears to be a documentation patch that doesn't require tests."
        return 0
      fi
    fi
    
    add_jira_table -1 "tests included" \
    "The patch doesn't appear to include any new or modified tests. " \
    "Please justify why no new tests are needed for this patch." \
    "Also please list what manual steps were performed to verify this patch."
    return 1
  fi
  add_jira_table +1 "tests included" \
  "The patch appears to include ${testReferences} new or modified test files."
  return 0
}

function cleanUpXml
{
  local file
  
  cd "${BASEDIR}/conf"
  for file in *.xml.template
  do
    rm -f "$(basename "${file}" .template)"
  done
  cd "${BASEDIR}"
}


function calculateJavadocWarnings
{
  local warningfile=$1
  
  #shellcheck disable=SC2016,SC2046
  return $(${EGREP} "^[0-9]+ warnings$" "${warningfile}" | ${AWK} '{sum+=$1} END {print sum}')
}

### Check there are no javadoc warnings
function checkJavadocWarnings
{
  local numTrunkJavadocWarnings
  local numPatchJavadocWarnings
  
  big_console_header "Determining number of patched javadoc warnings."
  
  echo "${MVN} clean test javadoc:javadoc -DskipTests -Pdocs -D${PROJECT_NAME}PatchProcess > ${PATCH_DIR}/patchJavadocWarnings.txt 2>&1"
  if [[ -d hadoop-project ]]; then
    (cd hadoop-project; ${MVN} install > /dev/null 2>&1)
  fi
  if [[ -d hadoop-common-project/hadoop-annotations ]]; then
    (cd hadoop-common-project/hadoop-annotations; ${MVN} install > /dev/null 2>&1)
  fi
  ${MVN} clean test javadoc:javadoc -DskipTests -Pdocs -D${PROJECT_NAME}PatchProcess > "${PATCH_DIR}/patchJavadocWarnings.txt" 2>&1
  calculateJavadocWarnings "${PATCH_DIR}/trunkJavadocWarnings.txt"
  numTrunkJavadocWarnings=$?
  calculateJavadocWarnings "${PATCH_DIR}/patchJavadocWarnings.txt"
  numPatchJavadocWarnings=$?
  
  echo "There appear to be ${numTrunkJavadocWarnings} javadoc warnings before the patch and ${numPatchJavadocWarnings} javadoc warnings after applying the patch."
  if [[ ${numTrunkJavadocWarnings} != "" && ${numPatchJavadocWarnings} != "" ]] ; then
    if [[ ${numPatchJavadocWarnings} -gt ${numTrunkJavadocWarnings} ]] ; then
      
      ${GREP} -i warning "${PATCH_DIR}/trunkJavadocWarnings.txt" > "${PATCH_DIR}/trunkJavadocWarningsFiltered.txt"
      ${GREP} -i warning "${PATCH_DIR}/patchJavadocWarnings.txt" > "${PATCH_DIR}/patchJavadocWarningsFiltered.txt"
      ${DIFF} -u "${PATCH_DIR}/trunkJavadocWarningsFiltered.txt" \
      "${PATCH_DIR}/patchJavadocWarningsFiltered.txt" \
      > "${PATCH_DIR}/diffJavadocWarnings.txt"
      rm -f "${PATCH_DIR}/trunkJavadocWarningsFiltered.txt" "${PATCH_DIR}/patchJavadocWarningsFiltered.txt"
      
      add_jira_table -1 javadoc "The applied patch generated "\
      "$((numPatchJavadocWarnings-numTrunkJavadocWarnings))" \
      " additional warning messages. See ${BUILD_URL}/artifact/patchprocess/diffJavadocWarnings.txt for details."
      add_jira_footer javadoc "${BUILD_URL}/artifact/patchprocess/diffJavadocWarnings.txt"
      return 1
    fi
  fi
  add_jira_table +1 javadoc "There were no new javadoc warning messages."
  return 0
}

function calcuateJavacWarnings
{
  local warningfile=$1
  #shellcheck disable=SC2016,SC2046
  return $(${AWK} 'BEGIN {total = 0} {total += 1} END {print total} ${warningfile}')
}

function checkJavacWarnings
{
  local trunkJavacWarnings
  local patchJavacWarnings
  
  big_console_header "Determining number of patched javac warnings."
  
  echo "${MVN} clean test -DskipTests -D${PROJECT_NAME}PatchProcess ${NATIVE_PROFILE} -Ptest-patch > ${PATCH_DIR}/patchJavacWarnings.txt 2>&1"
  ${MVN} clean test -DskipTests -D${PROJECT_NAME}PatchProcess ${NATIVE_PROFILE} -Ptest-patch > "${PATCH_DIR}/patchJavacWarnings.txt" 2>&1
  if [[ $? != 0 ]] ; then
    add_jira_table -1 javac "The patch appears to cause the build to fail."
    return 2
  fi
  ### Compare trunk and patch javac warning numbers
  if [[ -f ${PATCH_DIR}/patchJavacWarnings.txt ]] ; then
    ${GREP} '\[WARNING\]' "${PATCH_DIR}/trunkJavacWarnings.txt" > "${PATCH_DIR}/filteredTrunkJavacWarnings.txt"
    ${GREP} '\[WARNING\]' "${PATCH_DIR}/patchJavacWarnings.txt" > "${PATCH_DIR}/filteredPatchJavacWarnings.txt"
    
    calculateJavacWarnings "${PATCH_DIR}/filteredTrunkJavacWarnings.txt"
    trunkJavacWarnings=$?
    calculateJavacWarnings "${PATCH_DIR}/filteredPatchJavacWarnings.txt"
    patchJavacWarnings=$?
    
    echo "There appear to be $trunkJavacWarnings javac compiler warnings before the patch and $patchJavacWarnings javac compiler warnings after applying the patch."
    if [[ $patchJavacWarnings != "" && $trunkJavacWarnings != "" ]] ; then
      if [[ $patchJavacWarnings -gt $trunkJavacWarnings ]] ; then
        
        ${DIFF} "${PATCH_DIR}/filteredTrunkJavacWarnings.txt" \
        "${PATCH_DIR}/filteredPatchJavacWarnings.txt" \
        > "${PATCH_DIR}/diffJavacWarnings.txt"
        
        add_jira_table -1 javac "The applied patch generated "\
        "$((patchJavacWarnings-trunkJavacWarnings))" \
        " additional warning messages. See ${BUILD_URL}/artifact/patchprocess/diffJavacWarnings.txt for details."
        
        add_jira_footer javac "${BUILD_URL}/artifact/patchprocess/diffJavacWarnings.txt"
        
        return 1
      fi
    fi
  fi
  
  add_jira_table +1 javadoc "There were no new javac warning messages."
  return 0
}

###############################################################################
### Check there are no changes in the number of release audit (RAT) warnings
function checkReleaseAuditWarnings
{
  
  big_console_header "Determining number of patched release audit warnings."
  
  echo "${MVN} apache-rat:check -D${PROJECT_NAME}PatchProcess > ${PATCH_DIR}/patchReleaseAuditOutput.txt 2>&1"
  ${MVN} apache-rat:check -D${PROJECT_NAME}PatchProcess > "${PATCH_DIR}/patchReleaseAuditOutput.txt" 2>&1
  #shellcheck disable=SC2038
  find "${BASEDIR}" -name rat.txt | xargs cat > "${PATCH_DIR}/patchReleaseAuditWarnings.txt"
  
  ### Compare trunk and patch release audit warning numbers
  if [[ -f ${PATCH_DIR}/patchReleaseAuditWarnings.txt ]] ; then
    patchReleaseAuditWarnings=$("${GREP}" -c '\!?????' "${PATCH_DIR}/patchReleaseAuditWarnings.txt")
    echo ""
    echo ""
    echo "There appear to be ${patchReleaseAuditWarnings} release audit warnings after applying the patch."
    if [[ ${patchReleaseAuditWarnings} != "" ]] ; then
      if [[ ${patchReleaseAuditWarnings} -gt 0 ]] ; then
        add_jira_table -1 "release audit" "The applied patch generated ${patchReleaseAuditWarnings} release audit warnings."
        
        ${GREP} '\!?????' "${PATCH_DIR}/patchReleaseAuditWarnings.txt" \
        >  "${PATCH_DIR}/patchReleaseAuditProblems.txt"
        
        echo "Lines that start with ????? in the release audit report indicate files that do not have an Apache license header." >> "${PATCH_DIR}/patchReleaseAuditProblems.txt"
        
        add_jira_footer "Release Audit" "${BUILD_URL}/artifact/patchprocess/diffJavacWarnings.txt"
        
        return 1
      fi
    fi
  fi
  add_jira_table 1 "release audit" "The applied patch does not increase the total number of release audit warnings."
  return 0
}

###############################################################################
### Check there are no changes in the number of Checkstyle warnings
function checkStyle
{
  return 0
  
  big_console_header "Determining number of patched checkstyle warnings."
  
  echo "THIS IS NOT IMPLEMENTED YET"
  echo ""
  echo ""
  echo "${MVN} test checkstyle:checkstyle -DskipTests -D${PROJECT_NAME}PatchProcess"
  ${MVN} test checkstyle:checkstyle -DskipTests -D${PROJECT_NAME}PatchProcess
  
  add_jira_footer "Checkstyle" "${BUILD_URL}/artifact/trunk/build/test/checkstyle-errors.html"
  
  
  ### TODO: calculate actual patchStyleErrors
  #  patchStyleErrors=0
  #  if [[ $patchStyleErrors != 0 ]] ; then
  #    JIRA_COMMENT="${JIRA_COMMENT}
  #
  #    {color:red}-1 checkstyle{color}.  The patch generated $patchStyleErrors code style errors."
  #    return 1
  #  fi
  #  JIRA_COMMENT="${JIRA_COMMENT}
  #
  #    {color:green}+1 checkstyle{color}.  The patch generated 0 code style errors."
  return 0
}

###############################################################################
### Install the new jars so tests and findbugs can find all of the updated jars
function buildAndInstall
{
  
  big_console_header "Installing all of the jars"
  
  echo "${MVN} install -Dmaven.javadoc.skip=true -DskipTests -D${PROJECT_NAME}PatchProcess"
  ${MVN} install -Dmaven.javadoc.skip=true -DskipTests -D${PROJECT_NAME}PatchProcess
  return $?
}


###############################################################################
### Check there are no changes in the number of Findbugs warnings
function checkFindbugsWarnings
{
  
  big_console_header "Determining number of patched Findbugs warnings."
  
  local findbugs_version=$("${FINDBUGS_HOME}/bin/findbugs" -version)
  local modules=${CHANGED_MODULES}
  local rc=0
  local module_suffix
  local findbugsWarnings=0
  local relative_file
  local newFindbugsWarnings
  local findbugsWarnings
  
  for module in ${modules}
  do
    pushd "${module}" >/dev/null
    echo "  Running findbugs in ${module}"
    module_suffix=$(basename "${module}")
    echo "${MVN} clean test findbugs:findbugs -DskipTests -D${PROJECT_NAME}PatchProcess < /dev/null > ${PATCH_DIR}/patchFindBugsOutput${module_suffix}.txt 2>&1"
    ${MVN} clean test findbugs:findbugs -DskipTests -D${PROJECT_NAME}PatchProcess \
    < /dev/null \
    > "${PATCH_DIR}/patchFindBugsOutput${module_suffix}.txt" 2>&1
    (( rc = rc + $? ))
    popd >/dev/null
  done
  
  if [[ ${rc} -ne 0 ]]; then
    add_jira_table -1 findbugs "The patch appears to cause Findbugs (version ${findbugs_version}) to fail."
    return 1
  fi
  
  while read file
  do
    relative_file=${file#${BASEDIR}/} # strip leading ${BASEDIR} prefix
    if [[ ${relative_file} != "target/findbugsXml.xml" ]]; then
      module_suffix=${relative_file%/target/findbugsXml.xml} # strip trailing path
      module_suffix=$(basename "${module_suffix}")
    fi
    
    cp "${file}" "${PATCH_DIR}/patchFindbugsWarnings${module_suffix}.xml"
    
    "${FINDBUGS_HOME}/bin/setBugDatabaseInfo" -timestamp "01/01/2000" \
    "${PATCH_DIR}/patchFindbugsWarnings${module_suffix}.xml" \
    "${PATCH_DIR}/patchFindbugsWarnings${module_suffix}.xml"
    
    newFindbugsWarnings=$("${FINDBUGS_HOME}/bin/filterBugs" \
      -first "01/01/2000" "${PATCH_DIR}/patchFindbugsWarnings${module_suffix}.xml" \
      "${PATCH_DIR}/newPatchFindbugsWarnings${module_suffix}.xml" \
    | ${AWK} '{print $1}')
    
    echo "Found $newFindbugsWarnings Findbugs warnings ($file)"
    
    findbugsWarnings=$((findbugsWarnings+newFindbugsWarnings))
    
    "${FINDBUGS_HOME}/bin/convertXmlToText" -html \
    "${PATCH_DIR}/newPatchFindbugsWarnings${module_suffix}.xml" \
    "${PATCH_DIR}/newPatchFindbugsWarnings${module_suffix}.html"
    
    if [[ ${newFindbugsWarnings} -gt 0 ]] ; then
      add_jira_footer "Findbugs warnings" "${BUILD_URL}/artifact/patchprocess/newPatchFindbugsWarnings${module_suffix}.html"
    fi
  done < <(find "${BASEDIR}" -name findbugsXml.xml)
  
  if [[ ${findbugsWarnings} -gt 0 ]] ; then
    add_jira_table -1 findbugs "The patch appears to introduce $findbugsWarnings new Findbugs (version ${findbugs_version}) warnings."
    return 1
  fi
  
  add_jira_table +1 findbugs "The patch does not introduce any new Findbugs (version ${findbugs_version}) warnings."
  return 0
}

###############################################################################
### Verify eclipse:eclipse works
function checkEclipseGeneration
{
  
  big_console_header "Running mvn eclipse:eclipse."
  
  echo "${MVN} eclipse:eclipse -D${PROJECT_NAME}PatchProcess > ${PATCH_DIR}/patchEclipseOutput.txt 2>&1"
  ${MVN} eclipse:eclipse -D${PROJECT_NAME}PatchProcess > "${PATCH_DIR}/patchEclipseOutput.txt" 2>&1
  if [[ $? != 0 ]] ; then
    add_jira_table -1 eclipse:eclipse "The patch failed to build with eclipse:eclipse."
    return 1
  fi
  add_jira_table +1 eclipse:eclipse "The patch built with eclipse:eclipse."
  return 0
}


###############################################################################
### Run the tests
function runTests
{
  big_console_header "Running tests."
  
  
  local failed_tests=""
  local modules=${CHANGED_MODULES}
  local building_common=0
  local hdfs_modules
  local ordered_modules
  local failed_test_builds=""
  local test_timeouts=""
  local test_logfile
  local test_build_result
  local module_test_timeouts
  local result
  
  #
  # If we are building hadoop-hdfs-project, we must build the native component
  # of hadoop-common-project first.  In order to accomplish this, we move the
  # hadoop-hdfs subprojects to the end of the list so that common will come
  # first.
  #
  # Of course, we may not be building hadoop-common at all-- in this case, we
  # explicitly insert a mvn compile -Pnative of common, to ensure that the
  # native libraries show up where we need them.
  #
  
  for module in ${modules}; do
    if [[ ${module} == hadoop-hdfs-project* ]]; then
      hdfs_modules="${hdfs_modules} ${module}"
    elif [[ ${module} == hadoop-common-project* ]]; then
      ordered_modules="${ordered_modules} ${module}"
      building_common=1
    else
      ordered_modules="${ordered_modules} ${module}"
    fi
  done
  
  if [[ -n "${hdfs_modules}" ]]; then
    ordered_modules="${ordered_modules} ${hdfs_modules}"
    if [[ ${building_common} -eq 0 ]]; then
      echo "  Building hadoop-common with -Pnative in order to provide libhadoop.so to the hadoop-hdfs unit tests."
      echo "  ${MVN} compile ${NATIVE_PROFILE} -D${PROJECT_NAME}PatchProcess"
      if ! ${MVN} compile ${NATIVE_PROFILE} -D${PROJECT_NAME}PatchProcess; then
        add_jira_table -1 "core tests" "Failed to build the native portion " \
        "of hadoop-common prior to running the unit tests in ${ordered_modules}"
        return 1
      fi
    fi
  fi
  
  result=0
  for module in ${ordered_modules}; do
    pushd "${module}" >/dev/null
    module_suffix=$(basename "${module}")
    test_logfile=${PATCH_DIR}/testrun_${module_suffix}.txt
    echo "  Running tests in ${module}"
    echo "  ${MVN} clean install -fn ${NATIVE_PROFILE} $REQUIRE_TEST_LIB_HADOOP -D${PROJECT_NAME}PatchProcess"
    ${MVN} clean install -fae ${NATIVE_PROFILE} $REQUIRE_TEST_LIB_HADOOP -D${PROJECT_NAME}PatchProcess > "${test_logfile}" 2>&1
    test_build_result=$?
    cat "${test_logfile}"
    # shellcheck disable=2016
    module_test_timeouts=$(${AWK} '/^Running / { if (last) { print last } last=$2 } /^Tests run: / { last="" }' "${test_logfile}")
    if [[ -n "${module_test_timeouts}" ]] ; then
      test_timeouts="${test_timeouts} ${module_test_timeouts}"
      result=1
    fi
    #shellcheck disable=SC2038
    module_failed_tests=$(find . -name 'TEST*.xml' | xargs "${GREP}"  -l -E "<failure|<error" | sed -e "s|.*target/surefire-reports/TEST-|                  |g" | sed -e "s|\.xml||g")
    if [[ -n "${module_failed_tests}" ]] ; then
      failed_tests="${failed_tests} ${module_failed_tests}"
      result=1
    fi
    if [[ ${test_build_result} != 0 && -z "${module_failed_tests}" && -z "${module_test_timeouts}" ]] ; then
      failed_test_builds="${failed_test_builds} ${module}"
      result=1
    fi
    popd >/dev/null
  done
  if [[ $result == 1 ]]; then
    add_jira_table -1 "core tests" "Tests failed in ${modules}."
    if [[ -n "${failed_tests}" ]] ; then
      add_jira_table null "Failed unit tests" "${failed_tests}"
    fi
    if [[ -n "${test_timeouts}" ]] ; then
      add_jira_table null "Test timeouts" "${test_timeouts}"
    fi
    if [[ -n "${failed_test_builds}" ]] ; then
      add_jira_table null "Failed test builds" "${failed_test_builds}"
    fi
  else
    add_jira_table +1 "core tests" "The patch passed unit tests in ${modules}."
  fi
  add_jira_footer "Test Results" "${BUILD_URL}/testReport/"
  return ${result}
}

function giveConsoleReport
{
  local result=$1
  shift
  local i
  local seccoladj=$(findlargest 2 "${JIRA_COMMENT_TABLE[@]}")
  
  if [[ ${result} == 0 ]]; then
    printf "\n\n+1 overall\n\n"
  else
    printf "\n\n-1 overall\n\n"
  fi
  
  if [[ ${seccoladj} -lt 10 ]]; then
    seccoladj=10
  fi
  
  seccoladj=$((seccoladj + 2 ))
  i=0
  until [[ $i -eq ${#JIRA_HEADER[@]} ]]; do
    printf "%s\n" "${JIRA_HEADER[${i}]}"
    i=$((i+1))
  done
  
  printf "| %s | %*s | %s\n" "Vote" ${seccoladj} Subsystem "Comment"
  
  i=0
  until [[ $i -eq ${#JIRA_COMMENT_TABLE[@]} ]]; do
    vote=$(echo "${JIRA_COMMENT_TABLE[${i}]}" | cut -f2 -d\|)
    vote=$(colorstripper "${vote}")
    subs=$(echo "${JIRA_COMMENT_TABLE[${i}]}" | cut -f3 -d\|)
    comment=$(echo "${JIRA_COMMENT_TABLE[${i}]}" | cut -f4- -d\|)
    
    if [[ -z ${vote} ]]; then
      printf "|      | %*s | " ${seccoladj} "${subs}"
      for j in ${comment}; do
        printf "|      | %*s | %s\n" ${seccoladj} " " "${j}"
      done
    else
      printf "| %4s | %*s | %s\n" "${vote}" ${seccoladj} \
      "${subs}" "${comment}"
    fi
    i=$((i+1))
  done
}

function submitJiraComment
{
  local result=$1
  local i
  local commentfile=/tmp/cf.$$
  
  if [[ ${JENKINS} != "true" ]] ; then
    return 0
  fi
  
  add_jira_footer "Console output" "${BUILD_URL}/console"
  
  if [[ ${result} == 0 ]]; then
    printf "{color:green}+1 overall{color}\n\n" > /tmp/cf.$$
  else
    printf "{color:red}-1 overall{color}\n\n" > /tmp/cf.$$
  fi
  
  i=0
  until [[ $i -eq ${#JIRA_HEADER[@]} ]]; do
    printf "%s\n" "${JIRA_HEADER[${i}]}" >> /tmp/cf.$$
    i=$((i+1))
  done
  
  printf "|| Vote || Subsystem || Comment ||\n" >> /tmp/cf.$$
  
  i=0
  until [[ $i -eq ${#JIRA_COMMENT_TABLE[@]} ]]; do
    printf "%s\n" "${JIRA_COMMENT_TABLE[${i}]}" >> /tmp/cf.$$
    i=$((i+1))
  done
  
  printf "|| Subsystem || Report ||" >> /tmp/cf.$$
  i=0
  until [[ $i -eq ${#JIRA_FOOTER_TABLE[@]} ]]; do
    printf "%s\n" "${JIRA_FOOTER_TABLE[${i}]}" >> /tmp/cf.$$
    i=$((i+1))
  done
  
  printf "\n\nThis message was automatically generated.\n\n" >> /tmp/cf.$$
  
  big_console_header "Adding comment to JIRA"
  
  export USER=hudson
  ${JIRACLI} -s https://issues.apache.org/jira -a addcomment -u hadoopqa -p "${JIRA_PASSWD}" --comment "$(cat ${commentfile})" --issue "${defect}"
  ${JIRACLI} -s https://issues.apache.org/jira -a logout -u hadoopqa -p "${JIRA_PASSWD}"
  
  rm ${commentfile}
}

function cleanupAndExit
{
  local result=$1
  
  if [[ ${JENKINS} == "true" ]] ; then
    if [[ -e "${PATCH_DIR}" ]] ; then
      mv "${PATCH_DIR}" "${BASEDIR}"
    fi
  fi
  big_console_header "Finished build."
  
  # shellcheck disable=SC2086
  exit ${result}
}

###############################################################################
###############################################################################
###############################################################################


### Check if arguments to the script have been specified properly or not
parseArgs "$@"
cd "${BASEDIR}"

find_java_home
(( RESULT = RESULT + $? ))
if [[ ${RESULT} != 0 ]] ; then
  submitJiraComment 1
  giveConsoleReport 1
  cleanupAndExit 1
fi

checkout
RESULT=$?
if [[ ${JENKINS} == "true" ]] ; then
  if [[ ${RESULT} != 0 ]] ; then
    exit 100
  fi
fi

downloadPatch

verifyPatch
(( RESULT = RESULT + $? ))
if [[ ${RESULT} != 0 ]] ; then
  submitJiraComment 1
  giveConsoleReport 1
  cleanupAndExit 1
fi

prebuildWithoutPatch
(( RESULT = RESULT + $? ))
if [[ ${RESULT} != 0 ]] ; then
  submitJiraComment 1
  giveConsoleReport 1
  cleanupAndExit 1
fi

checkAuthor
(( RESULT = RESULT + $? ))

if [[ ${JENKINS} == "true" ]] ; then
  cleanUpXml
fi

CHANGED_MODULES=$(findChangedModules)

checkTests
(( RESULT = RESULT + $? ))
applyPatch
APPLY_PATCH_RET=$?
(( RESULT = RESULT + APPLY_PATCH_RET ))
if [[ ${APPLY_PATCH_RET} != 0 ]] ; then
  submitJiraComment 1
  giveConsoleReport 1
  cleanupAndExit 1
fi
checkJavacWarnings
JAVAC_RET=$?
#2 is returned if the code could not compile
if [[ ${JAVAC_RET} == 2 ]] ; then
  submitJiraComment 1
  giveConsoleReport 1
  cleanupAndExit 1
fi

(( RESULT = RESULT + JAVAC_RET ))
checkJavadocWarnings
(( RESULT = RESULT + $? ))
### Checkstyle not implemented yet
#checkStyle
#(( RESULT = RESULT + $? ))
buildAndInstall
checkEclipseGeneration
(( RESULT = RESULT + $? ))
checkFindbugsWarnings
(( RESULT = RESULT + $? ))
checkReleaseAuditWarnings
(( RESULT = RESULT + $? ))
### Run tests for Jenkins or if explictly asked for by a developer
if [[ ${JENKINS} == "true" || $RUN_TESTS == "true" ]] ; then
  runTests
  (( RESULT = RESULT + $? ))
fi

submitJiraComment ${RESULT}
giveConsoleReport ${RESULT}
cleanupAndExit ${RESULT}
