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
		#wait for ecasound engines to be ready
		sleep(1) until $project->{mixers}{$mixername}{ecasound}->is_ready;
		print "Ecasound $mixername is ready\n";

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

	#send previous state to ecasound engines
	#--------------------------------------
	&OSC_send("/refresh i 1");

	# now we should be back to saved state
	#--------------------------------------
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

sub PlayIt {
	my $project = shift;

	print "\n--------- Project $project->{project}{name} ---------\n";
	while (1) {
		print "$project->{project}{name}> ";
		my $command = <STDIN>;
		chomp $command;
		#exit with save
		return 1 if ($command =~ /exit|x|quit/);
		#exit without save
		return 0 if ($command =~ /bye|z/);
		#save
		$project->SaveTofile("$project->{project}{name}".".cfg") if ($command eq "save");
	}
}

sub Exit {
	my $project = shift;

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