#!/usr/bin/python
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

import re
import sys
from optparse import OptionParser
import httplib
import urllib
import cgi
try:
  import json
except ImportError:
  import simplejson as json


namePattern = re.compile(r' \([0-9]+\)')

def clean(str):
  return clean(re.sub(namePattern, "", str))

def formatComponents(str):
  str = re.sub(namePattern, '', str).replace("'", "")
  if str != "":
    ret = "(" + str + ")"
  else:
    ret = ""
  return clean(ret)
    
def clean(str):
  str=str.replace("_","\_")
  str=str.replace("\r","")
  str=str.replace("|","\|")
  str=str.rstrip()
  return str

def lessclean(str):
  str=str.replace("_","\_")
  str=str.replace("\r","")
  str=str.rstrip()
  return str

def mstr(obj):
  if (obj == None):
    return ""
  return unicode(obj)

class Version:
  """Represents a version number"""
  def __init__(self, data):
    self.mod = False
    self.data = data
    found = re.match('^((\d+)(\.\d+)*).*$', data)
    if (found):
      self.parts = [ int(p) for p in found.group(1).split('.') ]
    else:
      self.parts = []
    # backfill version with zeroes if missing parts
    self.parts.extend((0,) * (3 - len(self.parts)))

  def decBugFix(self):
    self.mod = True
    self.parts[2] -= 1
    return self

  def __str__(self):
    if (self.mod):
      return '.'.join([ str(p) for p in self.parts ])
    return self.data

  def __cmp__(self, other):
    return cmp(self.parts, other.parts)

class Jira:
  """A single JIRA"""

  def __init__(self, data, parent):
    self.key = data['key']
    self.fields = data['fields']
    self.parent = parent
    self.notes = None
    self.incompat = None
    self.reviewed = None

  def getId(self):
    return mstr(self.key)

  def getDescription(self):
    return mstr(self.fields['description'])

  def getReleaseNote(self):
    if (self.notes == None):
      field = self.parent.fieldIdMap['Release Note']
      if (self.fields.has_key(field)):
        self.notes=mstr(self.fields[field])
      else:
        self.notes=self.getDescription()
    return self.notes

  def getPriority(self):
    ret = ""
    pri = self.fields['priority']
    if(pri != None):
      ret = pri['name']
    return mstr(ret)

  def getAssignee(self):
    ret = ""
    mid = self.fields['assignee']
    if(mid != None):
      ret = mid['displayName']
    return mstr(ret)

  def getComponents(self):
    return " , ".join([ comp['name'] for comp in self.fields['components'] ])

  def getSummary(self):
    return self.fields['summary']

  def getType(self):
    ret = ""
    mid = self.fields['issuetype']
    if(mid != None):
      ret = mid['name']
    return mstr(ret)

  def getReporter(self):
    ret = ""
    mid = self.fields['reporter']
    if(mid != None):
      ret = mid['displayName']
    return mstr(ret)

  def getProject(self):
    ret = ""
    mid = self.fields['project']
    if(mid != None):
      ret = mid['key']
    return mstr(ret)

  def __cmp__(self,other):
    selfsplit=self.getId().split('-')
    othersplit=other.getId().split('-')
    v1=cmp(selfsplit[0],othersplit[0])
    if (v1!=0):
      return v1
    else:
      if selfsplit[1] < othersplit[1]:
        return True
      elif selfsplit[1] > othersplit[1]:
        return False
    return False

  def getIncompatibleChange(self):
    if (self.incompat == None):
      field = self.parent.fieldIdMap['Hadoop Flags']
      self.reviewed=False
      self.incompat=False
      if (self.fields.has_key(field)):
        if self.fields[field]:
          for hf in self.fields[field]:
            if hf['value'] == "Incompatible change":
              self.incompat=True
            if hf['value'] == "Reviewed":
              self.reviewed=True
    return self.incompat

class JiraIter:
  """An Iterator of JIRAs"""

  def __init__(self, versions):
    self.versions = versions

    resp = urllib.urlopen("https://issues.apache.org/jira/rest/api/2/field")
    data = json.loads(resp.read())

    self.fieldIdMap = {}
    for part in data:
      self.fieldIdMap[part['name']] = part['id']

    self.jiras = []
    at=0
    end=1
    count=100
    while (at < end):
      params = urllib.urlencode({'jql': "project in (HADOOP,HDFS,MAPREDUCE,YARN) and fixVersion in ('"+"' , '".join(versions)+"') and resolution = Fixed", 'startAt':at, 'maxResults':count})
      resp = urllib.urlopen("https://issues.apache.org/jira/rest/api/2/search?%s"%params)
      data = json.loads(resp.read())
      if (data.has_key('errorMessages')):
        raise Exception(data['errorMessages'])
      at = data['startAt'] + data['maxResults']
      end = data['total']
      self.jiras.extend(data['issues'])

    self.iter = self.jiras.__iter__()

  def __iter__(self):
    return self

  def next(self):
    data = self.iter.next()
    j = Jira(data, self)
    return j

class Outputs:
  """Several different files to output to at the same time"""

  def __init__(self, base_file_name, file_name_pattern, keys, params={}):
    self.params = params
    self.base = open(base_file_name%params, 'w')
    self.others = {}
    for key in keys:
      both = dict(params)
      both['key'] = key
      self.others[key] = open(file_name_pattern%both, 'w')

  def writeAll(self, pattern):
    both = dict(self.params)
    both['key'] = ''
    self.base.write(pattern%both)
    for key in self.others.keys():
      both = dict(self.params)
      both['key'] = key
      self.others[key].write(pattern%both)

  def writeKeyRaw(self, key, str):
    self.base.write(str)
    if (self.others.has_key(key)):
      self.others[key].write(str)
  
  def close(self):
    self.base.close()
    for fd in self.others.values():
      fd.close()

def main():
  parser = OptionParser(usage="usage: %prog i[--previousVer VERSION] --version VERSION")
  parser.add_option("-v", "--version", dest="versions",
             action="append", type="string", 
             help="versions in JIRA to include in releasenotes", metavar="VERSION")
  parser.add_option("--previousVer", dest="previousVer",
             action="store", type="string", 
             help="previous version to include in releasenotes", metavar="VERSION")

  (options, args) = parser.parse_args()

  if (options.versions == None):
    options.versions = []

  if (len(args) > 2):
    options.versions.append(args[2])

  if (len(options.versions) <= 0):
    parser.error("At least one version needs to be supplied")

  versions = [ Version(v) for v in options.versions];
  versions.sort();

  maxVersion = str(versions[-1])
  if(options.previousVer == None):  
    options.previousVer = str(versions[0].decBugFix())
    print >> sys.stderr, "WARNING: no previousVersion given, guessing it is "+options.previousVer

  list = JiraIter(options.versions)
  version = maxVersion
  outputs = Outputs("releasenotes.%(ver)s.md", 
    "releasenotes.%(key)s.%(ver)s.md", 
    ["HADOOP","HDFS","MAPREDUCE","YARN"], {"ver":maxVersion, "previousVer":options.previousVer})

  head = '# Hadoop %(key)s %(ver)s Release Notes\n\n' \
    'These release notes cover  new developer and user-facing incompatibilities, features, and major improvements.\n\n' \
    '## Changes since Hadoop %(previousVer)s\n\n'

  outputs.writeAll(head)

  for jira in sorted(list):
    if (jira.getIncompatibleChange()) and (len(jira.getReleaseNote())==0):
      outputs.writeKeyRaw(jira.getProject(),"---\n\n")
      line = '* [%s](https://issues.apache.org/jira/browse/%s) | *%s* | **%s**\n' \
        % (clean(jira.getId()), clean(jira.getId()), clean(jira.getPriority()),
           clean(jira.getSummary()))
      outputs.writeKeyRaw(jira.getProject(), line)
      line ='\n**WARNING: No release note provided for this incompatible change.**\n\n'
      outputs.writeKeyRaw(jira.getProject(), line)

    if (len(jira.getReleaseNote())>0):
      outputs.writeKeyRaw(jira.getProject(),"---\n\n")
      line = '* [%s](https://issues.apache.org/jira/browse/%s) | *%s* | **%s**\n' \
        % (clean(jira.getId()), clean(jira.getId()), clean(jira.getPriority()),
           clean(jira.getSummary()))
      outputs.writeKeyRaw(jira.getProject(), line)
      line ='\n%s\n\n' % (lessclean(jira.getReleaseNote()))
      outputs.writeKeyRaw(jira.getProject(), line)
      
 
  outputs.writeAll("\n\n")
  outputs.close()

if __name__ == "__main__":
  main()

