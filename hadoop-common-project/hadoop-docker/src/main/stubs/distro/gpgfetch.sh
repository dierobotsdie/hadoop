# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.# See the License for the specific language governing permissions and
# limitations under the License.

## @description  Default command handler
## @audience     public
## @stability    stable
## @replaceable  no
## @param        CLI arguments
function main
{
  while true; do
    case "$1" in
      --distro-gpgfetch-ascbaseurl)
        shift
        HADOOP_DF_GPG_ASCBASEURL=$1
        shift
      ;;
      --distro-gpgfetch-keysurl)
        shift
        HADOOP_DF_GPG_KEYSURL=$1
        shift
      ;;
      --distro-gpgfetch-tarbaseurl)
        shift
        HADOOP_DF_GPG_TARBASEURL=$1
        shift
      ;;
      *)
        break;
      ;;
    esac
  done
}

main "$@"

HADOOP_DF_GPG_TARBASEURL=https://www.apache.org/dyn/closer.cgi?action=download\\\&filename=hadoop/core/hadoop-${HADOOP_VERSION}
HADOOP_DF_GPG_ASCBASEURL=https://dist.apache.org/repos/dist/release/hadoop/common/hadoop-${HADOOP_VERSION}
HADOOP_DF_GPG_KEYSURL=https://dist.apache.org/repos/dist/release/hadoop/common/KEYS

cat <<EOF

# Download and extract from

RUN curl -s -L -o /tmp/hadoop-${HADOOP_VERSION}.tar.gz ${HADOOP_DF_GPG_TARBASEURL}/hadoop-${HADOOP_VERSION}.tar.gz
RUN curl -s -L -o /tmp/hadoop-${HADOOP_VERSION}.tar.gz.asc ${HADOOP_DF_GPG_ASCBASEURL}/hadoop-${HADOOP_VERSION}.tar.gz.asc
RUN curl -s -L -o /tmp/KEYS_HADOOP ${HADOOP_DF_GPG_KEYSURL}
RUN gpg --import /tmp/KEYS_HADOOP
RUN gpg --refresh-keys
RUN gpg --verify /tmp/hadoop-${HADOOP_VERSION}.tar.gz.asc
RUN cd /opt && tar xzpf /tmp/hadoop-${HADOOP_VERSION}.tar.gz
EOF
