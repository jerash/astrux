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

	# copy jack plumbing
	#----------------------
	if ($project->{connections}{"jack.plumbing"} eq 1) {
		my $homedir = $ENV{"HOME"};
		warn "jack.plumbing already exists, file will be overwritten\n" if (-e "$homedir/.jack.plumbing");
		use File::Copy;
		copy("$project->{connections}{file}","$homedir/.jack.plumbing") or die "Copy failed: $!";
	}

	#verify that backends are active
	#---------------------------------
	#TODO make a hash of backends/PID, or add to project {process}

	#JACK
	my $pid_jackd = qx(pgrep jackd);
	die "JACK server is not running" unless $pid_jackd;
	print "JACK server running with PID $pid_jackd";
	#TODO verify jack parameters

	#JPMIDI
	my $pid_jpmidi = qx(pgrep jpmidi);
	die "JPMIDI server is not running" unless $pid_jpmidi;
	print "JPMIDI server running with PID $pid_jpmidi";

	#SAMPLER
	if ($project->{linuxsampler}{enable}) {
		my $pid_linuxsampler = qx(pgrep linuxsampler);
		die "LINUXSAMPLER is not running" unless $pid_linuxsampler;
		print "LINUXSAMPLER running with PID $pid_linuxsampler\n";
	}

	#TODO OSC/MIDI BRIDGE

	
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
	# my @pid_mixers;
	# my $pid_mixer;
	
	foreach my $mixername (keys %{$project->{mixers}}) {
		print " - mixer $mixername\n";
		my $mixerfile = $project->{mixers}{$mixername}{ecasound}{ecsfile};
		my $path = $project->{project}{base_path}."/".$project->{project}{eca_cfg_path};
		my $port = $project->{mixers}{$mixername}{ecasound}{port};
		
		#if mixer is already running on same port, then reconfigure it
		my $ps = qx(ps ax);
		if  ($ps =~ /ecasound/ and $ps =~ /--server/ and $ps =~ /tcp-port=$port/) {
			print "Found existing Ecasound server on port $port, reconfiguring engine\n";
			#reconfigure ecasound engine with ecs file
			&EngineReconfigure($mixerfile,$project->{mixers}{$mixername}{ecasound}{name},$port);
			next;	
			#TODO parse ecasound reply to check for errors
		}

		#if mixer is not existing, launch mixer with needed file
		my $command = "ecasound -q -s $mixerfile -R $path/ecasoundrc --server --server-tcp-port=$port > /dev/null 2>&1 &\n";
		system ( $command );
		sleep(1);

		# #fork and exec
		# 	$SIG{CHLD} = sub { wait };
		# 	$pid_mixer = fork();
		# 	if ($pid_mixer) {
		# 		#we are parent
		# 		print "new pid_mixer = $pid_mixer\n";
		# 	   	push (@pid_mixers,$pid_mixer);
		# 		sleep(1);
		# 	}
		# 	elsif (defined $pid_mixer) {
		# 		#we are child
		# 		print "$command\n";
		# 	    exec( $command );
		#         die "unable to exec: $!";
		# 	}
		# 	else {
		# 		die "unable to fork: $!";
		# 	}
	}

	# load song chainsetups + dummy
	#--------------------------------
	my $playersport = $project->{mixers}{players}{ecasound}{port};
	foreach my $song (@songkeys) {
		#load song chainsetup
		&EngineLoad($project->{songs}{$song}{ecasound}{ecsfile},$playersport);
	}
	#load dummy song chainsetup
	&EngineReselect("players",$playersport);

	# Start OSC2midi bridge
	#--------------------------------
	#$project->{bridge}->run;
	print "------------HEREIAM-------------\n";

	# now should have sound
	#--------------------------------
	&Play;
}

sub Play {
	print "i'm playing!";
}

sub EngineLoad {
	my $file = shift;
	my $port = shift;
	system ( "echo \"cs-load $file\" | nc localhost $port -C" );	
}
sub EngineReconfigure {
	my $file = shift;
	my $name = shift;
	my $port = shift;

	my $command = "echo \"cs-load $file\" | nc localhost $port -C";
	system ( $command );
	$command = "echo \"cs-select $name\" | nc localhost $port -C";
	system ( $command );
	$command = "echo \"cs-connect\" | nc localhost $port -C";
	system ( $command );
	$command = "echo \"engine-launch\" | nc localhost $port -C";
	system ( $command );
}
sub EngineReselect {
	my $song = shift;
	my $port = shift;

	my $command = "echo \"cs-select $song\" | nc localhost $port -C";
	system ( $command );
	$command = "echo \"cs-connect\" | nc localhost $port -C";
	system ( $command );
	$command = "echo \"engine-launch\" | nc localhost $port -C";
	system ( $command );
}

1;