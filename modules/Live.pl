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

use lib '/home/seijitsu/astrux/modules';
use Project;
use Mixer;
use Song;
use Bridge;

use Data::Dumper;

#-------------------------------------INIT LIVE -----------------------------------
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

#------------Now PLay !------------------------
&PlayIt;

#------------------------------------------------------------------------

sub Start {

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
		sleep 1;
		$pid_jackd = qx(pgrep jackd);
	}
	else {
		print "JACK server running with PID $pid_jackd";
	}
	#TODO verify jack parameters
	$project->{backends}{JACK}{PID} = $pid_jackd;

	#JPMIDI << problem in server mode can't load new midi file....
	# my $pid_jpmidi = qx(pgrep jpmidi);
	# if ($project->{midi_player}{enable}) {
	# 	die "JPMIDI server is not running" unless $pid_jpmidi;
	# 	print "JPMIDI server running with PID $pid_jpmidi";
	# }
	# $project->{backends}{JPMIDI} = $pid_jpmidi;

	#SAMPLER
	my $pid_linuxsampler = qx(pgrep linuxsampler);
	if ($project->{linuxsampler}{enable}) {
		die "LINUXSAMPLER is not running" unless $pid_linuxsampler;
		print "LINUXSAMPLER running with PID $pid_linuxsampler";
	}
	$project->{backends}{LINUXSAMPLER}{PID} = $pid_linuxsampler;

	#jack.plumbing
	my $pid_jackplumbing = qx(pgrep jack.plumbing);
	if ($project->{connections}{"jack.plumbing"} eq 1) {
		die "jack.plumbing is not running" unless $pid_jackplumbing;
		print "jack.plumbing running with PID $pid_jackplumbing";
	}
	$project->{backends}{JACKPLUMBING}{PID} = $pid_jackplumbing;

	#a2jmidid
	my $pid_a2jmidid = qx(pgrep -f a2jmidid);
	die "alsa to jack midi bridge is not running" unless $pid_a2jmidid;
	print "a2jmidid running with PID $pid_a2jmidid";
	$project->{backends}{A2JMIDID}{PID} = $pid_a2jmidid;
	
	#OSC/MIDI BRIDGE
	#----------------
	if ($project->{osc2midi}{enable} eq 1) {
		$project->{osc2midi}->create_midi_out_port();
	}

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
		print "Loading song $song\n"; 
		print $project->{mixers}{players}{ecasound}->LoadFromFile($project->{songs}{$song}{ecasound}{ecsfile});
	}
	#load dummy song chainsetup
	$project->{mixers}{players}{ecasound}->SelectAndConnectChainsetup("players");

	#send previous state to ecasound engines
	#--------------------------------------
	&OSC_send("/refresh i 1");

	# now we should be back to saved state
	#--------------------------------------
}

#-------------------------MAIN LOOP---------------------------------------------

sub PlayIt {

	print "\n--------- Project $project->{project}{name} Running---------\n";
	#Start the global parser accepting many things like:
	#	tcp commands
	&init_tcp_server if $project->{TCP}{enable};
	#	OSC messages
	&init_osc_server if $project->{OSC}{enable};
	#	command line interface
	&init_cli_server if $project->{CLI}{enable};	
	#	gui actions (from tcp commands is best)
	#	front panel actions (from tcp commands)

	#main loop waiting
	my $cv = AE::cv;
	$cv->recv;
	# old static CLI
	# while (1) {
	# 	print "$project->{project}{name}> ";
	# 	my $command = <STDIN>;
	# 	chomp $command;
	# 	return if ($command =~ /exit|x|quit/);
	# 	$project->execute_command($command);
	# }
}
#-------------------------CLI---------------------------------------------
sub init_cli_server {
	my $rl; $rl = new AnyEvent::ReadLine::Gnu prompt => "$project->{project}{name}>  ", on_line => sub {
		# called for each line entered by the user
		# AnyEvent::ReadLine::Gnu->print ("you entered: $_[0]\n");
		undef $rl unless process_cli($_[0]);
 }
}
sub process_cli {
	my $command = shift;
	return if ($command =~ /exit|x|quit/);
	print $project->execute_command($command);
	return 1;
}

#-------------------------TCP---------------------------------------------
sub init_tcp_server {
	my $tcpport = $project->{TCP}{port};
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
	$project->{TCP}{socket} = $tcpsocket;
 	$project->{TCP}{events} = AE::io( $tcpsocket, 0, \&process_tcp_command );
}
sub process_tcp_command {

	#TODO for persistent connection we should fork the connection and put it in a loop until clients asks to exit

    my $socket = $project->{TCP}{socket};
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
	
	my $oscip = $project->{OSC}{ip} || 'localhost';
	my $oscport = $project->{OSC}{inport} || '8000';
	print ("Starting OSC listener on port $oscport\n");
	#init socket on osc port
	my $osc_in = $project->{OSC}{socket} = IO::Socket::INET->new(
		LocalAddr => $oscip, #default is localhost
		LocalPort => $oscport,
		Proto	  => 'udp',
		Type	  =>  SOCK_DGRAM) || die $!;
	warn "cannot create socket $!\n" unless $osc_in;
	#create the anyevent watcher on this socket
	$project->{OSC}{events} = AE::io( $osc_in, 0, \&process_osc_command );
	#init an osc object
	$project->{OSC}{object} = Protocol::OSC->new;
}
sub process_osc_command {
use Socket qw(getnameinfo NI_NUMERICHOST);
my $debug = 0;

	my $in = $project->{OSC}{socket};
	my $osc = $project->{OSC}{object};
	
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
	#element 1 = mixername
	print " mixer $mixername\n" if $debug;
	return unless exists $project->{mixers}{$mixername};
	#element 2 = trackname
	my $trackname = shift @pathelements;
	print " track $trackname\n" if $debug;
	return unless exists $project->{mixers}{$mixername}{channels}{$trackname};
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
	elsif ($el3 eq 'aux_to') {
		#channel aux send
		print "track $trackname aux_to\n" if $debug;
		#element 4 = channel destination
		my $destination = shift @pathelements;
		return unless exists $project->{mixers}{$mixername}{channels}{$trackname}{aux_route}{$destination};
		#element 5 = parameter (pan or volume)
		my $param = shift @pathelements;
		return unless my $index = $project->{mixers}{$mixername}{channels}{$trackname}{aux_route}{$destination}{inserts}{panvol}->is_param_ok($param);
		#associate with value
		my $value = shift @args;
		warn "empty value on param $param!\n" unless defined $value;
		print "sending $trackname to $destination with $param $value\n" if $debug;
		#TODO send ecasound command to EcaStrip
		#my $position = $project->{mixers}{$mixername}{channels}{$trackname}{aux_route}{$destination}{inserts}{panvol}{nb}; 
		#TODO nb contains 99 for panvol and this is not compatible with ecasound index !!
		my $position = 1; # this is ok for aux_route
		$project->{mixers}{$mixername}->udpate_auxroutefx_value($trackname,$destination,$position,$index,$value);
		#udpate current status in strucutre
		$project->{mixers}{$mixername}{channels}{$trackname}{aux_route}{$destination}{inserts}{panvol}->update_current_value($index,$value);
	}
	elsif (exists $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$el3} ) {
		#fx change
		my $insertname = $el3;
		#element 4 = fx parameter
		my $insertparam = shift @pathelements;
		return unless my $index = $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$insertname}->is_param_ok($insertparam);
		#associate with value
		my $value = shift @args;
		warn "empty value on param $insertparam!\n" unless defined $value;
		print "effect $insertname change param $insertparam with value $value on track $trackname\n" if $debug;
		#send ecasound command to EcaFx
		my $position = $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$insertname}{nb};
		$project->{mixers}{$mixername}->udpate_trackfx_value($trackname,$position,$index,$value);
		#udpate current status in strucutre
		$project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$insertname}->update_current_value($index,$value);
	}
	else {
		warn "unknown osc parameter $el3\n";
	}

	#TODO check if we send back information
	if ($project->{OSC}{sendback}) {
		#resolve the sender adress
		my($err, $hostname, $servicename) = getnameinfo($sender, NI_NUMERICHOST);
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