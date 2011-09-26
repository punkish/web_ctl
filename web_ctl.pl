#!/usr/bin/env perl

# ===============================================================================
# 
#         FILE:  web_ctl.pl
# 
#        USAGE:  ./web_ctl.pl <command> [<application>]
# 
#  DESCRIPTION:  A command line interface to Starman-powered Dancer applications
# 
#      OPTIONS:  ---
# REQUIREMENTS:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Puneet Kishor (Pk), <punkish@eidesis.org>
#      COMPANY:  eidesis
#      VERSION:  1.0
#      CREATED:  07/17/2011 15:01:54 CDT
#     REVISION:  ---
#      LICENSE:  Released with a CC0 License Waiver.
#                If you use my work, or improve on it, it would be nice if you 
#                gave me credit, but you don't have to. Use it, make it better, 
#                pass it on.
# ===============================================================================

use 5.10.1;
use strict;

# Edit $cnf to point to the conf file. This is the *only* edit required in this script.
my $cnf = '/Volumes/roller/Users/punkish/bin/web_ctl/web_ctl.conf';

=begin

Required, a configuration file referenced above in $cnf containing the following code

# web_ctl.conf
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
        all  => '',                                 #   Note: 'all' is a special app. Don't change this.
        blog => 5000,
        app1 => 5001,
        app2 => 5002,
        app3 => 5003
    }
);

=cut


# Get our configuration information
# From http://www.perlmonks.org/?node_id=464358
if (my $err = ReadCfg($cnf)) {
    say STDERR $err;
    exit(1);
}

my $test = $CFG::CFG{test};
my $host = $CFG::CFG{host};
my $root = $CFG::CFG{root};
my $dir_logs = $root . '/' . $CFG::CFG{dirs}{logs};
my $dir_prod = $root . '/' . $CFG::CFG{dirs}{prod};
my $dir_test = $root . '/' . $CFG::CFG{dirs}{test};
my $dir_devl = $root . '/' . $CFG::CFG{dirs}{devl};
my $dir_pids = $root . '/' . $CFG::CFG{dirs}{pids};
my %apps = %{$CFG::CFG{apps}};

for (keys %{$CFG::CFG{dirs}}) {
    my $dir = $CFG::CFG{root} . '/' . $CFG::CFG{dirs}{$_};
    die "Please create $dir\n" unless (-d $dir);
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
    sleep 2;
    start($app);
}

sub stop_all {
    for my $app (keys %{$CFG::CFG{apps}}) {
        stop($app) unless $app eq 'all';
    }
}

sub stop {
    my ($app) = @_;
    
    my $env = $apps{$app}->{env};
    my $pid = $app . '_' . $env . '.pid';
    
    unless (-e "$dir_pids/$pid") {
        say "The app $app doesn't seem to be running... nothing to do.";
        return;
    }
    
    my $cmd = "kill `head -1 $dir_pids/$pid`";
    if ($test) {
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

    my $port   = $apps{$app}->{port};
    my $access = $app . '_access.log';
    my $error  = $app . '_error.log';
    my $env    = $apps{$app}->{env};
    my $pid    = $app . '_' . $env . '.pid';
    #say "pid: $pid";
    
    my $dir_appl = '';
    if ($env eq 'development') {
        $dir_appl = $dir_devl;
        $port += 20000;
    }
    elsif ($env eq 'testing') {
        $dir_appl = $dir_test;
        $port += 10000;
    }
    elsif ($env eq 'production') {
        $dir_appl = $dir_prod;
    }
    
    my $prompt = '';
    if (-e "$dir_pids/$pid") {
        while ($prompt ne 'c' and $prompt ne 'k') {
            print "The app $app is running. Enter 'k' to kill and restart it, 'c' to cancel this program: ";
            chomp($prompt = <STDIN>);
        }
        
        if ($prompt eq 'c') {
            say "Exiting without starting $app";
            exit;
        }
        elsif ($prompt eq 'k') {
            say "Attempting to stop $app";
            stop($app);
        }
    }

    my @cmd = (
        "plackup",
        "-s Starman",
        "-p $port",
        "-w 10",
        "-E $env",
        "--access-log $dir_logs/$access",
        "--error-log $dir_logs/$error",
        "-D",
        "--pid $dir_pids/$pid",
        "-a $dir_appl/$app/bin/app.pl"
    );
    if ($test) {
        say join(" ", @cmd);
    }
    else {
        system( join(" ", @cmd) );
    }
    say "Started $app on port $port. Browse at $host:$port";
}

sub status {
    opendir DIR, $dir_pids;
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
            my $pid_in_file = qx{head -1 "$dir_pids/$pidfile"}; #"
            
            if ($pid_in_file == $pid) {
                my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks) = stat("$dir_pids/$pidfile");
                my $app = $pidfile;
                $app =~ s/\.pid$//;
                say "'$app' has been running since " . localtime($ctime) . ". Browse it at $host:$apps{$app}->{port}/";
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
