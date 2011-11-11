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
use Getopt::Std;

# Edit $cnf to point to the conf file. This is the *only* edit required in this script.
my $cnf = '/Volumes/roller/Users/punkish/bin/web_ctl/web_ctl.conf';

=begin

Required, a configuration file referenced above in $cnf containing the following code

# web_ctl.conf
%CFG = (
	default_workers => 5,
	test => 0,
	host => 'http://127.0.0.1',
	root => '/Volumes/roller/Users/punkish',
	dirs => {
		logs => 'Logs',
		prod => 'Sites_production',
		test => 'Sites_testing',
		devl => 'Sites_development',
		pids => 'Pids'
	},
	apps => {
		blog				=> {port => 5000},
		macrostrat			=> {port => 5001},
		macromap			=> {port => 5002},
		geomaps				=> {port => 5003, workers => 10},
		pbdb				=> {port => 5004},
		sue					=> {port => 5005},
		punkish				=> {port => 5006},
		humanesettlements	=> {port => 5007},
		geoplates			=> {port => 5008},
	ecoval					=> {port => 5009}
	}
);

=cut

# Get our configuration information
# From http://www.perlmonks.org/?node_id=464358
if (my $err = ReadCfg($cnf)) {
    say STDERR $err;
    exit(1);
}

my $default_workers = $CFG::CFG{default_workers};
my $test = $CFG::CFG{test};
my $host = $CFG::CFG{host};
my $root = $CFG::CFG{root};
my $dir_logs = $root . '/' . $CFG::CFG{dirs}{logs};
my $dir_prod = $root . '/' . $CFG::CFG{dirs}{prod};
my $dir_test = $root . '/' . $CFG::CFG{dirs}{test};
my $dir_devl = $root . '/' . $CFG::CFG{dirs}{devl};
my $dir_pids = $root . '/' . $CFG::CFG{dirs}{pids};
my %apps = %{$CFG::CFG{apps}};

# Read the command line arguments
our ($opt_c, $opt_a, $opt_e);
getopt('cae');


#### Check the command line arguments
# Check the commands
my @cmds = qw(start restart stop status help);
if ($opt_c eq 'help') {
    usage("Please provide arguments as follows:");
    exit;
}
elsif (!in_array($opt_c, @cmds) ) {
    usage("Please provide a valid command as follows:");
    exit;
}

# Check the environment
if ($opt_e ne 'development' && $opt_e ne 'production') {
    usage("Please provide environment as follows:");
    exit;
}

# Check the application
if ($opt_a ne 'all' && !in_array($opt_a, keys %apps) ) {
    usage("Please provide a valid application as follows:");
    exit;
}

# Check if the directories exist
for (keys %{$CFG::CFG{dirs}}) {
    my $dir = $CFG::CFG{root} . '/' . $CFG::CFG{dirs}{$_};
    die "Please create $dir\n" unless (-d $dir);
}

if ($opt_a eq 'all') {
    $opt_c .= '_all';
}

my $dispatch = {
    stop_all    => \&stop_all,
    stop        => \&stop,
    start_all   => \&start_all,
    start       => \&start,
    status_all  => \&status_all,
    status      => \&status,
    restart_all => \&restart_all,
    restart     => \&restart
};

# Run the command
$dispatch->{$opt_c}->($opt_a);


sub usage {
    my $mesg = shift;
    my $cmds = join " | ", @cmds; $cmds = 'all | ' . $cmds;
    my $apps = join " | ", keys %{$CFG::CFG{apps}};
    say "\n***********************************************************\n" . 
        "USAGE: $mesg\n" . 
        "web_ctl.pl -c <command> -a [<application>] -e [development | production]\n" . 
        "- <command> = ($cmds)\n" . 
        "- <application> = ($apps)\n" .  
        "************************************************************";
}

sub in_array {
    my ($arg, @arr) = @_;
    
    for (@arr) {
        return 1 if $arg eq $_;
    }
    return 0;
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

sub status_all {
    for my $app (keys %apps) {
        status($app);
    }
}

sub status {
    my ($app) = @_;
    
    my $pidfile = $app . '_' . $opt_e . '.pid';

    if (-e "$dir_pids/$pidfile") {
        open(PS_F, "ps -lax | grep '[s]tarman master'|");
        
        PS: while (<PS_F>) {
            chomp;
            $_ = trim($_);
            
            #  UID   PID  PPID        F CPU PRI NI       SZ    RSS WCHAN     S             ADDR TTY           TIME CMD
            #  501  4882     1      104   0  31  0  2469860   4656 -      Ss   ffffff800e37f740 ??         0:00.08 starman master 
            my ($uid, $pid, $ppid, $f, $cpu, $pri, $ni, $sz, $rss, $wchan, $s, $addr, $tty, $time, $cmd) = split /\s+/;
            
            my $pid_in_file = qx{head -1 "$dir_pids/$pidfile"}; #"
                
            if ($pid_in_file == $pid) {
                my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks) = stat("$dir_pids/$pidfile");
                say "application: $app";
                say "    running since: " . localtime($ctime);
                say "    in mode      : " . $opt_e;
                say "    browse at    : " . $host . ':' . $apps{$app}->{port} . "/\n";
                last PS;
            }
        }
        
        close(PS_F);
    }
    else {
        say "'$app' doesn't seem to be running in mode '$opt_e'";
    }
}

sub stop_all {
    for my $app (keys %apps) {
        stop($app);
    }
}

sub stop {
    my ($app) = @_;
    
    my $pid = $app . '_' . $opt_e . '.pid';
    
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
    for my $app (keys %apps) {
	   start($app);
    }
}

sub start {
    my ($app) = @_;

    my $port   = $apps{$app}->{port};
	my $workers = $apps{$app}->{workers} || $default_workers;
    my $access = $app . '_access.log';
    my $error  = $app . '_error.log';
    my $env    = $opt_e;
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
        "-w $workers",
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

sub restart_all {   
    for my $app (keys %apps) {
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

sub trim {
    my $string = shift;
    if ($string) {
        $string =~ s/^\s+//;
        $string =~ s/\s+$//;
        return $string;
    }
}
