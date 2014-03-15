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

	#	meters
	&init_meters if $project->{meters}{options}{enable};

	#	gui actions (from tcp commands)

	#	front panel actions (from rs232 port)

	#catch signals
	#--------------------------------------
	$SIG{INT} = \&cmd_exit;

	#reload state
	if (-e $project->{bridge}{statefile}){
		$bridge->reload_state_file($project->{bridge}{statefile});
	}
	else {
		$bridge->reload_current_state;
	}
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

		#create mixer references
		my $mixer = $project->{mixers}{$mixername};
		my $engine = $mixer->{engine}{engine};
		my $protocol = $mixer->{engine}{control};
		my $port;
		$port = $mixer->get_tcp_port if $mixer->is_tcp_controllable;
		$port = $mixer->get_osc_port if $mixer->is_osc_controllable;
		$port = $mixer->get_midi_port if $mixer->is_midi_controllable;
		
		# --- FIRST GET NONMIXER AUXES ---
		my @auxes = $mixer->get_auxes_list;

		# --- LOOP THROUGH CHANNELS ---
	
		foreach my $channelname (keys %{$mixer->{channels}}) {
			
			#create channel reference
			my $channelstrip = $mixer->{channels}{$channelname};
			
			#add generic channelstrip options
			$bridge->insert_midioscpaths("/$mixername/$channelname/mute","toggle",0,$engine,$protocol,$port);
			$bridge->insert_midioscpaths("/$mixername/$channelname/solo","toggle",0,$engine,$protocol,$port) unless $channelstrip->is_hardware_out;
			$bridge->insert_midioscpaths("/$mixername/$channelname/fxbypass","toggle",0,$engine,$protocol,$port);
			
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
					#scale value to [0,1] range
					my $outvalue = ( $insert->{defaultvalues}[$i]-$insert->{lowvalues}[$i] ) / ( $insert->{highvalues}[$i] - $insert->{lowvalues}[$i] );
					#add to paths
					$bridge->insert_midioscpaths("/$mixername/$channelname/$insertname/$paramname","linear",$outvalue,$engine,$protocol,$port)
						if $mixer->is_ecasound;
					$bridge->insert_midioscpaths("/$mixername/$channelname/$insert->{fxname}/$insert->{paramnames}[$i]","linear",$outvalue,$engine,$protocol,$port)
						if $mixer->is_nonmixer;
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
					#scale value to [0,1] range
					my $outvalue = ( $route->{defaultvalues}[$i]-$route->{lowvalues}[$i] ) / ( $route->{highvalues}[$i] - $route->{lowvalues}[$i] );
					#add to paths
					$bridge->insert_midioscpaths("/$mixername/$channelname/aux_to/$auxroute/$paramname","linear",$outvalue,$engine,$protocol,$port);
					$i++;
				}
			}

			# --- NON-MIXER SPECIFICS ---

			if ($project->{mixers}{$mixername}->is_nonmixer) {
				# Add gain control
				$bridge->insert_midioscpaths("/$mixername/$channelname/panvol/vol","linear",0.921,$engine,$protocol,$port);
				# Add pan control
				$bridge->insert_midioscpaths("/$mixername/$channelname/panvol/pan","linear",0.5,$engine,$protocol,$port);
				#add aux routes
				foreach my $aux (@auxes) {
					$bridge->insert_midioscpaths("/$mixername/$channelname/aux_to/$aux/vol","linear",0.921,$engine,$protocol,$port) unless $channelstrip->is_hardware_out;
				}
			}
		}
	}
}

sub insert_midioscpaths {
	my $bridge = shift;
	my $oscpath = shift;
	my $type = shift;
	my $val = shift;
	my $engine = shift;
	my $protocol = shift;
	my $port = shift;

	#get a new midi CC/channel
	my ($midiCC,$midichannel) = &getnextCC();

	#insert into project
	$bridge->{OSC}{paths}{$oscpath}{type} = $type;
	$bridge->{OSC}{paths}{$oscpath}{target} = $engine;
	$bridge->{OSC}{paths}{$oscpath}{protocol} = $protocol;
	$bridge->{OSC}{paths}{$oscpath}{port} = $port;
	$bridge->{OSC}{paths}{$oscpath}{message} = "";
	$bridge->{MIDI}{paths}{"$midichannel,$midiCC"} = $oscpath;
	$bridge->{current_values}{$oscpath} = $val;
}

sub translate_osc_paths_to_target {
	my $project = shift;
	#TODO make generic commands in EcaEngine and NonEngine for : get_mute_command, get_volume_command ...etc

	foreach my $oscpath (sort keys %{$project->{bridge}{OSC}{paths}}) {
	
		my $engine = $project->{bridge}{OSC}{paths}{$oscpath}{target};
		my $protocol = $project->{bridge}{OSC}{paths}{$oscpath}{protocol};

		#cleanup path
		my $fake_oscpath = $oscpath;
		$fake_oscpath =~ s(^/)();
		
		#split path elements
		my @pathelements = split '/',$fake_oscpath;
	
		#element 1 = mixername OR system command
		my $mixername = shift @pathelements;
		#element 2 = trackname
		my $trackname = shift @pathelements;
		#element 3 = fx name OR 'aux_to' OR special command
		my $el3 = shift @pathelements;
	
		# if mixer is NONMIXER
		#-----------------------------------------
		#osc message must be translated to non-mixer format
		if ($engine eq "non-mixer") {
			
			if ($el3 eq 'mute') {
				$project->{bridge}{OSC}{paths}{$oscpath}{message} = "/strip/$trackname/Gain/Mute";
			}
			elsif ($el3 eq 'solo') {
				#TODO nonmixer osc solo command
				$project->{bridge}{OSC}{paths}{$oscpath}{message} = "/dummy";
			}
			elsif ($el3 eq 'fxbypass') {
				#TODO nonmixer osc fxbypass command
				$project->{bridge}{OSC}{paths}{$oscpath}{message} = "/dummy";
			}
			elsif ($el3 eq 'panvol') {
				# element 4 = fx parameter
				my $el4 = shift @pathelements;
				#associate with value
				$project->{bridge}{OSC}{paths}{$oscpath}{message} = "/strip/$trackname/Gain/Gain%20(dB)" if ($el4 eq 'vol');
				if ($el4 eq 'pan') {
					$project->{bridge}{OSC}{paths}{$oscpath}{message} = "/strip/$trackname/Mono%20Pan/Pan" if $project->{mixers}{$mixername}{channels}{$trackname}->is_mono;
					$project->{bridge}{OSC}{paths}{$oscpath}{message} = "/strip/$trackname/Stereo%20balance%20and%20panner/Balance" if $project->{mixers}{$mixername}{channels}{$trackname}->is_stereo;
				}
			}
			elsif (exists $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$el3} ) {
				#fx change (LADSPA ID)
				my $insertID = $el3;
				#element 4 = fx parameter
				my $insertparam = shift @pathelements;
				next unless $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$insertID}->is_param_ok($insertparam);
				#associate with value
				#get insertname
				my $insertname = $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$insertID}{name};
				#replace non aplhanum characters with %ascii code
				$insertname = Utils::encode_my_ascii($insertname);
				$insertparam = Utils::encode_my_ascii($insertparam);
				$project->{bridge}{OSC}{paths}{$oscpath}{message} = "/strip/$trackname/$insertname/$insertparam";
			}
			elsif ($el3 eq 'aux_to') {
				# element 4 = auxname
				my $auxname = shift @pathelements;
				next unless exists $project->{mixers}{$mixername}{channels}{$auxname};
				my $letter = $project->{mixers}{$mixername}{channels}{$auxname}{aux_letter};
				next unless $letter;
				# element 5 = command
				my $command = shift @pathelements;
				next unless $command eq 'vol'; #TODO for now only volume command on track aux send to monitor
				$project->{bridge}{OSC}{paths}{$oscpath}{message} = "/strip/$trackname/Aux%20\($letter\)/Gain%20\(dB\)";
			}
		}
	
		# if mixer is ECASOUND
		#-----------------------------------------
		if ($engine eq "ecasound") {
			#dependin on the third element
			if ($el3 eq 'mute') {
				#channel mute
				my @messages = ("c-select $trackname","c-muting");
				$project->{bridge}{OSC}{paths}{$oscpath}{message} = \@messages;
			}		
			elsif ($el3 eq 'solo') {
				#TODO ecasound osc solo command
			}
			elsif ($el3 eq 'fxbypass') {
				#TODO ecasound osc fxbypass command
			}
			elsif ($el3 eq 'aux_to') {
				#element 4 = channel destination
				my $destination = shift @pathelements;
				next unless exists $project->{mixers}{$mixername}{channels}{$trackname}{aux_route}{$destination};
				#element 5 = parameter (pan or volume)
				my $param = shift @pathelements;
				next unless my $index = $project->{mixers}{$mixername}{channels}{$trackname}{aux_route}{$destination}{inserts}{panvol}->is_param_ok($param);
				my $position = 1; # this is ok for aux_route
				my @messages = ("c-select $trackname"."_to_"."$destination","cop-set $position,$index,\$realvalue");
				$project->{bridge}{OSC}{paths}{$oscpath}{message} = \@messages;
			}
			elsif (exists $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$el3} ) {
				#fx change
				my $insertname = $el3;
				#element 4 = fx parameter
				my $insertparam = shift @pathelements;
				next unless my $index = $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$insertname}->is_param_ok($insertparam);
				my $position = $project->{mixers}{$mixername}{channels}{$trackname}{inserts}{$insertname}{nb};
				$trackname = "bus_$trackname" if $project->{mixers}{$mixername}{channels}{$trackname}->is_hardware_out;
				my @messages = ("c-select $trackname","cop-select $position","copp-select $index","copp-set \$realvalue");
				$project->{bridge}{OSC}{paths}{$oscpath}{message} = \@messages;
			}
		} #endif ecasound
	} #end foreach $oscpath
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
	print FILE "$_\n" for (sort keys %{$bridge->{OSC}{paths}});
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

sub save_state_file {
	my $bridge = shift;
	my $outfile = shift;
	return unless defined $outfile;
	use Storable;
	$Storable::Deparse = 1; #warn if CODE encountered, but dont die
	store $bridge->{current_values}, $outfile;
}
sub reload_state_file {
	my $bridge = shift;
	my $infile = shift;
	return unless defined $infile;	
	return unless -e $infile;
	print "Loading previous state from file $infile\n";
	use Storable;
	#load state file
	$bridge->{current_values} = retrieve($infile);
	#send values to services/servers
	foreach my $oscpath (keys %{$bridge->{current_values}}){
		&OSC_send($bridge->{OSC}{ip},$bridge->{OSC}{inport},"$oscpath","f","$bridge->{current_values}{$oscpath}");
	}
}
sub reload_current_state {
	my $bridge = shift;
	print "Sending current state\n";
	#send values to services/servers
	foreach my $oscval (keys %{$bridge->{current_values}}){
		&OSC_send($bridge->{OSC}{ip},$bridge->{OSC}{inport},"$oscval","f","$bridge->{current_values}{$oscval}");
	}
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
#		 BRIDGE functions
#
###########################################################

sub parse_cmd {
	my $command = shift;

	use Scalar::Util qw(looks_like_number);

	# split command line in usable parts
	my @pathelements = split ' ', $command;
	my $element1 = shift @pathelements;
	my $element2 = shift @pathelements;
	my @args = @pathelements;

	# check elements
	if ($element1 eq "start") { &cmd_start; return; }
	elsif ($element1 eq "stop") { &cmd_stop; return; }
	elsif ($element1 eq "zero") { &cmd_zero; return; }
	elsif ($element1 eq "locate") {
		my $value = shift @args;
		return unless looks_like_number($value);
		&cmd_locate($value);
		return;
	}
	elsif ($element1 eq "save") {
		return unless $element2;
		&cmd_save($element2);
		return;
	}
	elsif ($element1 eq "status") {
		&cmd_status;
		return;
	}
	elsif ($element1 eq "song") {
		return unless exists $project->{songs}{$element2};
		&cmd_song($project->{songs}{$element2});
		return;
	}
	elsif ($element1 eq "reload") {
		return unless $element2;
		&cmd_reload($element2);
		return;
	}
	elsif ($element1 eq "clic") {
		return unless $element2;
		&cmd_clic("start") if $element2 eq "start";
		&cmd_clic("stop") if $element2 eq "stop";
		return unless @args;
		&cmd_clic("tempo",\@args) if ($element2 eq "tempo") and looks_like_number($args[0]);
		&cmd_clic("inbuilt_sound",\@args) if ($element2 eq "tempo") and looks_like_number($args[0]);
		&cmd_clic("custom_sounds",\@args) if ($element2 eq "tempo") and ($#args == 1); #need two files
		return;
	}
	elsif ($element1 eq "exit") {
		&cmd_exit;
	}
}
sub cmd_song {
	my $song = shift;

	# TODO maybe fisrt save previous song state before starting new song
	print "Starting song $song->{friendly_name}\n";
	
	# stop and Goto 0
	&OSC_send("localhost",$project->{"jack-osc"}{osc_port},"/stop");
	&OSC_send("localhost",$project->{"jack-osc"}{osc_port},"/locate","f","0");
	
	# reconfigure klick
	&OSC_send("localhost",$project->{klick}{osc_port},"/klick/metro/set_type","s","$song->{metronome_type}");
	&OSC_send("localhost",$project->{klick}{osc_port},"/klick/map/load_file","s","$song->{klick_file}") if $song->{metronome_type} eq "map";
	#TODO fix klick simple mode won't unregistrer current tempo map
	if ($song->{metronome_type} eq "simple") {
		&OSC_send("localhost",$project->{klick}{osc_port},"/klick/simple/set_tempo","f","$song->{metronome_tempo}");
		my @meters = split '/' , $song->{metronome_timesignature};
		&OSC_send("localhost",$project->{klick}{osc_port},"/klick/simple/set_meter","ii",@meters);
	}
	&OSC_send("localhost",$project->{klick}{osc_port},"/klick/metro/start");

	# load players
	print $project->{mixers}{players}{engine}->SelectAndConnectChainsetup($song->{name});
	
	# load midifile
	# TODO oups...jpmidi cannot load a new song & need a2jmidid to connect to some midi out
	
	#autostart ?
	&OSC_send("localhost",$project->{"jack-osc"}{osc_port},"/start","f","0") if $song->{autostart};
}
sub cmd_start { &OSC_send("localhost",$project->{"jack-osc"}{osc_port},"/start") if $project->{"jack-osc"}{enable}; }
sub cmd_stop { &OSC_send("localhost",$project->{"jack-osc"}{osc_port},"/stop") if $project->{"jack-osc"}{enable}; }
sub cmd_zero { &OSC_send("localhost",$project->{"jack-osc"}{osc_port},"/locate","f","0") if $project->{"jack-osc"}{enable}; }
sub cmd_locate {
	my $value = shift;
	&OSC_send("localhost",$project->{"jack-osc"}{osc_port},"/locate","f","$value") if $project->{"jack-osc"}{enable};
}
sub cmd_save {
	my $what = shift;
	$project->SaveDumperFile(".live") if ($what =~ /^(dumper|all)$/);
	$project->SaveToFile if ($what =~ /^(project|all)$/);
	$project->{bridge}->save_state_file($project->{bridge}{statefile}) if ($what =~ /^(state|all)$/);
}
sub cmd_status {
	# TODO print/reply status
}
sub cmd_reload {
	my $what = shift;
	$project->{bridge}->reload_current_state if $what eq "state";
	$project->{bridge}->reload_state_file($project->{bridge}{statefile}) if $what eq "statefile";
}
sub cmd_clic {
	my $command = shift;
	my $args = shift; # arrayref

	if ($command eq "start") { 
		&OSC_send("localhost",$project->{klick}{osc_port},"/klick/metro/start");
		return;
	}
	elsif ($command eq "stop") {
		&OSC_send("localhost",$project->{klick}{osc_port},"/klick/metro/stop");
		return;
	}
	elsif ($command eq "tempo") {
		&OSC_send("localhost",$project->{klick}{osc_port},"/klick/metro/set_type","s","simple");
		&OSC_send("localhost",$project->{klick}{osc_port},"/klick/simple/set_tempo","f",$args->[0]);
		return;
	}
	elsif ($command eq "inbuilt_sound") {
		&OSC_send("localhost",$project->{klick}{osc_port},"/klick/config/set_sound","i",$args->[0]);
		return;
	}
	elsif ($command eq "custom_sounds") {
		return unless -e $args->[0];
		return unless -e $args->[1];
		&OSC_send("localhost",$project->{klick}{osc_port},"/klick/config/set_sound","ss",@{$args});
		return;
	}
}
sub cmd_exit {
		print "\nSIGINT, Exiting...\n";

		print "Saving state file\n";
		$project->{bridge}->save_state_file($project->{bridge}{statefile});

		$project->{meters}->stop_jackpeak_meters;

		# TODO finish to close everything on exit

		exit(0);
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
	print ("Starting OSC listener on ip $oscip and port $oscport\n");
	#init socket on osc port
	my $osc_in = $bridge->{OSC}{socket} = IO::Socket::INET->new(
		LocalAddr => $oscip, #default is localhost
		LocalPort => $oscport,
		Proto	  => 'udp',
		Type	  =>  SOCK_DGRAM) || die $!;
	warn "cannot create socket $!\n" unless $osc_in;
	#create the anyevent watcher on this socket
	$bridge->{OSC}{events} = AE::io( $osc_in, 0, \&process_incoming_osc );
	#init an osc object
	$bridge->{OSC}{object} = Protocol::OSC->new;
}

sub process_incoming_osc {
	use Socket qw(getnameinfo NI_NUMERICHOST);
	my $debug = 0;

	# verify socket
	#-----------------------------------------
	die "Live process_osc error: could not read OSC socket in project\n" unless $project->{bridge}{OSC}{socket};
	die "Live process_osc error: could not read OSC object in project\n" unless $project->{bridge}{OSC}{object};
	
	#grab the message and sender info
	#-----------------------------------------
	my $sender = $project->{bridge}{OSC}{socket}->recv(my $oscpacket, $project->{bridge}{OSC}{socket}->sockopt(SO_RCVBUF));
	return unless defined $sender;
	#resolve the sender adress
	my($err, $sender_hostname, $servicename) = getnameinfo($sender, NI_NUMERICHOST);
	if ($err) { warn "Cannot resolve name - $err"; }
	#add sender address to known clients
	elsif (!defined $project->{bridge}{OSC}{clients}{$sender_hostname}) { $project->{bridge}{OSC}{clients}{$sender_hostname} = 1; }

	#parse the osc packet
	#-----------------------------------------
	my ($oscpath, $argtypes, @args) = @{$project->{bridge}{OSC}{object}->parse($oscpacket)};
	#TODO deal with osc bundles

	print "OSC MESSAGE\n------------\npath=$oscpath types=$argtypes and args " if $debug;
	if ($debug){print "$_," for @args};
	print "\n" if $debug;

	# verify if the osc message is in our list of known paths
	#--------------------------------------------------------
	if (defined $project->{bridge}{OSC}{paths}{$oscpath}) {

		# verify how many arguments we have
		# -----------------------------------------
		warn "Bridge warning: ignored osc message without arguments\n", return if ( length($argtypes) == 0 );
		warn "Bridge warning: ignored osc message with multiple arguments\n", return if ( length($argtypes) > 1 );

		#verify that incoming value is within (0,1) range
		#------------------------------------------------
		my $value = shift @args;
		warn "Bridge warning: ignored message without value\n", return if (!defined $value);
		warn "Bridge warning: OSC values must be within [0,1]\n", $value = 0 if ($value < 0);
		warn "Bridge warning: OSC values must be within [0,1]\n", $value = 1 if ($value > 1);

		# send the corresponding message
		#------------------------------------------------
		if (($project->{bridge}{OSC}{paths}{$oscpath}{protocol} eq "osc") and ($project->{bridge}{OSC}{paths}{$oscpath}{message})) {
			#send osc message if it exists
			&OSC_send("localhost",$project->{bridge}{OSC}{paths}{$oscpath}{port},"$project->{bridge}{OSC}{paths}{$oscpath}{message}","f","$value");
		}
		elsif (($project->{bridge}{OSC}{paths}{$oscpath}{protocol} eq "tcp") and ($project->{bridge}{OSC}{paths}{$oscpath}{message})) {
			# send tcp commands one after the other
			#TODO deal with how to send tcp command and do some eval for the $value/$realvalue
			print "will send $_ via port $project->{bridge}{OSC}{paths}{$oscpath}{port}\n" for @{$project->{bridge}{OSC}{paths}{$oscpath}{message}};
		}
		elsif (($project->{bridge}{OSC}{paths}{$oscpath}{protocol} eq "midi") and ($project->{bridge}{OSC}{paths}{$oscpath}{message})) {
			#TODO send midi data on osc receive
		}

		# update current value
		#------------------------------------------------
		$project->{bridge}{current_values}{$oscpath} = $value;

		# check if we send back information
		#------------------------------------------------
		if ($project->{bridge}{OSC}{sendback}) {
			print "we send back osc message \"/$oscpath f $value\" to $sender_hostname\n" if $debug;
			#send back OSC info
			&OSC_send($sender_hostname,$project->{bridge}{OSC}{outport},"$oscpath","f","$value") unless $sender_hostname eq $project->{bridge}{OSC}{ip};
			#TODO sendback for each registered client &OSC_send($_,$project->{bridge}{OSC}{outport}",/$oscpath","f","$value") for @{keys $project->{bridge}{OSC}{clients}};
			return;
		}
	}
	else
	# else verify if the osc message is an astrux command
	#-----------------------------------------------------
	{
		#split path elements
		$oscpath =~ s(^/)();
		my @pathelements = split '/',$oscpath;

		# TODO should we add /astrux/ to prevent mixername can't be start/stop...etc and would need to check on create

		#element 1 = system command
		my $element1 = shift @pathelements;
		if ($element1 eq "ping") {
			&OSC_send($sender_hostname,$project->{bridge}{OSC}{outport},"/pong");
			return;
		}
		elsif ($element1 eq "start") { &cmd_start; return; }
		elsif ($element1 eq "stop") { &cmd_stop; return; }
		elsif ($element1 eq "zero") { &cmd_zero; return; }
		elsif ($element1 eq "locate") {
			return unless $argtypes =~ /^(f|i)$/;
			my $value = shift @args;
			&cmd_locate($value);
			return;
		}
		elsif ($element1 eq "save") {
			my $element2 = shift @pathelements;
			return unless $element2;
			&cmd_save($element2);
			return;
		}
		elsif ($element1 eq "status") {
			&cmd_status;
			return;
		}
		elsif ($element1 eq "song") {
			my $element2 = shift @pathelements;
			if (defined $element2) {
				return unless $argtypes =~ /^(f|i)$/;
				my $val = shift @args;
				return unless ($val == 1);
				&cmd_song($project->{songs}{$element2});
				return;
			}
			return unless $argtypes =~ /^(s)$/;
			my $songname = shift @args;
			return unless exists $project->{songs}{$songname};
			&cmd_song($project->{songs}{$songname});
			return;
		}
		elsif ($element1 eq "reload") {
			my $element2 = shift @pathelements;
			return unless $element2;
			&cmd_reload($element2);
			return;
		}
		elsif ($element1 eq "clic") {
			my $element2 = shift @pathelements;
			return unless $element2;
			&cmd_clic("start") if $element2 eq "start";
			&cmd_clic("stop") if $element2 eq "stop";
			return unless @args;
			&cmd_clic("tempo",\@args) if ($element2 eq "tempo") and ($argtypes =~ /^(f|i)$/);
			&cmd_clic("inbuilt_sound",\@args) if ($element2 eq "tempo") and ($argtypes =~ /^(i)$/);
			&cmd_clic("custom_sounds",\@args) if ($element2 eq "tempo") and ($argtypes =~ /^(ss)$/);
			return;
		}
		elsif ($element1 eq "exit") {
			&cmd_exit;
		}
	}
}

sub OSC_send {
	my $destination = shift;
	my $port = shift;
	return unless $port;
	my $oscpath = shift;
	return unless $oscpath;
	my $types = shift;
	my $arguments = shift;

	my @specs;
	push @specs , $oscpath;
	push @specs , $types if $types;
	#TODO verify @values number equals types
	# return unless ... ne $#{$arguments}+1
	if (ref($arguments) eq "ARRAY") {
		push @specs , $_ for @{$arguments};
	}
	else {
		push @specs , $arguments;
	}

	my $osc = Protocol::OSC->new;
	my $oscpacket = $osc->message(@specs);

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
    print "connection from $client_address:$client_port\n";
 
    # read up to 256 characters from the connected client
    my $data = "";
    $client_socket->recv($data, 256);
    print "received data: $data\n";

    chomp($data);
	my $reply = &parse_cmd($data);

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
	print &parse_cmd($command);
	return 1;
}

###########################################################
#
#		 BRIDGE METERS functions
#
###########################################################

sub init_meters {
	my $fifo = $project->{meters}{options}{port};
	die "Bridge error: missing port/fifo definition in meters!\n" unless $project->{meters}{options}{port};
	my $speed = $project->{meters}{options}{speed} || "100";
	print "Reading meters every $speed ms\n";
	$speed = $speed/1000;
	#create the anyevent timer @100ms by default on the meters fifo
	$project->{meters}{events} = AE::timer( 0, $speed, \&process_meters );
}

sub process_meters {
	my $fifofile = $project->{meters}{options}{port};
	use Fcntl;
	$| = 1;
	my $fifo_fh;
	# open in non-blocking mode if nothing is to be read in the fifo
	sysopen($fifo_fh, $fifofile, O_RDWR) or warn "The FIFO file \"$fifofile\" is missing\n";
	while (<$fifo_fh>) {
		my (@meters,@peaks);
		if ($project->{meters}{options}{peaks}) {
			my @duo = split (/\|/);
			@meters = split ' ', $duo[0];
			@peaks = split ' ', $duo[1];
		}
		else {
			@meters = split ' ';
		}
		#upate project meters with current value 
		for my $i (0..$#meters) {
			$project->{meters}{values}[$i]->{current_value} = $meters[$i];
			$project->{meters}{values}[$i]->{current_peak} = $peaks[$i] if @peaks;
		}
		#force exit
		last;
	}
	close $fifo_fh;
}

1;