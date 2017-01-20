#!/usr/bin/env bash
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
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
 
# pkill is almost everywhere and much more trustworthy
if command -v pkill; then
  # shellcheck disable=SC2046
  pkill -9 -U $(id -u) apacheds || exit 0
else
  # shellcheck disable=SC2009
  pids=$(ps -ef | grep apacheds | grep -v grep | awk '{printf $2"\n"}')
  if [[ -n "${pids}" ]]; then
    # shellcheck disable=SC2086
    echo ${pids} | xargs -t kill -9
  fi
fi

