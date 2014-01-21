#!/usr/bin/perl

package Live;

use strict;
use warnings;

use Project;
use Mixer;
use Song;
use Bridge;

#-------------------------------------LIVE USE-----------------------------------------------------

sub Start {
	my $project = shift;

	#TODO verify if Project is valid
	print "--------- Init Project $project->{project}{name} ---------\n";

	# copy jack plumbing file
	#-------------------------
	if ($project->{connections}{"jack.plumbing"} eq 1) {
		my $homedir = $ENV{"HOME"};
		warn "jack.plumbing already exists, file will be overwritten\n" if (-e "$homedir/.jack.plumbing");
		use File::Copy;
		copy("$project->{connections}{file}","$homedir/.jack.plumbing") or die "Copy failed: $!";
	}

	#verify that backends are active
	#---------------------------------
	
	#JACK
	my $pid_jackd = qx(pgrep jackd);
	if (!$pid_jackd) {
		print "Strange ...JACK server is not running ?? Starting it\n";
		my $command = $project->{JACK}{start};
		system ($command) if $command; 
	}
	else {
		print "JACK server running with PID $pid_jackd";
	}
	#TODO verify jack parameters
	$project->{backends}{JACK} = $pid_jackd;

	#JPMIDI
	my $pid_jpmidi = qx(pgrep jpmidi);
	if ($project->{midi_player}{enable}) {
		die "JPMIDI server is not running" unless $pid_jpmidi;
		print "JPMIDI server running with PID $pid_jpmidi";
	}
	$project->{backends}{JPMIDI} = $pid_jpmidi;

	#SAMPLER
	my $pid_linuxsampler = qx(pgrep linuxsampler);
	if ($project->{linuxsampler}{enable}) {
		die "LINUXSAMPLER is not running" unless $pid_linuxsampler;
		print "LINUXSAMPLER running with PID $pid_linuxsampler";
	}
	$project->{backends}{LINUXSAMPLER} = $pid_linuxsampler;

	#jack.plumbing
	my $pid_jackplumbing = qx(pgrep jack.plumbing);
	if ($project->{connections}{"jack.plumbing"} eq 1) {
		die "jack.plumbing is not running" unless $pid_jackplumbing;
		print "jack.plumbing running with PID $pid_jackplumbing";
	}
	$project->{backends}{JACKPLUMBING} = $pid_jackplumbing;

	#OSC/MIDI BRIDGE
	my $pid_osc2midibridge = qx(pgrep -f osc2midi);
	if ($project->{osc2midi}{enable} eq 1) {
		die "osc2midi bridge is not running" unless $pid_osc2midibridge;
		print "osc2midi bridge running with PID $pid_osc2midibridge";
	}
	$project->{backends}{OSC2MIDI} = $pid_osc2midibridge;
	
	# get song list
	#---------------
	my @songkeys = sort keys %{$project->{songs}};
	my @songlist;
	push (@songlist,$project->{songs}{$_}{song_globals}{friendly_name}) foreach @songkeys;
	print "SONGS :\n";
	print " - $_\n" foreach @songlist;

	# start mixers
	#---------------
	print "Starting mixers\n"; 
	$project->StartEngines;

	# load song chainsetups + dummy
	#--------------------------------
	my $playersport = $project->{mixers}{players}{ecasound}{port};
	foreach my $song (@songkeys) {
		#load song chainsetup
		print "Error: unable to load song $song\n" unless 
			$project->{mixers}{players}{ecasound}->LoadFromFile($project->{songs}{$song}{ecasound}{ecsfile});
	}
	#load dummy song chainsetup
	print "Error: unable to connect dummy player\n" unless
		$project->{mixers}{players}{ecasound}->SelectAndConnectChainsetup("players");

	#send previous state to ecasound engines
	#--------------------------------------
	&OSC_send("/refresh i 1");

	# now we should be back to saved state
	#--------------------------------------
}

sub PlayIt {
	my $project = shift;

	#TODO here should be the global parser accepting many thing like:
	#	tcp commands
	#	OSC messages
	#	gui actions (from tcp commands is best)
	#	front panel actions (from tcp commands)

	print "\n--------- Project $project->{project}{name} ---------\n";
	while (1) {
		print "$project->{project}{name}> ";
		my $command = <STDIN>;
		chomp $command;
		return if ($command =~ /exit|x|quit/);
		$project->execute_command($command);
	}
}

sub OSC_send {
	use Protocol::OSC;
	use IO::Socket::INET;

	my $osc = Protocol::OSC->new;
	#make packet
	my $data = $osc->message(my @specs = qw(/refresh i 1));
    # or
    #use Time::HiRes 'time';
    #my $data $osc->bundle(time, [@specs], [@specs2], ...);
		
	#send
	my $udp = IO::Socket::INET->new( PeerAddr => 'localhost', PeerPort => '8000', Proto => 'udp', Type => SOCK_DGRAM) || die $!;
	$udp->send($data);	
}

1;