#!/usr/bin/perl

package Bridge;

use strict;
use warnings;

#http://search.cpan.org/~pjb/MIDI-ALSA-1.18/ALSA.pm
use MIDI::ALSA;
use POSIX qw(ceil floor); #for floor/ceil function
use Utils;

use Protocol::OSC;
use IO::Socket::INET;

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::ReadLine::Gnu;

my $debug = 0;

use Load;
our $project;

###########################################################
#
#		 BRIDGE OBJECT functions
#
###########################################################
sub new {
	my $class = shift;
	my $bridgefile = shift;
	die "Bridge Error: can't create bridge without an ini file\n" unless $bridgefile;

	#init structure
	my $bridge = {
		"ini_file" => $bridgefile
	};
	
	bless $bridge,$class;
	
	#fill from ini file 
	$bridge->init($bridgefile);

	return $bridge; 
}

sub init {
	my $bridge = shift;
	my $ini_file = shift;

	use Config::IniFiles;
	#ouverture du fichier ini de configuration des channels
	tie my %bridgeinfo, 'Config::IniFiles', ( -file => $ini_file );
	die "Bridge Error: reading I/O ini file failed\n" unless %bridgeinfo;
	
	#update project structure with bridge infos
	$bridge->{$_} = $bridgeinfo{$_} foreach (keys %bridgeinfo);
}

sub start {
	my $bridge = shift;

	#Start the global parser accepting many things like:

	#	tcp commands
	$bridge->init_tcp_server if $bridge->{TCP}{enable};
	
	#	OSC messages
	$bridge->init_osc_server if $bridge->{OSC}{enable};

	#   MIDI messages
	$bridge->create_midi_ports if $bridge->{MIDI}{enable};

	#	command line interface
	&init_cli_server if $bridge->{CLI}{enable};	

	#	gui actions (from tcp commands)

	#	front panel actions (from tcp commands)

	#main loop waiting
	#--------------------------------------
	my $cv = AE::cv;
	$cv->recv;
}

sub create_midiosc_paths {
	my $project = shift;
	my $bridge = $project->{bridge};
	
	# --- LOOP THROUGH MIXERs ---
	
	foreach my $mixername (keys %{$project->{mixers}}) {

		#variables to hold the bridge midi input info
		my ($midiCC,$midichannel);

		#create mixer reference
		my $mixer = $project->{mixers}{$mixername}{channels};
		
		# --- FIRST GET NONMIXER AUXES ---
		my @auxes = $project->{mixers}{$mixername}->get_auxes_list;

		# --- LOOP THROUGH CHANNELS ---
	
		foreach my $channelname (keys %{$mixer}) {
			
			#create channel reference
			my $channelstrip = $mixer->{$channelname};
			
			#add generic channelstrip options
			$bridge->add_midioscpaths("/$mixername/$channelname/mute","toggle",0);
			$bridge->add_midioscpaths("/$mixername/$channelname/solo","toggle",0) unless $channelstrip->is_hardware_out;
			$bridge->add_midioscpaths("/$mixername/$channelname/bypass","toggle",0);
			
			# --- LOOP THROUGH INSERTS ---
	
			foreach my $insertname (keys %{$channelstrip->{inserts}}) {

				#create insert reference
				my $insert = $channelstrip->{inserts}{$insertname};

				# --- LOOP THROUGH INSERT PARAMETERS ---

				my $i = 0;
				foreach my $paramname (@{$insert->{paramnames}}) {
					warn "Insert ($paramname) has a system name... may not work\n" if ($paramname =~ /^(mute|solo|bypass)$/);	
					#replace space characters with _ #TODO check how ecasound treats LADSPA plugins names with nonalpha characters
					$paramname = Utils::underscore_my_spaces($paramname);

					$bridge->add_midioscpaths("/$mixername/$channelname/$insertname/$paramname","linear",$insert->{defaultvalues}[$i])
						if $project->{mixers}{$mixername}->is_ecasound;
					$bridge->add_midioscpaths("/$mixername/$channelname/$insert->{fxname}/$insert->{paramnames}[$i]","linear",$insert->{defaultvalues}[$i])
						if $project->{mixers}{$mixername}->is_nonmixer;
				
					$i++;
				}
			}
			
			# --- LOOP THROUGH AUX ROUTES (ecasound only) ---
			
			foreach my $auxroute (keys %{$channelstrip->{aux_route}}) {

				#create route reference
				my $route = $channelstrip->{aux_route}{$auxroute}{inserts}{panvol};

				# --- LOOP THROUGH route PARAMETERS ---

				my $i = 0;
				foreach my $paramname (@{$route->{paramnames}}) {
					my $value = $route->{defaultvalues}[$i];
					$bridge->add_midioscpaths("/$mixername/$channelname/aux_to/$auxroute/$paramname","linear",$route->{defaultvalues}[$i]);
					$i++;
				}
			}

			# --- NON-MIXER SPECIFICS ---

			if ($project->{mixers}{$mixername}->is_nonmixer) {
				# Add gain control
				$bridge->add_midioscpaths("/$mixername/$channelname/panvol/vol","linear",0);
				# Add pan control
				$bridge->add_midioscpaths("/$mixername/$channelname/panvol/pan","linear",0);
				#add aux routes
				foreach my $aux (@auxes) {
					$bridge->add_midioscpaths("/$mixername/$channelname/aux_to/$aux/vol","linear",0) unless $channelstrip->is_hardware_out;
				}
			}
		}
	}
}

sub add_midioscpaths {
	my $bridge = shift;
	my $oscpath = shift;
	my $type = shift;
	my $val = shift;

	#get a new midi CC/channel
	my ($midiCC,$midichannel) = &getnextCC();

	#insert into project
	$bridge->{OSC}{paths}{$oscpath} = $type;
	$bridge->{MIDI}{paths}{"$midichannel,$midiCC"} = $oscpath;
	$bridge->{current_values}{$oscpath} = $val;
}

###########################################################
#
#		 BRIDGE FILE functions
#
###########################################################

sub save_osc_file {
	my $bridge = shift;

	my $filepath = $bridge->{OSC}{file};
	open FILE, ">$filepath" or die $!;
	
	#add lines
	foreach my $oscpath (sort keys %{$bridge->{OSC}{paths}}) {
		print FILE "$oscpath;$bridge->{OSC}{paths}{$oscpath}\n";
	}
	close FILE;
}

sub save_midi_file {
	my $bridge = shift;

	my $filepath = $bridge->{MIDI}{file};
	open FILE, ">$filepath" or die $!;
	
	#add lines
	foreach my $midipath (sort keys %{$bridge->{MIDI}{paths}}) {
		print FILE "$midipath;$bridge->{MIDI}{paths}{$midipath}\n";
	}
	close FILE;
}

###########################################################
#
#		 BRIDGE MIDI functions
#
###########################################################

#create alsa midi port with only 1 output
my @alsa_output = ("astrux",0);

sub create_midi_ports {
	my $bridge = shift;

	#update bridge structure
	$bridge->{MIDI}{alsa_output} = @alsa_output;
	my $clientname = $bridge->{MIDI}{clientname} || "astrux";
	my $ninputports = $bridge->{MIDI}{inputports} || 1;
	my $noutputports = $bridge->{MIDI}{outputports} || 1;

	#client($name, $ninputports, $noutputports, $createqueue)
	my $status = MIDI::ALSA::client($clientname,$ninputports,$noutputports,0) || die "could not create alsa midi port.\n";
	print "successfully created \"$clientname\" alsa midi client\n";
	$bridge->{MIDI}{status} = 'created';
}

sub getnextCC {
	use feature 'state';
	state $channel = 1;
	state $CC = 0;
	#verify end of midi CC range
	die "Bridge error: CC max range error!!\n" if (($CC eq 127) and ($channel eq 16));
	#CC range from 1 to 127, update channel if needed
	if ($CC == 127) {
		$CC = 0;
		$channel++;
	}
	#increment CC number
	$CC++;
	#return values
	return($CC,$channel);
}

sub ScaleToMidiValue {
	my $inval = shift;
	my $min = shift;
	my $max = shift;
	#verify if data is within min max range
	$inval = $min if $inval < $min;
	$inval = $max if $inval > $max;
	#scale value
	my $out = floor((127*($inval-$min))/($max-$min));
	#verify if outdata is within MIDI min max range
	$out = 0 if $out < 0;
	$out = 127 if $out > 127;
	#return scaled value
	return $out;
}

sub SendMidiCC {
	my $outCC = shift;
	return MIDI::ALSA::output(MIDI::ALSA::SND_SEQ_EVENT_CONTROLLER,'','',MIDI::ALSA::SND_SEQ_QUEUE_DIRECT,0.0,\@alsa_output,0,$outCC);
}

###########################################################
#
#		 BRIDGE OSC functions
#
###########################################################

sub init_osc_server {
	my $bridge = shift;

	my $oscip = $bridge->{OSC}{ip} || 'localhost';
	my $oscport = $bridge->{OSC}{inport} || '8000';
	print ("Starting OSC listener on port $oscport\n");
	#init socket on osc port
	my $osc_in = $bridge->{OSC}{socket} = IO::Socket::INET->new(
		LocalAddr => $oscip, #default is localhost
		LocalPort => $oscport,
		Proto	  => 'udp',
		Type	  =>  SOCK_DGRAM) || die $!;
	warn "cannot create socket $!\n" unless $osc_in;
	#create the anyevent watcher on this socket
	$bridge->{OSC}{events} = AE::io( $osc_in, 0, \&process_osc_command );
	#init an osc object
	$bridge->{OSC}{object} = Protocol::OSC->new;
}

sub process_osc_command {
	use Socket qw(getnameinfo NI_NUMERICHOST);
	my $debug = 1;

	# verify socket
	#-----------------------------------------
	my $insocket = $project->{bridge}{OSC}{socket};
	die "Live process_osc error: could not read OSC socket in project\n" unless $insocket;
	my $osc = $project->{bridge}{OSC}{object};
	die "Live process_osc error: could not read OSC object in project\n" unless $insocket;
	
	#grab the message, and get the sender
	#-----------------------------------------
	my $sender = $insocket->recv(my $packet, $insocket->sockopt(SO_RCVBUF));
	#parse the osc packet
	my $p = $osc->parse($packet);

	#TODO deal with osc bundles
	#grab osc packet arguments
	#-----------------------------------------
	my ($path, $types, @args) = @$p;

	print "OSC MESSAGE\n------------\npath=$path types=$types and args " if $debug;
	if ($debug){print "$_," for @args};
	print "\n" if $debug;

	#verify how many arguments we have
	#-----------------------------------------
	if ( length($types) == 0 ) {
		warn "Bridge warning: ignored osc message without arguments\n";
		return;
	}
	elsif ( length($types) > 1 ) {
		warn "Bridge warning: ignored osc message with multiple arguments\n";
		return;
	}

	#go on with a single argument osc message
	#-----------------------------------------

	#cleanup path
	$path =~ s(^/)();
	$path =~ s(/$)(); #this one should never be
	
	#split path elements
	my @pathelements = split '/',$path;
	
	#element 1 = mixername OR system command
	my $mixername = shift @pathelements;
	if ($mixername eq "astrux") {
		my $command = '';
		$command .= (shift @pathelements)." " while @pathelements;
		print "will send command $command\n" if $debug;
		print $project->execute_command($command);
		return;
	}

	#verify that incoming value is within (0,1) range
	#------------------------------------------------
	my $value = shift @args;
	if (!defined $value) {
		warn "Bridge warning: ignored message without value\n";
		return;
	}
	elsif ($value < 0) {
		warn "Bridge warning: OSC values must be within [0,1]\n";
		$value = 0;
	}
	elsif ($value > 1) {
		warn "Bridge warning: OSC values must be within [0,1]\n";
		$value = 1;
	}

	#resolve the sender adress
	my($err, $sender_hostname, $servicename) = getnameinfo($sender, NI_NUMERICHOST);
	if ($err) {
		warn "Cannot resolve name - $err";
	}
	else {
		$project->{bridge}{OSC}{clients}{$sender_hostname} = 1;
	}

	#element 1 = mixername
	print " mixer $mixername\n" if $debug;
	#element 2 = trackname
	my $trackname = shift @pathelements;
	print " track $trackname\n" if $debug;
	
	if ((exists $project->{mixers}{$mixername}) and (exists $project->{mixers}{$mixername}{channels}{$trackname})) {
		
		#element 3 = fx name OR 'aux_to' OR special command
		my $el3 = shift @pathelements;
		print " el3 $el3\n" if $debug;

		# if mixer is NONMIXER
		#-----------------------------------------
		#osc message must be translated and passed to nonmixer osc port
		if ($project->{mixers}{$mixername}->is_nonmixer) {
			#get osc port
			my $nonoscport = $project->{mixers}{$mixername}{engine}{osc_port};

			if ($el3 eq 'mute') {
				return unless (($value eq 0)or($value eq 1));
				&OSC_send("/strip/$trackname/Gain/Mute f $value","localhost",$nonoscport);
			}
			elsif ($el3 eq 'solo') {
				#TODO nonmixer osc solo command
			}
			elsif ($el3 eq 'bypass') {
				#TODO nonmixer osc bypass command
			}
			elsif ($el3 eq 'panvol') {
				# element 4 = fx parameter
				my $el4 = shift @pathelements;
				#associate with value
				print "effect $el3 change param $el4 with value $value on track $trackname\n" if $debug;
				&OSC_send("/strip/$trackname/Gain/Gain%20(dB) f $value","localhost",$nonoscport) if ($el4 eq 'vol');
				if ($el4 eq 'pan') {
					&OSC_send("/strip/$trackname/Mono%20Pan/Pan f $value","localhost",$nonoscport) if $project->{mixers}{$mixername}{channels}{$trackname}->is_mono;
					&OSC_send("/strip/$trackname/Stereo%20balance%20and%20panner/Balance f $value","localhost",$nonoscport) if $project->{mixers}{$mixername}{channels}{$trackname}->is_stereo;
				}
				#udpate current value
				$project->{bridge}{current_values}{$path} = $value;
			}
			elsif (exists $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$el3} ) {
				#fx change (LADSPA ID)
				my $insertID = $el3;
				#element 4 = fx parameter
				my $insertparam = shift @pathelements;
				return unless $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$insertID}->is_param_ok($insertparam);
				#associate with value
				#get insertname
				my $insertname = $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$insertID}{name};
				print "effect $insertID/$insertname change param $insertparam with value $value on track $trackname\n" if $debug;
				#replace non aplhanum characters with %ascii code
				$insertname = Utils::encode_my_ascii($insertname);
				$insertparam = Utils::encode_my_ascii($insertparam);
				#send osc command to nonmixer
				&OSC_send("/strip/$trackname/$insertname/$insertparam f $value","localhost",$nonoscport);
			}
			elsif ($el3 eq 'aux_to') {
				# element 4 = auxname
				my $auxname = shift @pathelements;
				return unless exists $project->{mixers}{$mixername}{channels}{$auxname};
				my $letter = $project->{mixers}{$mixername}{channels}{$auxname}{aux_letter};
				return unless $letter;
				# element 5 = command
				my $command = shift @pathelements;
				return unless $command eq 'vol'; #TODO for now only volume command on track aux send to monitor
				#send osc command to nonmixer
				&OSC_send("/strip/$trackname/Aux%20\($letter\)/Gain%20\(dB\) f $value","localhost",$nonoscport);
			}
		}

		# if mixer is ECASOUND
		#-----------------------------------------
		if ($project->{mixers}{$mixername}->is_ecasound) {
			#dependin on the third element
			if ($el3 eq 'mute') {
				#channel mute
				print "mute track $trackname\n" if $debug;
				#send ecasound command
				$project->{mixers}{$mixername}->mute_channel($trackname);
				#udpate current status in structure
				$project->{bridge}{current_values}{$path} = $value;
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
				warn "empty value on param $param!\n" unless defined $value;
				print "sending $trackname to $destination with $param $value\n" if $debug;
				my $position = 1; # this is ok for aux_route
				$project->{mixers}{$mixername}->udpate_auxroutefx_value($trackname,$destination,$position,$index,$value);
				#udpate current value
				$project->{bridge}{current_values}{$path} = $value;
			}
			elsif (exists $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$el3} ) {
				#fx change
				my $insertname = $el3;
				#element 4 = fx parameter
				my $insertparam = shift @pathelements;
				return unless my $index = $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$insertname}->is_param_ok($insertparam);
				#associate with value
				warn "empty value on param $insertparam!\n" unless defined $value;
				print "effect $insertname change param $insertparam with value $value on track $trackname\n" if $debug;
				#send ecasound command to EcaFx
				my $position = $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$insertname}{nb};
				$project->{mixers}{$mixername}->udpate_trackfx_value($trackname,$position,$index,$value);
				#udpate current value
				$project->{bridge}{current_values}{$path} = $value;
			}
			else {
				warn "unknown osc parameter $el3\n";
			}
		} #endif ecasound
	} #endif mixer and channel is ok
	else 
	{
		print "could not find corresponding info from $path"
	}

	#check if we send back information
	if ($project->{bridge}{OSC}{sendback}) {
		print "we send back osc message \"/$path f $value\" to $sender_hostname\n" if $debug;
		#send back OSC info
		&OSC_send("/$path f $value",$sender_hostname,$project->{bridge}{OSC}{outport});
	}
}

sub OSC_send {
	my $data = shift;
	my $destination = shift;
	my $port = shift;
	return unless $port;

	my $osc = Protocol::OSC->new;
	#make packet
	# my $oscpacket = $osc->message(my @specs = qw(/refresh i 1));
    # or
    #use Time::HiRes 'time';
    #my $oscpacket $osc->bundle(time, [@specs], [@specs2], ...);
	my @specs = split(' ',$data);
	my $oscpacket = $osc->message(@specs);
	# print "oscpacket to send= 0=$specs[0] , 1=$specs[1] , 2=$specs[2]\n";	

	#send
	my $udp = IO::Socket::INET->new( PeerAddr => "$destination", PeerPort => "$port", Proto => 'udp', Type => SOCK_DGRAM) || die $!;
	$udp->send($oscpacket);	
}

###########################################################
#
#		 BRIDGE TCP functions
#
###########################################################

sub init_tcp_server {
	my $bridge = shift;

	my $tcpport = $bridge->{TCP}{port};
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
	$bridge->{TCP}{socket} = $tcpsocket;
 	$bridge->{TCP}{events} = AE::io( $tcpsocket, 0, \&process_tcp_command );
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

###########################################################
#
#		 BRIDGE CLI functions
#
###########################################################

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


1;