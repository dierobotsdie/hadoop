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

cat <<EOF

# Self-contained, single node

RUN mkdir -p /opt/hadoop-${HADOOP_VERSION}/logs

RUN cp -pr /opt/hadoop-${HADOOP_VERSION}/etc/hadoop /etc

RUN echo "export JAVA_HOME=\\\$(find /usr/lib/jvm/ -name \"java-*\" -type d | tail -1)" >> /etc/hadoop/hadoop-env.sh

ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64

ENV HADOOP_CONF_DIR /etc/hadoop

RUN printf "\
<configuration>\n\
  <property>\n\
    <name>fs.defaultFS</name>\n\
    <value>hdfs://@@HOSTNAME@@:9000</value>\n\
  </property>\n\
</configuration>\n\
" > /etc/hadoop/core-site.xml.t

RUN printf "\
<configuration>\n\
  <property>\n\
    <name>dfs.replication</name>\n\
    <value>1</value>\n\
  </property>\n\
</configuration>\n\
" > /etc/hadoop/hdfs-site.xml.t

RUN printf "\
<configuration>\n\
  <property>\n\
    <name>mapreduce.framework.name</name>\n\
    <value>yarn</value>\n\
  </property>\n\
  <property>\n\
    <name>mapreduce.admin.user.env</name>\n\
    <value>HADOOP_MAPRED_HOME=\${HADOOP_MAPRED_HOME}</value>\n\
  </property>\n\
  <property>\n\
    <name>yarn.app.mapreduce.am.env</name>\n\
    <value>HADOOP_MAPRED_HOME=\${HADOOP_MAPRED_HOME}</value>\n\
  </property>\n\
</configuration>\n\
" > /etc/hadoop/mapred-site.xml.t

RUN printf "\
<configuration>\n\
  <property>\n\
    <name>yarn.nodemanager.aux-services</name>\n\
    <value>mapreduce_shuffle</value>\n\
  </property>\n\
  <property>\n\
    <name>yarn.nodemanager.aux-services</name>\n\
    <value>mapreduce_shuffle</value>\n\
  </property>\n\
  <property>\n\
    <name>yarn.nodemanager.vmem-check-enabled</name>\n\
    <value>false</value>\n\
  </property>\n\
</configuration>\n\
" > /etc/hadoop/yarn-site.xml.t
EOF

RUN printf "\
export HDFS_NAMENODE_USER=hdfs\n\
export HDFS_DATANODE_USER=hdfs\n\
export HDFS_SECONDARYNAMENODE_USER=hdfs\n\
export YARN_RESOURCEMANAGER_USER=yarn\n\
export YARN_NODEMANAGER_USER=yarn\n\
export YARN_PROXYSERVER_USER=yarn\n\
export YARN_TIMELINESERVER_USER=yarn\n\
" >> /etc/hadoop/hadoop-env.sh.t

RUN adduser --system hadoop
RUN adduser --system --ingroup hadoop yarn
RUN adduser --system --ingroup hadoop hdfs
