#!/usr/bin/perl
#
#

use strict;
use Data::Dumper;

my %JIRA;

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

sub process_broken($) {
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
    print "$JIRA{$_} $_\n";
  } 
  close($fh);
}

process_changes("hadoop-common-project/hadoop-common/CHANGES.TXT");
process_changes("hadoop-hdfs-project/hadoop-hdfs/CHANGES.TXT");
process_changes("hadoop-yarn-project/CHANGES.TXT");
process_changes("hadoop-mapreduce-project/CHANGES.TXT");

process_broken("dev-support/subtasks.txt");

#print Dumper(%JIRA);
