#!/usr/bin/perl
#
#

use strict;
use Data::Dumper;

my %JIRA;
my $key;

sub process_changes($) {
  my $filename=shift;
  my $release="3.0.0";
  my $line;
  my $fh;
  my $j;
  my $notdone;
  open($fh,$filename) || die "$0: $! [$filename]\n";
  while (<$fh>)  {
    chomp;
    s,\s+, ,g;
    $line=$_;
    if ($line =~ /Release/) {
      $release=(split(' ',$line))[1];
      next;
    }
    if ($release =~ /0.20/) {
      $notdone=1;
      next;
    }
    if ($line =~ /(HADOOP|YARN|HDFS|MAPRED)/) {
      $j=(split(' ',$line))[0];
      $j=~ s,\.,,g;
      $JIRA{$j}=$release;
    }
  } 
  close($fh);
}

process_changes("hadoop-common-project/hadoop-common/CHANGES.TXT");
process_changes("hadoop-hdfs-project/hadoop-hdfs/CHANGES.TXT");
process_changes("hadoop-yarn-project/CHANGES.TXT");
process_changes("hadoop-mapreduce-project/CHANGES.TXT");

foreach $key (sort(keys %JIRA)) {
  if ( $JIRA{$key}=="3.0.0" ){
    print $key,"\n";
  }
}
