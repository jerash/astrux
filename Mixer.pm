#!/usr/bin/perl

package Mixer;

use strict;
use warnings;

use EcaEngine;
use Strip;
use NonEngine;
use feature 'state';

my $debug = 0;

###########################################################
#
#		 MIXER OBJECT functions
#
###########################################################

sub new {
	my $class = shift;
	my $ini_mixer_file = shift;
	my $output_path = shift;
	die "Mixer Error: can't create mixer without ini file\n" unless $ini_mixer_file;
	die "Mixer Error: can't create mixer without output path\n" unless $output_path;
	
	my $mixer = {
		"output_path" => $output_path
		# "engine" => {},
		# "IOs" => {}
	};
	bless $mixer, $class;

	#fill from ini file and create the mixer file
	$mixer->init($ini_mixer_file);

	return $mixer;
}

sub init {
	my $mixer = shift;
	my $ini_mixer_file = shift;
	
	use Config::IniFiles;
	#ouverture du fichier ini de configuration des channels
	tie my %mixer_io, 'Config::IniFiles', ( -file => $ini_mixer_file );
	die "Mixer Error: reading I/O ini file failed\n" unless %mixer_io;
	my $mixer_io_ref = \%mixer_io;

	#verify if [mixer_globals] section exists
	if (!$mixer_io_ref->{mixer_globals}) {
		die "Mixer Error: missing [mixer_globals] section in $ini_mixer_file mixer file\n";
	}
	my %globals = %{$mixer_io_ref->{mixer_globals}};

	#test wich engine we use
	if ($globals{engine} eq "ecasound") {
		#create ecsfile path
		my $ecsfile = $mixer->{output_path} . "/" . $globals{name} . ".ecs";
		$mixer->{engine} = EcaEngine->new($ecsfile,$globals{name});
		#add ENV variable for effect path
		die "Mixer Error: missing eca_cfg_path in mixer_globals inifile\n" unless exists $globals{eca_cfg_path};
		use File::Basename;
		my ($filename,$pathto,$suffix) = fileparse($ini_mixer_file);
		$ENV{'ECA_CFG_PATH'} = "$pathto$globals{eca_cfg_path}";
	}
	elsif ($globals{engine} eq "non-mixer") {
		#bless structure to access data with module functions
		$mixer->{engine} = NonEngine->new($mixer->{output_path},$globals{name});
	}

	#merge global info info to created engine
	$mixer->{engine}{$_} = $globals{$_} for (keys %globals);

	#remove mixer globals from IO hash to prevent further ignore
	delete $mixer_io_ref->{mixer_globals};

	#add IO info to mixer
	$mixer->{IOs} = $mixer_io_ref;

	#add channel strips to mixer
	$mixer->BuildMainMixer if $mixer->is_main;
	$mixer->BuildSubmix if $mixer->is_submix;
	$mixer->BuildPlayers if $mixer->is_player;

	#remove IO info not necessary anymore
	delete $mixer->{IOs};
}

###########################################################
#
#		 MIXER functions
#
###########################################################

sub BuildMainMixer {
	my $mixer = shift;
	$mixer->BuildEcaMainMixer if ($mixer->is_ecasound);
	$mixer->BuildNonMixer if ($mixer->is_nonmixer);
}
sub BuildSubmix {
	my $mixer = shift;
	$mixer->BuildEcaSubmix if ($mixer->is_ecasound);
	$mixer->BuildNonMixer if ($mixer->is_nonmixer);
}
sub BuildPlayers {
	my $mixer = shift;
	die "Players mixer must be ecasound !!\n" if !$mixer->is_ecasound;
	$mixer->CreateEcaPlayers;
}

sub Start {
	my $mixer = shift;
	$mixer->{engine}->StartEcasound if ($mixer->is_ecasound);
	$mixer->{engine}->StartNonmixer if ($mixer->is_nonmixer);	
}

sub Create_File {
	my $mixer = shift;

	#if ecasound
	$mixer->{engine}->CreateEcsFile if ($mixer->is_ecasound);
	
	#if nonmixer
	$mixer->CreateNonFiles if ($mixer->is_nonmixer);
}

sub Sanitize_EffectsParams {
	my $mixer = shift;
	my $samplerate = shift;

	die "Mixer error: can't sanitize effects without samplerate\n" unless $samplerate;

	foreach my $channel (keys %{$mixer->{channels}}) {
		foreach my $insert (keys %{$mixer->{channels}{$channel}{inserts}}) {
			if ( $mixer->{channels}{$channel}{inserts}{$insert}->is_LADSPA ) {
				$mixer->{channels}{$channel}{inserts}{$insert}->SanitizeLADSPAFx($samplerate);
			}
		}
	}
}

###########################################################
#
#		 MIXER TEST functions
#
###########################################################

sub is_main {
	my $mixer = shift;
	return 1 if $mixer->{engine}{type} eq "main";
	return 0;
}
sub is_submix {
	my $mixer = shift;
	return 1 if $mixer->{engine}{type} eq "submix";
	return 0;
}
sub is_player {
	my $mixer = shift;
	return 1 if $mixer->{engine}{type} eq "player";
	return 0;
}
sub is_ecasound {
	my $mixer = shift;
	return 1 if $mixer->{engine}{engine} eq "ecasound";
	return 0;
}
sub is_nonmixer {
	my $mixer = shift;
	return 1 if $mixer->{engine}{engine} eq "non-mixer";
	return 0;
}
sub is_midi_controllable {
	my $mixer = shift;
	return 1 if ($mixer->{engine}{control} =~ /midi/);
}
sub is_osc_controllable {
	my $mixer = shift;
	return 1 if ($mixer->{engine}{control} =~ /osc/);
}
sub is_tcp_controllable {
	my $mixer = shift;
	return 1 if ($mixer->{engine}{control} =~ /tcp/);
}

###########################################################
#
#		 MIXER UTILITY functions
#
###########################################################

sub get_name {
	my $mixer = shift;
	return $mixer->{engine}{name};
}
sub get_tcp_port {
	my $mixer = shift;
	return $mixer->{engine}{tcp_port};
}
sub get_inputs_list {
	my $mixer = shift;
	my @inputnames;
	foreach my $channelname (keys %{$mixer->{channels}}) {
			push @inputnames, $channelname if (($mixer->{channels}{$channelname}->is_main_in) or 
											($mixer->{channels}{$channelname}->is_submix_in));
	}
	my @sorted_inputnames = &sort_by_group_and_name($mixer,\@inputnames);
	return @sorted_inputnames;
}
sub get_auxes_list {
	my $mixer = shift;
	my @auxnames;
	foreach my $channelname (keys %{$mixer->{channels}}) {
			push @auxnames, $channelname if ($mixer->{channels}{$channelname}->is_aux);
	}
	my @sorted_auxnames = &sort_by_group_and_name($mixer,\@auxnames);
	return @sorted_auxnames;
}
sub get_buses_list {
	my $mixer = shift;
	my @busnames;
	foreach my $channelname (keys %{$mixer->{channels}}) {
			push @busnames, $channelname if ($mixer->{channels}{$channelname}->is_bus_out);
	}
	my @sorted_busnames = &sort_by_group_and_name($mixer,\@busnames);
	return @sorted_busnames;
}
sub get_main_out {
	my $mixer = shift;
	my $mainout;
	foreach my $channelname (keys %{$mixer->{channels}}) {
		$mainout = $channelname if ($mixer->{channels}{$channelname}->is_main_out);
	}
	return $mainout;
}
sub get_submix_out {
	my $mixer = shift;
	my $submixout;
	foreach my $channelname (keys %{$mixer->{channels}}) {
		$submixout = $channelname if ($mixer->{channels}{$channelname}->is_submix_out);
	}
	return $submixout;
}

###########################################################
#
#			ECASOUND functions
#
###########################################################

sub BuildEcaMainMixer {
	my $mixer = shift;
	
	#----------------------------------------------------------------
	print " |_Mixer:BuildEcaMainMixer name : " . $mixer->get_name . "\n";
	#----------------------------------------------------------------
	# === I/O Channels, Buses, Sends ===
	#----------------------------------------------------------------
	my @i_chaintab;
	my @o_chaintab;
	my @i_nametab;
	my @o_nametab;
	my @x_chaintab;

	#check each channel defined in the IO
	foreach my $name (keys %{$mixer->{IOs}} ) {		

		#ignore inactive channels
		next unless $mixer->{IOs}{$name}{status} eq "active";

		#create the channel strip
		my $strip = Strip->new;
		$strip->init($mixer->{IOs}{$name},$mixer->is_midi_controllable);

		#add strip to mixer
		$mixer->{channels}{$name} = $strip;
		
		#==INPUTS,RETURNS,SUBMIX_IN,PLAYERS_IN==
		if ( $strip->is_main_in ) {
			#create ecasound chain
			push( @i_chaintab , $strip->get_eca_input_chain($name) );
			push( @o_chaintab , $strip->get_eca_loop_output_chain($name) );
			push( @i_nametab , $name );
		}
		#==BUS OUTPUTS AND SEND==
		elsif ( $strip->is_hardware_out ) {
			push( @i_chaintab , $strip->get_eca_bus_input_chain($name) );
			push( @o_chaintab , $strip->get_eca_bus_output_chain($name) );
			push( @o_nametab , $name );			
		}
		else {
			warn "bad IO definition in main mixer with type \n" . $strip->{type};
		}
	}

	#----------------------------------------------------------------
	#==CHANNELS ROUTING TO BUSES AND SENDS==
	#----------------------------------------------------------------

	#to each channel defined as active input
	foreach my $channel (@i_nametab ) {		

		#create aux input line
		my $iline = "-a:";

		#add a route to the defined buses
		foreach my $bus (@o_nametab) {

			if ( $mixer->{channels}{$bus}{return} and ( $mixer->{channels}{$bus}{return} eq $channel )) {
				print "   |_info: discarding sendbus to himself ($bus) \n";
			}
			else {
				
				#init the aux input line
				$iline .= "$channel" . "_to_$bus,";

				#create a channel strip
				my $strip = Strip->new;
	
				#init the aux strip, & verify if the mixer is defined using midi control
				$strip->eca_aux_init($mixer->is_midi_controllable);
	
				#add aux route strip to mixer
				$mixer->{channels}{$channel}{aux_route}{$bus} = $strip;

				#grab the aux route inserts (static define to panvol only)
				my $inserts = $mixer->{channels}{$channel}{aux_route}{$bus}{inserts}{panvol}{ecsline};
				#create aux outputs line
				my $oline = "-a:" . $channel . "_to_$bus -f:f32_le,2,48000 -o:jack,,to_bus_$bus $inserts";
				push  (@x_chaintab , $oline );
			}
		}

		#finish the aux input line
		chop($iline);
		$iline .= " -f:f32_le,2,48000 -i:loop,$channel";
		push  (@x_chaintab , $iline );
	}

	#add aux chains to ecasound info
	$mixer->{engine}{x_chains} = \@x_chaintab if @x_chaintab;

	#add input chains to ecasound info
	$mixer->{engine}{i_chains} = \@i_chaintab if @i_chaintab;

	#add output chains to ecasound info
	$mixer->{engine}{o_chains} = \@o_chaintab if @o_chaintab;

	#udpate mixer info with curretly selected chainsetup
	$mixer->{current}{chainsetup} = $mixer->{engine}->get_selected_chainsetup;
	#udpate mixer info with curretly selected chain (channel)
	$mixer->{current}{channel} = $mixer->{engine}->get_selected_channel;
	#udpate mixer info with curretly selected effect
	$mixer->{current}{effect} = $mixer->{engine}->get_selected_effect;

}

sub BuildEcaSubmix {
	my $mixer = shift;
	
	#----------------------------------------------------------------
	print " |_Mixer:Create Submix mixer name : " . $mixer->get_name . "\n";
	#----------------------------------------------------------------
	# === Submix ===
	#----------------------------------------------------------------

	my @i_chaintab;
	my @o_chaintab;

	#check each channel defined in the IO
	foreach my $name (sort keys %{$mixer->{IOs}} ) {		

		#ignore inactive channels
		next unless $mixer->{IOs}{$name}{status} eq "active";

		#create the channel strip
		my $strip = Strip->new;
		$strip->init($mixer->{IOs}{$name},$mixer->is_midi_controllable);

		#add strip to mixer
		$mixer->{channels}{$name} = $strip;
		
		#==SUBMIX==
		#create ecasound chain
		push( @i_chaintab , $strip->get_eca_input_chain($name) ) if ( $strip->is_submix_in );
		push( @o_chaintab , $strip->get_eca_submix_output_chain($name) ) if ( $strip->is_submix_out );
		warn "bad IO definition in submix with type \n" . $strip->{type} unless ( ( $strip->is_submix_in ) or ( $strip->is_submix_out ));
	}

	#add input chains to ecasound info
	$mixer->{engine}{i_chains} = \@i_chaintab if @i_chaintab;

	#add output chains to ecasound info
	$mixer->{engine}{o_chains} = \@o_chaintab if @o_chaintab;

}

sub CreateEcaPlayers {
	my $mixer = shift;
	
	#----------------------------------------------------------------
	print " |_Mixer:Create Player mixer name : " . $mixer->get_name . "\n";
	#----------------------------------------------------------------
	# === Players ===
	#----------------------------------------------------------------

	my @io_chaintab;

	#check each channel defined in the IO
	foreach my $name (sort keys %{$mixer->{IOs}} ) {		

		#ignore inactive channels
		next unless $mixer->{IOs}{$name}{status} eq "active";

		#create the channel strip
		my $strip = Strip->new;
		$strip->init($mixer->{IOs}{$name},$mixer->is_midi_controllable);

		#add strip to mixer
		$mixer->{channels}{$name} = $strip;
		
		#==PLAYERS==
		#create ecasound chain
		push( @io_chaintab , $strip->get_eca_player_chain($name) ) if ( $strip->is_file_player );
		warn "bad IO definition in players with type \n" . $strip->{type} unless ( $strip->is_file_player );
	}

	#add chains to ecasound info
	$mixer->{engine}{io_chains} = \@io_chaintab if @io_chaintab;
}

###########################################################
#
#		 NON-MIXER functions
#
###########################################################

sub BuildNonMixer {
	my $mixer = shift;
	
	print " |_Mixer:Create Main Mixer name : " . $mixer->get_name . "\n";

	#add channels defined in the IO to mixer
	foreach my $name (sort keys %{$mixer->{IOs}} ) {		

		#ignore inactive channels
		next unless $mixer->{IOs}{$name}{status} eq "active";

		#create the channel strip
		my $strip = Strip->new;
		$strip->init($mixer->{IOs}{$name},$mixer->is_midi_controllable);

		#add strip to mixer
		$mixer->{channels}{$name} = $strip;
	}
	#TODO now check for auxes and stuff, and add default elements
}

sub CreateNonFiles {
	my $mixer = shift;

	#path where to store the nonmixer files
	my $mixerpath = $mixer->{output_path} . "/" . $mixer->{engine}{name};
	
	#check if the folder already exists
	if (! -d $mixerpath) {
		print "Mixer: nonmixer folder does not exists, creating\n";
		mkdir $mixerpath;
		die "Error: directry creation failed!\n" if (! -d $mixerpath);	
	}

	print" |_Mixer: saving non mixer to $mixerpath\n";

	#create the non info files
	foreach my $file (keys $mixer->{engine}{files}) {
		my $filepath = $mixerpath . "/" . $file;
		open FILE, ">$filepath" or die $!;
		my $content = $mixer->{engine}{files}{$file};
		print FILE $content if $content;
		close FILE;
	}
	delete $mixer->{engine}{files};

	# to build the snapshot file
	# first have an id counter
	my $id;
	# then check for number of aux outputs
	my %auxes;
	my $auxletter = 'A';
	# then check for groups
	my %groups;
	#then have a strip id reminder
	my %stripid;
	#then have a chain id reminder
	my %chainid;

	foreach my $channel (sort (keys $mixer->{channels})) {
		# add to auxes if it should be
		if ($mixer->{channels}{$channel}->is_aux) {
			#update local list, and project structure with aux reference
			$mixer->{channels}{$channel}{aux_letter} = $auxes{$channel} = "$auxletter";
			$auxletter++;
		}
		# add new group if doesn't exist
		my $group = $mixer->{channels}{$channel}{group} if ($mixer->{channels}{$channel}{group} ne '');
		if (defined $group) {
			$groups{$group} = &get_next_non_id unless (exists $groups{$group});
		}
	}

	# then build the snapshot lines
	my @snapshot;
	#add {
	push @snapshot, "{";
	
	#add groups
	foreach my $group (keys %groups) {
		push @snapshot, "\tGroup $groups{$group} create :name \"$group\"" if ($group ne '');
	}

	#add channels
	foreach my $channelname (sort (keys $mixer->{channels})) {
		my $line = "";
		my $channel = $mixer->{channels}{$channelname};

		#Mixer Strip
		#generate a 0x id
		$id = &get_next_non_id;
		$stripid{$channelname} = $id;
		#Mixer_Strip 0xB create :name "non_out" :width "narrow" :tab "signal" :color 878712457 :gain_mode 0 :mute_mode 0 :group 0x2 :auto_input "*/mains" :manual_connection 0
		$line = "\tMixer_Strip $id create :name \"$channelname\" ";
		$line .= ":width \"narrow\" :tab \"signal\" :color 878712457 ";
		$line .= ":gain_mode 0 :mute_mode 0 ";
		$line .= ":group $groups{$channel->{group}} " if ($channel->{group} ne '');
		$line .= ":group \"\" " if ($channel->{group} eq '');
		#autoconnect mains out
		if ((($channel->is_main_out) or ($channel->is_submix_out)) and ($mixer->{engine}{autoconnect} eq 1)){
			$line .= ":auto_input \"inputs/mains\" ";
		}
		#autoconnect auxes
		elsif (($channel->is_hardware_out) and ($mixer->{engine}{autoconnect} eq 1)) {
			$line .= ":auto_input \"inputs/$auxes{$channelname}\" ";
		}
		else {
			$line .= ":auto_input \"\" ";
		}
		$line .= ":manual_connection 0";
		push @snapshot,$line;

		#Chain
		#generate a 0x id
		$id = &get_next_non_id;
		$chainid{$channelname} = $id;
		$line = "\tChain $id create :strip $stripid{$channelname} :tab \"chain\"";
		push @snapshot,$line;
		
		#JACK module
		#generate a 0x id
		$id = &get_next_non_id;
		#JACK_Module 0x3 create :parameter_values "0.000000:1.000000" :is_default 1 :chain 0x2 :active 1
		$line = "\tJACK_Module $id create :parameter_values \"0.000000:1.000000\" :is_default 1 :chain $chainid{$channelname} :active 1"
			if ($channel->is_mono);
		#JACK_Module 0xF create :parameter_values "0.000000:2.000000" :is_default 1 :chain 0xE :active 1
		$line = "\tJACK_Module $id create :parameter_values \"0.000000:2.000000\" :is_default 1 :chain $chainid{$channelname} :active 1"
			if ($channel->is_stereo);
		push @snapshot,$line;
		
		if ($mixer->{engine}{addpregain}) {
			#Gain module (default)
			#generate a 0x id
			$id = &get_next_non_id;
			#Gain_Module 0x4 create :parameter_values "0.500000:0.000000" :is_default 1 :chain 0x2 :active 1
			$line = "\tGain_Module $id create :parameter_values \"0.000000:0.000000\" :is_default 1 :chain $chainid{$channelname} :active 1";
			push @snapshot,$line;
		}

		# pan module
		if ($channel->is_mono) { #add a mono to stereo converter with pan (nonmixer native)
			#generate a 0x id
			$id = &get_next_non_id;
			#Mono_Pan_Module 0x2B create :parameter_values "-1.000000" :is_default 0 :chain 0x2 :active 1
			$line = "\tMono_Pan_Module $id create :parameter_values \"0.000000\" :is_default 0 :chain $chainid{$channelname} :active 1";
			push @snapshot,$line;
		}
		elsif ($channel->is_stereo) { #add a stereo balance control (LADSPA 1956), could use 1955 too
			#generate a 0x id
			$id = &get_next_non_id;
			# Plugin_Module 0x65 create :plugin_id 1955 :plugin_ins 2 :plugin_outs 2 :parameter_values "0:1" :is_default 0 :chain 0x63 :active 1
			$line = "\tPlugin_Module $id create :plugin_id 1956 :plugin_ins 2 :plugin_outs 2 :parameter_values \"0:-1:1\" :is_default 0 :chain $chainid{$channelname} :active 1";
			push @snapshot,$line;
		}
		
		#PLUGIN modules
		foreach my $plugin (keys %{$channel->{inserts}}) {
			#ensure it is a LADSPA plugin
			next unless $channel->{inserts}{$plugin}->is_LADSPA;
			#get number of audio ios
			my $inputs = $channel->{inserts}{$plugin}{audio_io}{inputs};
			my $outputs = $channel->{inserts}{$plugin}{audio_io}{outputs};
			#get default paramvalues
			my $paramvalues;
			$paramvalues .= "$_:" for @{$channel->{inserts}{$plugin}{defaultvalues}};
			chop($paramvalues);
			#generate a 0x id
			$id = &get_next_non_id;
			#Plugin_Module 0xF1 create :plugin_id 2598 :plugin_ins 2 :plugin_outs 2 :parameter_values "0.000000:1.000000:0.000000:0.250000:0.000000:0.250000:0.000000" :is_default 0 :chain 0x24 :active 1
			$line = "\tPlugin_Module $id create :plugin_id $plugin :plugin_ins $inputs :plugin_outs $outputs :parameter_values \"$paramvalues\" :is_default 0 :chain $chainid{$channelname} :active 1";
			push @snapshot,$line;
		}

		#AUX module
		my $auxnumber = 0;
		foreach my $aux (keys %auxes) {
			if ($channel->is_main_in) { #create an aux send only for main mixer input channels
				# next if ((defined $mixer->{channels}{$aux}{return}) and ($mixer->{channels}{$aux}{return} eq $channelname));
					 #we shouldn't create an aux send to ourself, but it screws up the aux letter assignations, so we create it but we won't route it.
				#generate a 0x id
				$id = &get_next_non_id;
			#AUX_Module 0x2D create :number 0 :parameter_values "0.000000" :is_default 0 :chain 0x2 :active 1
				$line = "\tAUX_Module $id create :number $auxnumber :parameter_values \"0.000000\" :is_default 0 :chain $chainid{$channelname} :active 1";
				push @snapshot,$line;
				$auxnumber++;
			}	
		}

		#Gain module (post fx volume)
		#generate a 0x id
		$id = &get_next_non_id;
		#Gain_Module 0x4 create :parameter_values "0.500000:0.000000" :is_default 1 :chain 0x2 :active 1
		$line = "\tGain_Module $id create :parameter_values \"0.000000:0.000000\" :is_default 0 :chain $chainid{$channelname} :active 1";
		push @snapshot,$line;
		
		if ($mixer->{engine}{addmeters}) {
			#Meter module
			#generate a 0x id
			$id = &get_next_non_id;
			#Meter_Module 0x5 create :is_default 1 :chain 0x2 :active 1
			$line = "\tMeter_Module $id create :is_default 1 :chain $chainid{$channelname} :active 1";
			push @snapshot,$line;
		}

		#JACK module
		#generate a 0x id
		$id = &get_next_non_id;
		#JACK_Module 0x6 create :parameter_values "2.000000:0.000000" :is_default 1 :chain 0x2 :active 1
		$line = "\tJACK_Module $id create :parameter_values \"2.000000:0.000000\" :is_default 1 :chain $chainid{$channelname} :active 1";
		push @snapshot,$line;
		
	}
	#add }
	push @snapshot, "}";

	#save the snapshot file
	my $filepath = $mixerpath . "/snapshot";
	open FILE, ">$filepath" or die $!;
	print FILE "$_\n" for @snapshot;
	close FILE;
}

sub get_next_non_id {
	state $id = 0;
	$id++;
	return sprintf ("0x%x",$id);
}

sub sort_by_group_and_name {
	my $mixer = shift;
	my $channelnames = shift;
	#organize channels by group
	my $tree;
	foreach my $channelname (@{$channelnames}) {
		if ($mixer->{channels}{$channelname}{group}) {
			$tree->{$mixer->{channels}{$channelname}{group}} .= "$channelname,";
		}
		else {
			$tree->{zzzzz} .= "$channelname,";
		}
	}
	#sort group names
	my @sorted_groups = sort { lc($a) cmp lc($b) } (keys %{$tree});
	#sort channels by group then channelname
	my $sorted_channelnames = "";
	while (my $val = shift @sorted_groups) {
		#sort channels
		$sorted_channelnames .= join "," , sort { lc($a) cmp lc($b) } (split "," , $tree->{$val});
		$sorted_channelnames .= ",";
	}
	return split "," , $sorted_channelnames;
}

1;