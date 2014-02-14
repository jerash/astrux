#!/usr/bin/perl

package Live;

use strict;
use warnings;

#use Net::OpenSoundControl::Server;
use Protocol::OSC;
use IO::Socket::INET;

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::ReadLine::Gnu;

use FindBin;
use lib $FindBin::Bin;

use Project;
use Mixer;
use Song;
use Bridge;

use Data::Dumper;

###########################################################
#
#		 INIT LIVE
#
###########################################################

#autoflush
$| = 1;
use vars qw($project);
#----------------------------------------------------------------
# This is the main entry point for Astrux Live
#----------------------------------------------------------------

if ($#ARGV+1 eq 0) {
	die "usage : start_project project_name.cfg\n";
}

#------------LOAD project structure----------------------------

my $infile = $ARGV[0];
print "Opening : $infile\n";
use Storable;
our $project = retrieve($infile);
die "Could not load file $infile\n" unless $project;

&Start;
&PlayIt;

###########################################################
#
#		 LIVE INIT functions
#
###########################################################

sub Start {

	#TODO verify if Project is valid

	print "--------- Init Project $project->{globals}{name} ---------\n";

	#verify services and servers
	
	#JACK
	#---------------------------------
	my $pid_jackd = qx(pgrep jackd);
	if (!$pid_jackd) {
		print "Strange ...JACK server is not running ?? Starting it\n";
		my $command = $project->{JACK}{start};
		system ($command) if $command;
		sleep 1;
		$pid_jackd = qx(pgrep jackd);
	}
	else {
		print "JACK server running with PID $pid_jackd";
	}
	#TODO verify jack parameters
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
	if ($project->{linuxsampler}{enable}) {
		die "LINUXSAMPLER is not running" unless $pid_linuxsampler;
		print "LINUXSAMPLER running with PID $pid_linuxsampler";
	}
	$project->{LINUXSAMPLER}{PID} = $pid_linuxsampler;

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
	}
	$project->{a2jmidid}{PID} = $pid_a2jmidid;
	
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

	#send previous state to ecasound engines
	#--------------------------------------
	&OSC_send("/refresh i 1"); #TODO checkup

	# now we should be back to saved state
	#--------------------------------------
}

###########################################################
#
#		 LIVE MAIN functions
#
###########################################################

sub PlayIt {

	print "\n--------- Project $project->{globals}{name} Running---------\n";
	#Start the global parser accepting many things like:

	#	tcp commands
	&init_tcp_server if $project->{bridge}{TCP}{enable};
	
	#	OSC messages
	&init_osc_server if $project->{bridge}{OSC}{enable};

##### BRIDGE
	#---------------------------------
	if ( $project->{bridge}{enable} ) {
		$project->{bridge}->create_midi_out_port(); #TODO only needed to control ecasound via midi
	}

	#	command line interface
	&init_cli_server if $project->{bridge}{CLI}{enable};	
	#	gui actions (from tcp commands is best)
	#	front panel actions (from tcp commands)

	#main loop waiting
	my $cv = AE::cv;
	$cv->recv;
	# old static CLI
	# while (1) {
	# 	print "$project->{globals}{name}> ";
	# 	my $command = <STDIN>;
	# 	chomp $command;
	# 	return if ($command =~ /exit|x|quit/);
	# 	$project->execute_command($command);
	# }
}

###########################################################
#
#		 LIVE BRIDGE functions
#
###########################################################

#-------------------------CLI---------------------------------------------
sub init_cli_server {
	my $rl; $rl = new AnyEvent::ReadLine::Gnu prompt => "$project->{globals}{name}>  ", on_line => sub {
		# called for each line entered by the user
		# AnyEvent::ReadLine::Gnu->print ("you entered: $_[0]\n");
		undef $rl unless process_cli($_[0]);
 }
}
sub process_cli {
	my $command = shift;
	die "User asked to exit\n" if ($command =~ /exit|x|quit/);
	print $project->execute_command($command);
	return 1;
}

#-------------------------TCP---------------------------------------------
sub init_tcp_server {
	my $tcpport = $project->{bridge}{TCP}{port};
	# creating a listening socket
	my $tcpsocket = new IO::Socket::INET (
	    LocalHost => '0.0.0.0',
	    LocalPort => $tcpport,
	    Proto => 'tcp',
	    Listen => 5,
	    Reuse => 1
	);
	warn "cannot create socket $!\n" unless $tcpsocket;
	print "Starting TCP listener on port $tcpport\n";
	$project->{bridge}{TCP}{socket} = $tcpsocket;
 	$project->{bridge}{TCP}{events} = AE::io( $tcpsocket, 0, \&process_tcp_command );
}
sub process_tcp_command {

	#TODO for persistent connection we should fork the connection and put it in a loop until clients asks to exit
	# but then we need to synchronise the project structure whith childs...

    my $socket = $project->{bridge}{TCP}{socket};
    # waiting for a new client connection
    my $client_socket = $socket->accept();
 
    # get information about a newly connected client
    my $client_address = $client_socket->peerhost();
    my $client_port = $client_socket->peerport();
    #print "connection from $client_address:$client_port\n";
 
    # read up to 256 characters from the connected client
    my $data = "";
    $client_socket->recv($data, 256);
    print "received data: $data\n";

    chomp($data);
	my $reply = $project->execute_command($data);

    # write response data to the connected client
    $data .= " : $reply\n" if $reply;
    $client_socket->send($data);
   
    # notify client that response has been sent
    shutdown($client_socket, 1);
}
#$socket->close();

#-------------------------OSC---------------------------------------------
sub init_osc_server {
	
	my $oscip = $project->{bridge}{OSC}{ip} || 'localhost';
	my $oscport = $project->{bridge}{OSC}{inport} || '8000';
	print ("Starting OSC listener on port $oscport\n");
	#init socket on osc port
	my $osc_in = $project->{bridge}{OSC}{socket} = IO::Socket::INET->new(
		LocalAddr => $oscip, #default is localhost
		LocalPort => $oscport,
		Proto	  => 'udp',
		Type	  =>  SOCK_DGRAM) || die $!;
	warn "cannot create socket $!\n" unless $osc_in;
	#create the anyevent watcher on this socket
	$project->{bridge}{OSC}{events} = AE::io( $osc_in, 0, \&process_osc_command );
	#init an osc object
	$project->{bridge}{OSC}{object} = Protocol::OSC->new;
}
sub process_osc_command {
use Socket qw(getnameinfo NI_NUMERICHOST);
my $debug = 1;

	my $in = $project->{bridge}{OSC}{socket};
	my $osc = $project->{bridge}{OSC}{object};
	
	#grab the message, and get the sender
	my $sender = $in->recv(my $packet, $in->sockopt(SO_RCVBUF));
	#parse the osc packet
	my $p = $osc->parse($packet);

	#TODO deal with osc bundles
	#grab osc packet arguments
	my ($path, $types, @args) = @$p;

	print "OSC MESSAGE\n------------\npath=$path types=$types and args" if $debug;
	print Dumper @args if $debug;
	print "\n" if $debug;

	#verify how many arguments we have
	if ( length($types) == 0 ) {
		warn "ignored osc message without arguments\n";
		return;
	}
	elsif ( length($types) > 1 ) {
		warn "ignored osc message with multiple arguments\n";
	}

	# TODO check if midi is to be sent (ecasound midi control)
	# if () {
	# 	#send associated midi data
	# 	$project->{bridge}->send_osc2midi($path,$args[0]);
	# }

	#go on with a single argument osc message
	#cleanup path
	$path =~ s(^/)();
	$path =~ s(/$)(); #this one should never be
	#split path elements
	my @pathelements = split '/',$path;
	#TODO verify number of path elements ?
	#element 1 = mixername OR system command
	my $mixername = shift @pathelements;
	if ($mixername eq "astrux") {
		my $command = '';
		$command .= (shift @pathelements)." " while @pathelements;
		print "will send command $command\n" if $debug;
		print $project->execute_command($command);
		return;
	}

	#TCP send to ecasound
	#element 1 = mixername
	print " mixer $mixername\n" if $debug;
	#element 2 = trackname
	my $trackname = shift @pathelements;
	print " track $trackname\n" if $debug;
	
	if ((exists $project->{mixers}{$mixername}) and (exists $project->{mixers}{$mixername}{channels}{$trackname})) {
		#element 3 = fx name OR 'aux_to' OR special command
		my $el3 = shift @pathelements;
		print " el3 $el3\n" if $debug;
		#dependin on the third element
		if ($el3 eq 'mute') {
			#channel mute
			print "mute track $trackname\n" if $debug;
			#send ecasound command
			$project->{mixers}{$mixername}->mute_channel($trackname);
			#TODO udpate current status in strucutre
		}
		# elsif ($el3 eq 'aux_to') {
		# 	#channel aux send
		# 	print "track $trackname aux_to\n" if $debug;
		# 	#element 4 = channel destination
		# 	my $destination = shift @pathelements;
		# 	return unless exists $project->{mixers}{$mixername}{channels}{$trackname}{aux_route}{$destination};
		# 	#element 5 = parameter (pan or volume)
		# 	my $param = shift @pathelements;
		# 	return unless my $index = $project->{mixers}{$mixername}{channels}{$trackname}{aux_route}{$destination}{inserts}{panvol}->is_param_ok($param);
		# 	#associate with value
		# 	my $value = shift @args;
		# 	warn "empty value on param $param!\n" unless defined $value;
		# 	print "sending $trackname to $destination with $param $value\n" if $debug;
		# 	#TODO send ecasound command to EcaStrip
		# 	#my $position = $project->{mixers}{$mixername}{channels}{$trackname}{aux_route}{$destination}{inserts}{panvol}{nb}; 
		# 	#TODO nb contains 99 for panvol and this is not compatible with ecasound index !!
		# 	my $position = 1; # this is ok for aux_route
		# 	$project->{mixers}{$mixername}->udpate_auxroutefx_value($trackname,$destination,$position,$index,$value);
		# 	#udpate current status in strucutre
		# 	$project->{mixers}{$mixername}{channels}{$trackname}{aux_route}{$destination}{inserts}{panvol}->update_current_value($index,$value);
		# }
		# elsif (exists $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$el3} ) {
		# 	#fx change
		# 	my $insertname = $el3;
		# 	#element 4 = fx parameter
		# 	my $insertparam = shift @pathelements;
		# 	return unless my $index = $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$insertname}->is_param_ok($insertparam);
		# 	#associate with value
		# 	my $value = shift @args;
		# 	warn "empty value on param $insertparam!\n" unless defined $value;
		# 	print "effect $insertname change param $insertparam with value $value on track $trackname\n" if $debug;
		# 	#send ecasound command to EcaFx
		# 	my $position = $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$insertname}{nb};
		# 	$project->{mixers}{$mixername}->udpate_trackfx_value($trackname,$position,$index,$value);
		# 	#udpate current status in strucutre
		# 	$project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$insertname}->update_current_value($index,$value);
		# }
		else {
			warn "unknown osc parameter $el3\n";
		}
	}

	#check if we send back information
	if ($project->{bridge}{OSC}{sendback}) {
		#resolve the sender adress
		my($err, $hostname, $servicename) = getnameinfo($sender, NI_NUMERICHOST);
		print "we need to send back info to $hostname\n";
		#TODO send back OSC info
	}
}

#osc send tool
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