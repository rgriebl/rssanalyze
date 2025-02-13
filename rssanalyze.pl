#!/usr/bin/perl
use strict;
my $prefix;
my $verbose = 0;
my $proc = "/proc";
my %lines;
my @mapkeys;
my %mappings;
my $sizeAndRss = [['VSZ', "Size"], ['RSS', "Rss"]];
my $breakdown = [
    ['VSZ', "Size"],
    ['SC', "Shared_Clean"],
    ['SD', "Shared_Dirty"],
    ['PC', "Private_Clean"],
    ['PD', "Private_Dirty"],
    ['Swap', "Swap"]
];

sub percent($$) {
    my $value = $_[0];
    my $total = $_[1];
    return "n/a" if $total == 0;
    return $value * 100 / $total;
}

sub sharedPrivateReport($) {
    my $type = $_[0];
    my $clean = $lines{$type . "_Clean"};
    my $dirty = $lines{$type . "_Dirty"};
    my $anonymous =
	$lines{"Anonymous_${type}_Clean"} +
	$lines{"Anonymous_${type}_Dirty"};
    my $thread_stack =
	$lines{"Thread_Stack_${type}_Clean"} +
	$lines{"Thread_Stack_${type}_Dirty"} +
	$lines{"Main_Stack_${type}_Clean"} +
	$lines{"Main_Stack_${type}_Dirty"};
    my $code =
	$lines{"Code_${type}_Clean"} +
	$lines{"Code_${type}_Dirty"};
    my $rodata =
	$lines{"ROData_${type}_Clean"} +
	$lines{"ROData_${type}_Dirty"};
    my $rwdata =
	$lines{"RWData_${type}_Clean"} +
	$lines{"RWData_${type}_Dirty"};
    my $total = $clean + $dirty;
    my $other = $total - $anonymous - $thread_stack - $rodata - $rwdata - $code;

    printf("${prefix}                %7s: %d kB total (%.1f%% of RSS)\n",
          $_[0], $total, percent($total, $lines{'Rss'}));
    printf("${prefix}              Breakdown: %d kB clean (%.1f%%), %d kB dirty (%.1f%%)\n",
	   $clean, percent($clean, $total),
	   $dirty, percent($dirty, $total));
    printf("${prefix}                         %d kB code (%.1f%%), %d kB RO data (%.1f%%), %d kB RW data (%.1f%%)\n".
	   "${prefix}                         %d kB heap (%.1f%%), %d kB stack (%.1f%%), %d kB other (%.1f%%)\n",
	   $code, percent($code, $total),
	   $rodata, percent($rodata, $total),
	   $rwdata, percent($rwdata, $total),
	   $anonymous, percent($anonymous, $total),
	   $thread_stack, percent($thread_stack, $total),
	   $other, percent($other, $total));
}

sub verboseReport($$$) {
    my ($heading, $base, $selectors) = @_;
    my %totals = ();
    for my $key (@mapkeys) {
        my %mapinfo = %{$mappings{$key}};
        my $sizes = "";
        for my $selector (@{$selectors}) {
            my @selector = @{$selector};
            my $value = $mapinfo{"${base}_$selector[1]"};
            next unless $value;
            $totals{$selector[1]} += $value;
            $sizes .= sprintf("%s:%dkB ", $selector[0], $value);
        }

        next unless length($sizes);
        print "$prefix$heading:\n" if length($heading);
        $heading = "";
        printf "${prefix} %-25s  %-25s\t%s\n",
            $key, $sizes, $mapinfo{"file"};
    }

    my $sizes = "";
    for my $selector (@{$selectors}) {
        my @selector = @{$selector};
        my $value = $totals{$selector[1]};
        next unless $value;
        $totals{$selector[1]} += $value;
        $sizes .= sprintf("%s:%dkB ", $selector[0], $value);
    }
    printf "${prefix} %-25s  %-20s\n", "Total", $sizes
        if length($sizes);
}

sub addTo($$$) {
    my ($name, $value, $header) = @_;
    $lines{"$name"} += $value;
    return unless $verbose;

    my @header = @{$header};
    my $key = $header[0];
    my %mapinfo = %{$mappings{$key}} if defined($mappings{$key});
    $mapinfo{$name} = $value;
    $mapinfo{"file"} = $header[5];
    $mappings{$key} = \%mapinfo;
}

my @pids;

for my $arg (@ARGV) {
    if ($arg eq "-v" || $arg eq "-vv") {
        ++$verbose;
        ++$verbose if $arg eq "-vv";
    } elsif ($arg =~ /^--proc=/) {
        $proc = substr($arg, 7);
        print "Redirecting /proc access to $proc";
    } else {
        push @pids, $arg;
    }
}

for my $pid (@pids) {
    my $stacksize = 8192;   # Default on Linux
    if (open LIMITS, "<$proc/$pid/limits") {
        $stacksize = (map { /Max stack size\s+(\d+)/ ? $1 : (); } <LIMITS>)[0] / 1024;
        close LIMITS;
    }

    open DATA, "<$proc/$pid/smaps" or die("Cannot open smaps file for PID $pid");
    my @header;
    my @lastheader;
    %lines = ();
    %mappings = ();
    while (<DATA>) {
	if (/^([0-9a-f-]+) ([rwxps-]{4}) ([0-9a-f-]+) ([0-9a-f:]+) (\d+)\s+(.*)$/) {
            @lastheader = @header;
            @header = ($1, $2, $3, $4, $5, $6);
            my @vm = split /-/, $1;
            push @header, (hex($vm[1]) - hex($vm[0])) / 1024;
	}

        /(\w+):\s*(\d+) kB/ or next;
        addTo($1, $2, \@header);
	if ($header[5] eq '[stack]' || %header[5] eq "[stack:$pid]") {
	    addTo("Main_Stack_$1", $2, \@header);
        } elsif ($header[5] =~ m/\[stack:/) {
            addTo("Thread_Stack_$1", $2, \@header);
	} elsif ($header[1] eq 'rw-p') {
            # Check if it's a .bss section (contiguous to a previous rw-p) or a thread stack
            my $likely_thread_stack = ($header[6] == $stacksize && $header[3] eq '00:00' && $lastheader[1] eq '---p');

	    if ($likely_thread_stack) {
		addTo("Thread_Stack_$1", $2, \@header);
            } elsif ($header[5] =~ /\[(?!heap)/) {
            } elsif ($header[3] eq '00:00') {
                my $start = (split /-/, $header[0])[0];
                my $lastend = (split /-/, $lastheader[0])[1];
                if ($start eq $lastend && $lastheader[3] ne '00:00') {
                    addTo("RWData_$1", $2, \@header);
                } else {
                    addTo("Anonymous_$1", $2, \@header);
                }
            } else {
		addTo("RWData_$1", $2, \@header);
	    }
	} elsif ($header[1] eq 'rw-s' && $header[3] ne '00:00') {
	    addTo("RWData_$1", $2, \@header);
	} elsif ($header[1] eq 'r--p' || $header[1] eq 'r--s') {
	    addTo("ROData_$1", $2, \@header);
	} elsif ($header[1] eq 'r-xp') {
	    addTo("Code_$1", $2, \@header);
	} elsif ($header[1] eq 'rwxp') {
	    addTo("RWCode_$1", $2, \@header);
	} elsif ($header[1] eq '---p') {
	    addTo("Padding_$1", $2, \@header);
	}
    }
    close DATA;

    if (scalar @ARGV > 1) {
        my $cmdline;
        $prefix = "$pid:  ";
        open CMDLINE, "<", "/$proc/$pid/cmdline";
        binmode(CMDLINE);
        read CMDLINE, $cmdline, 512;
        close CMDLINE;
        printf "${prefix}Cmd: %s\n", join(' ', split(chr(0), $cmdline));
    }
    if ($verbose) {
        @mapkeys = sort keys %mappings;
        print "${prefix}Memory classification:\n";
        verboseReport("Padding regions", "Padding", [['VSZ', 'Size']])
            if $verbose > 1;
        verboseReport("Heap", 'Anonymous', $sizeAndRss);
        verboseReport("Main stack", "Main_Stack", $sizeAndRss);
        verboseReport("Thread stack", "Thread_Stack", $sizeAndRss);

        my $selector = ($verbose > 1 ? $breakdown : $sizeAndRss);
        verboseReport("Code (.text)", 'Code', $selector);
        verboseReport("JIT/SMC code", 'RWCode', $selector);
        verboseReport("Read-only data (.rodata)", 'ROData', $selector);
        verboseReport("Writable data (.data, .bss)", 'RWData', $selector);
        print "${prefix}[S = Shared, P = Private; C = Clean, D = Dirty]\n"
            if $verbose > 1;
        print "${prefix}\n${prefix}Summary:\n";
    }

    printf "${prefix}Total mapped memory:     %d kB\n", $lines{'Size'};
    printf "${prefix}    of which is padding: %d kB\n", $lines{'Padding_Size'};
    printf "${prefix}   of which swapped out: %d kB\n", $lines{'Swap'};
    printf "${prefix}  of which likely stack: %d kB mapped, %d kB resident (%d kB main, %d kB aux threads)\n",
          $lines{'Main_Stack_Size'} + $lines{'Thread_Stack_Size'},
          $lines{'Main_Stack_Rss'} + $lines{'Thread_Stack_Rss'},
          $lines{'Main_Stack_Rss'}, $lines{'Thread_Stack_Rss'};

    printf "${prefix}  of which are resident: %d kB, %d kB proportionally shared\n", $lines{'Rss'},
          $lines{'Pss'};
    printf "${prefix}        total anonymous: %d kB (%.1f%%)\n",
	$lines{'Anonymous'}, percent($lines{'Anonymous'}, $lines{'Rss'});

    sharedPrivateReport('Shared');
    sharedPrivateReport('Private');
}
