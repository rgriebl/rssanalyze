#!/usr/bin/perl
use strict;

for my $arg (@ARGV) {
    open DATA, "</proc/$arg/smaps" or die("Cannot open smaps file for PID $arg");
    my %lines;
    while (<DATA>) {
        /(\w+):\s*(\d+) kB/ or next;
        $lines{$1} += $2;
    }
    close DATA;

    my $prefix = "$arg:  " if (scalar @ARGV > 1);
    printf "${prefix}Total mapped memory:     %d kB\n", $lines{'Size'};
    printf "${prefix}  of which are resident: %d kB\n", $lines{'Rss'};
    printf "${prefix}                 Shared: %d kB clean (%.1f%%), %d kB dirty (%.1f%%)\n",
          $lines{'Shared_Clean'},
          $lines{'Shared_Clean'} * 100 / ($lines{'Shared_Clean'} + $lines{'Shared_Dirty'}),
          $lines{'Shared_Dirty'},
          $lines{'Shared_Dirty'} * 100 / ($lines{'Shared_Clean'} + $lines{'Shared_Dirty'}), "%)\n";
    printf "${prefix}                Private: %d kB clean (%.1f%%), %d kB dirty (%.1f%%)\n",
          $lines{'Private_Clean'},
          $lines{'Private_Clean'} * 100 / ($lines{'Private_Clean'} + $lines{'Private_Dirty'}),
          $lines{'Private_Dirty'},
          $lines{'Private_Dirty'} * 100 / ($lines{'Private_Clean'} + $lines{'Private_Dirty'}), "%)\n";
}
