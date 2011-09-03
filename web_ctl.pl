#!/Users/punkish/perl5/perlbrew/perls/perl-5.14.1/bin/perl

#/usr/bin/env perl

=begin

===============================================================================

        FILE:  web_ctl.pl

       USAGE:  ./web_ctl.pl <command> [<application>]

 DESCRIPTION:  A command line interface to Starman-powered Dancer applications

     OPTIONS:  ---
REQUIREMENTS:  ---
        BUGS:  ---
       NOTES:  ---
      AUTHOR:  Puneet Kishor (Pk), <punkish@eidesis.org>
     COMPANY:  eidesis
     VERSION:  1.0
     CREATED:  07/17/2011 15:01:54 CDT
    REVISION:  ---
     LICENSE:  Released with a CC0 License Waiver.
               If you use my work, or improve on it, it would be nice if you 
               gave me credit, but you don't have to. Use it, make it better, 
               pass it on.
===============================================================================

=cut

use 5.14.1;
use strict;

my $cnf = '/Users/punkish/bin/web_ctl.conf';

=begin

Required, a configuration file referenced above in $cnf containing the following code

%CFG = (
    host => 'http://127.0.0.1',
    dirs => {                                       # full path to directories that 
        logs => '/Users/punkish/Logs',              #   store the logs
        appd => '/Users/punkish/Documents/www',     #   have all the apps listed below
        pids => '/Users/punkish/Pids'               #   store the pid files for the running apps
    },
    test => 0,                                      # Set 'test' => 1 to print the $cmd on STDOUT instead of running it
    envs => 'development',  # 'production';         # Change the 'environment' as needed
    apps => {                                       # Add apps and the ports they would run on
        all        => '',                           #   Note: 'all' is a special app. Don't change this.
        blog       => 5000,
        macrostrat => 5001,
        macromap   => 5002,
        geomaps    => 5003,
        pbdb       => 5004,
        sue        => 5005,
        punkish    => 5006
    }
);

=cut


# Get our configuration information
# From http://www.perlmonks.org/?node_id=464358
if (my $err = ReadCfg($cnf)) {
    say STDERR $err;
    exit(1);
}

for (keys %{$CFG::CFG{dirs}}) {
    die "Please create $CFG::CFG{dirs}{$_}\n" unless (-d $CFG::CFG{dirs}{$_});
}

my ($cmd, $app) = @ARGV;

my @cmds = qw(start restart stop status help);

if ($cmd eq 'help' || @ARGV < 1) {
    usage("Please provide arguments as follows:");
    exit;
}
elsif (! in_array($cmd, @cmds) ) {
    usage("Please provide a valid command as follows:");
    exit;
}

if ($cmd eq 'help' || $cmd ne 'status') {
    if (! in_array($app, keys %{$CFG::CFG{apps}}) ) {
        usage("Please provide a valid application as follows:");
        exit;
    }
    
    $cmd .= ($app eq 'all') ? '_all': "('$app')";
}

eval $cmd;

sub in_array {
    my ($arg, @arr) = @_;
    
    for (@arr) {
        return 1 if $arg eq $_;
    }
    return 0;
}

sub usage {
    my $mesg = shift;
    my $cmds = join " | ", @cmds;
    my $apps = join " | ", keys %{$CFG::CFG{apps}};
    say "\n***********************************************************\n" . 
        "USAGE: $mesg\n" . 
        "web_ctl.pl <command> [<application>]\n" . 
        "- <command> = ($cmds)\n" . 
        "- <application> = ($apps)\n" . 
        "  Note: <application> is not required for 'status' or 'help'\n" . 
        "************************************************************";
}

sub restart_all {   
    for my $app (keys %{$CFG::CFG{apps}}) {
        stop($app);
        start($app);
    }
}

sub restart {
    my ($app) = @_;
    
    stop($app);
    start($app);
}

sub stop_all {
    for my $app (keys %{$CFG::CFG{apps}}) {
        stop($app) unless $app eq 'all';
    }
}

sub stop {
    my ($app) = @_;
    
    my $pid    = $app . '.pid';
    
    unless (-e "$CFG::CFG{dirs}{pids}/$pid") {
        say "The app $app doesn't seem to be running... exiting.";
        exit;
    }
    
    my $cmd = "kill `head -1 $CFG::CFG{dirs}{pids}/$pid`";
    if ($CFG::CFG{test}) {
        say $cmd;
    }
    else {
        system($cmd);
    }
    say "Stopped $app";
}

sub start_all {
    for my $app (keys %{$CFG::CFG{apps}}) {
	start($app) unless $app eq 'all';
    }
}

sub start {
    my ($app) = @_;

    my $port   = ${$CFG::CFG{apps}}{$app};
    my $access = $app . '_access.log';
    my $error  = $app . '_error.log';
    my $pid    = $app . '.pid';
    
    my $prompt = '';
    if (-e "$CFG::CFG{dirs}{pids}/$pid") {
        while ($prompt ne 'q' and $prompt ne 'y') {
            print "The app $app seems to be running. Enter 'q' to quit, or 'y' to kill it and restart: ";
            chomp($prompt = <STDIN>);
        }
        
        if ($prompt eq 'q') {
            say "Exiting without starting $app";
            exit;
        }
        elsif ($prompt eq 'y') {
            say "Attempting to stop $app";
            stop($app);
        }
    }
    
    my @cmd = (
        "plackup",
        "-s Starman",
        "-p $port",
        "-w 10",
        "-E $CFG::CFG{envs}",
        "--access-log $CFG::CFG{dirs}{logs}/$access",
        "--error-log $CFG::CFG{dirs}{logs}/$error",
        "-D ",
        "--pid $CFG::CFG{dirs}{pids}/$pid",
        "-a $CFG::CFG{appd}/$app/bin/app.pl"
    );
    if ($CFG::CFG{test}) {
        say join(" ", @cmd);
    }
    else {
        system( join(" ", @cmd) );
    }
    say "Started $app on port $port. Browse at $CFG::CFG{host}:$port/";
}

sub status {
    opendir DIR, $CFG::CFG{dirs}{pids};
    my @pidfiles = grep {/\.pid$/} readdir(DIR);
    closedir(DIR);

    open(PS_F, "ps -lax | grep '[s]tarman master'|");
    
    PS: while (<PS_F>) {
        chomp;
        $_ = trim($_);
        
        #  UID   PID  PPID        F CPU PRI NI       SZ    RSS WCHAN     S             ADDR TTY           TIME CMD
        #  501  4882     1      104   0  31  0  2469860   4656 -      Ss   ffffff800e37f740 ??         0:00.08 starman master 
        my ($uid, $pid, $ppid, $f, $cpu, $pri, $ni, $sz, $rss, $wchan, $s, $addr, $tty, $time, $cmd) = split /\s+/;
        
        for my $pidfile (@pidfiles) {
            my $pid_in_file = qx{head -1 "$CFG::CFG{dirs}{pids}/$pidfile"}; #"
            
            if ($pid_in_file == $pid) {
                my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks) = stat("$CFG::CFG{pids}/$pidfile");
                my $app = $pidfile;
                $app =~ s/\.pid$//;
                say "'$app' has been running since " . localtime($mtime) . ". Browse it at $CFG::CFG{host}:${$CFG::CFG{apps}}{$app}/";
                next PS;
            }
        }
    }
    
    close(PS_F);
}

sub trim {
    my $string = shift;
    if ($string) {
        $string =~ s/^\s+//;
        $string =~ s/\s+$//;
        return $string;
    }
}

# From http://www.perlmonks.org/?node_id=464358
sub ReadCfg {
    my $file = $_[0];

    our $err;

    # Put config data into a separate namespace
    {
        package CFG;

        # Process the contents of the config file
        my $rc = do($file);

        # Check for errors
        if ($@) {
            $::err = "ERROR: Failure compiling '$file' - $@";
        }
        elsif (! defined($rc)) {
            $::err = "ERROR: Failure reading '$file' - $!";
        }
        elsif (! $rc) {
            $::err = "ERROR: Failure processing '$file'";
        }
    }

    return ($err);
}