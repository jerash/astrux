#!/usr/bin/perl

package Live;

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin;

use Load;
use Project;
use Mixer;
use Song;
use Bridge;
use Utils;

###########################################################
#
#		 INIT LIVE
#
###########################################################

#autoflush
$| = 1;

#----------------------------------------------------------------
# This is the main entry point for Astrux Live
#----------------------------------------------------------------

if ($#ARGV+1 eq 0) {
	die "usage : start_project project_name.cfg\n";
}

#------------LOAD project structure----------------------------

my $infile = $ARGV[0];
print "Opening : $infile\n";
Load::LoadStoredProject($infile);
our $project;

#TODO verify if Project is valid

print "--------- Init Project $project->{globals}{name} ---------\n";

#verify services and servers

#JACK
#---------------------------------
my $pid_jackd = qx(pgrep jackd);
if (!$pid_jackd) {
	print "Strange ...JACK server is not running ?? Starting it\n";
	my $command = "$project->{jack}{start} 2>&1 &";
	system ($command) if $command;
	sleep 1;
	$pid_jackd = qx(pgrep jackd);
}
else {
	print "JACK server running with PID $pid_jackd";
	#verify jack parameters
	my $params = qx(ps $pid_jackd);
	die "JACK server doesn't have project parameters, please check.\nExpected : $project->{jack}{start}\nFound :\n$params"
		unless $params =~ $project->{jack}{start};
	print "JACK server parameters ok\n";
}
$project->{JACK}{PID} = $pid_jackd;

#jack.plumbing
#---------------------------------
# copy jack plumbing file
if ( $project->{plumbing}{enable} eq '1') {
	my $homedir = $ENV{HOME};
	warn "jack.plumbing already exists, file will be overwritten\n" if (-e "$homedir/.jack.plumbing");
	use File::Copy;
	copy("$project->{plumbing}{file}","$homedir/.jack.plumbing") or die "jack.plumbing copy failed: $!";
}
# start jack.plumbing
my $pid_jackplumbing = qx(pgrep jack.plumbing);
if ($project->{plumbing}{enable}) {
	if (!$pid_jackplumbing) {
		print "jack.plumbing is not running. Starting it\n";
		my $command = "jack.plumbing > /dev/null 2>&1 &";
		system ($command);
		sleep 1;
		$pid_jackplumbing = qx(pgrep jackd);
	}
	print "jack.plumbing running with PID $pid_jackplumbing";
}
$project->{plumbing}{PID} = $pid_jackplumbing;

#JACK-OSC (jack.clock)
#---------------------------------
my $pid_jackosc = qx(pgrep jack-osc);
if ($project->{'jack-osc'}{enable}) {
	if (!$pid_jackosc) {
		print "jack-osc server is not running, starting it\n";
		my $command = "jack-osc -p $project->{'jack-osc'}{osc_port} 2>&1 &";
		system ($command);
		sleep 1;
		$pid_jackosc = qx(pgrep jack-osc);
	}
	print "jack-osc server running with PID $pid_jackosc";
	$project->{'jack-osc'}{PID} = $pid_jackosc;
}
#JPMIDI << TODO problem in server mode can't load new midi file....
#---------------------------------
# my $pid_jpmidi = qx(pgrep jpmidi);
# if ($project->{midi_player}{enable}) {
# 	die "JPMIDI server is not running" unless $pid_jpmidi;
# 	print "JPMIDI server running with PID $pid_jpmidi";
# }
# $project->{midi_player}{PID} = $pid_jpmidi;

#SAMPLER
#---------------------------------
my $pid_linuxsampler = qx(pgrep linuxsampler);
#TODO check linuxsampler is running on the expected port
if ($project->{linuxsampler}{enable}) {
	die "LINUXSAMPLER is not running" unless $pid_linuxsampler;
	print "LINUXSAMPLER running with PID $pid_linuxsampler";
	$project->{LINUXSAMPLER}{PID} = $pid_linuxsampler;
}

#a2jmidid
#---------------------------------
my $pid_a2jmidid = qx(pgrep -f a2jmidid);
#die "alsa to jack midi bridge is not running" unless $pid_a2jmidid;
if ($project->{a2jmidid}{enable}) {
	if (!$pid_a2jmidid) {
		system('a2jmidid -e > /dev/null 2>&1 &');
		sleep 1;
		$pid_a2jmidid = qx(pgrep -f a2jmidid);
	}
	print "a2jmidid running with PID $pid_a2jmidid";
	$project->{a2jmidid}{PID} = $pid_a2jmidid;
}

# start mixers
#---------------------------------
print "Starting mixers engines\n"; 
$project->StartEngines;

# load song chainsetups + dummy
#--------------------------------
my @songkeys = sort keys %{$project->{songs}};
print "SONGS :\n";
foreach my $song (@songkeys) {
	#load song chainsetup
	print " - $project->{songs}{$song}{friendly_name}\n";
	print $project->{mixers}{players}{engine}->LoadFromFile($project->{songs}{$song}{ecasound}{ecsfile});
}
#load dummy song chainsetup
$project->{mixers}{players}{engine}->SelectAndConnectChainsetup("players");

# Start bridge > wait loop
#--------------------------------------
print "\n--------- Project $project->{globals}{name} Running---------\n";
$project->{bridge}->start;
