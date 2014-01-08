#!/usr/bin/perl

package EcaEcs;

use strict;
use warnings;

use Data::Dumper;

sub new {
	my $class = shift;
	#ecasound engine configuration options
	my $ini_mixer = shift;
	#complete path to the file
	my $ecsfile = shift;
	
	#create object
	my $ecaecs = $ini_mixer;
	#add ecs file path to object
	$ecaecs->{ecsfile} = $ecsfile;
	$ecaecs->{status} = "notcreated";
	bless $ecaecs,$class;

	#create the file in the specified path
	#print "---EcaEcs\n path = $path\n info = $info\n";
	$ecaecs->create if (defined $ecsfile);
	#add file header
	$ecaecs->build_header if (defined $ini_mixer);

	return $ecaecs;
}
sub create {
	#create the file (overwrite)
	my $ecaecs = shift;
	my $path = $ecaecs->{ecsfile};
	#print "---EcaEcs:create\n path = $path\n";
	die "no path to create ecs file\n" unless (defined $path);
	open my $handle, ">$path" or die $!;
	#update mixer status
	$ecaecs->{status} = "new";
}
sub open_add {
	#open a filehandle to the file (rw add)	
	my $ecaecs = shift;
	my $ecsfile = $ecaecs->{ecsfile};
	open my $handle, ">>$ecsfile" or die $!;
}
sub close {
	#close the filehandle to the file
	my $ecaecs = shift;
	close $ecaecs->{ecsfile};
}
sub build_header {
	my $ecaecs = shift;
	#print Dumper $ecaecs;
	my $name = $ecaecs->{name};
	my $header = "#GENERAL\n";
	$header .= "-b:".$ecaecs->{buffersize} if $ecaecs->{buffersize};
	$header .= " -r:".$ecaecs->{realtime} if $ecaecs->{realtime};
	my @zoptions = split(",",$ecaecs->{z});
	foreach (@zoptions) {
		$header .= " -z:".$_;
	}
	$header .= " -n:\"$name\"";
	$header .= " -z:mixmode,".$ecaecs->{mixmode} if $ecaecs->{mixmode};
	$header .= " -G:jack,$name,notransport" if ($ecaecs->{sync} == 0);
	$header .= " -G:jack,$name,sendrecv" if ($ecaecs->{sync});
	$header .= " -Md:".$ecaecs->{midi} if $ecaecs->{midi};
	#add header to file
	#print "--EcaEcs:build_header\n header = $header\n";
	my $file;
	die "ecs file has not been created" if ($ecaecs->{status} eq "notcreated");
	$file = $ecaecs->open_add;
	#append to file
	print $file $header;
	#update status
	$ecaecs->{status} = "header";
}



# 	#ajouter channel inserts
# 	#ajouter channel inserts
# 	if ( $mixer->{IOs}->val($section,'insert') ) {
# 		#verify how many inserts are defined
# 		my @inserts = split(",", $mixer->{IOs}->val($section,'insert') );
# 		foreach my $insert ( @inserts ) {
# 			# TODO : split on | for parralel effects ?
# 			#print "one effect here : $insert\n";
# 			#get default values
# 			my @def_dump = MidiCC::Get_defaults($insert);
# 			$line .= " -pn:$insert" . $def_dump[1] if $def_dump[0];
# 			if ($create_midi_CC) {
# 				#ajouter les contrôleurs midi
# 				my $path = "/$eca_mixer/inputs/" . $mixer->{IOs}->val($section,'name') . "/$insert";
# 				my @CC_dump = MidiCC::Generate_km($insert,$path);
# 				#status is in first parameter, km info is in second parameter
# 				$line .= $CC_dump[1] if $CC_dump[0];
# 			}
# 		}
# 	}

# 		#ajouter la règle de plumbing
# 		#pour une piste player
# 		if ( $mixer->{IOs}->val($section,'type') eq 'player' ) {
# 			for my $i (1..2) {
# 				#grab player number
# 				my $nb = substr ($mixer->{IOs}->val($section,'name'), -1, 1);
# 				#deal with stereo pair
# 				my $plumbin = "player:out_$nb" . "_.*[13579]\$" if ($i==1);
# 				$plumbin = "player:out_$nb" . "_.*[02468]\$" if ($i==2);
# 				my $plumbout = "$eca_mixer:";
# 				$plumbout .= $mixer->{IOs}->val($section,'name') . "_$i";
# 				$plumbing->Add("(connect \"$plumbin\" \"$plumbout\")") if $plumbin;
# 			}
# 		}
# 		#pour une piste submix
# 		elsif ( $mixer->{IOs}->val($section,'type') eq 'submix' ) {
# 			my $plumbin = "submix_" . $mixer->{IOs}->val($section,'name') . ":" . $mixer->{IOs}->val($section,'name') . "_out_(.*)";
# 			my $plumbout = "$eca_mixer:" . $mixer->{IOs}->val($section,'name') . "_\\1";
# 			$plumbing->Add("(connect \"$plumbin\" \"$plumbout\")") if $plumbin;
# 		}
# 		else { #pour une piste input,return
# 			for my $i (1..2) {
# 				if (( $mixer->{IOs}->val($section,'type') eq 'audio' ) or ( $mixer->{IOs}->val($section,'type') eq 'return' )) {
# 					my $plumbin = $mixer->{IOs}->val($section,"hardware_input_$i");
# 					my $plumbout = "$eca_mixer:" . $mixer->{IOs}->val($section,'name') . "_$i";
# 					$plumbing->Add("(connect \"$plumbin\" \"$plumbout\")") if $plumbin;
# 				}
# 				elsif ( $mixer->{IOs}->val($section,'type') eq 'submix' ) {
# 					$plumbing->Add(";submix");
# 					my $plumbin = "submix_" . $mixer->{IOs}->val($section,'name') . ":out_(.*)";
# 					my $plumbout = "$eca_mixer:submix_" . $mixer->{IOs}->val($section,'name') . "_\\1";
# 					$plumbing->Add("(connect \"$plumbin\" \"$plumbout\")");
# 					last;
# 				}
# 			}
# 		}


#---old non object code to integrate

# 	}
# 	#section valide
# 	 #ajoute à la liste des sections valides
# 	push(@valid_input_sections,$section);
# 	 #ajoute la ligne à la liste des ai
# 	push(@inputs_ai,$line);
# 	 #crée la sorite loop
# 	$line = "-a:$number -f:f32_le,2,48000 -o:loop," . $mixer->{IOs}->val($section,'name');
# 	push(@inputs_ao,$line);
# }
# print "Found " . (scalar @valid_input_sections) . " valid audio input definitions\n";
# if ($debug) {
# 	print "\nINPUT CHAINS\ninputs_ai\n";
# 	print Dumper (@inputs_ai);
# 	print "inputs_ao\n";
# 	print Dumper (@inputs_ao);
# }
# #----------------------------------------------------------------
# # -- CHANNELS routing to bus sends --
# $plumbing->Add(";channels routes");
# my @output_sections = $mixer->{IOs}->Sections;
# print "\nFound " . (scalar @output_sections) . " output definitions in ini file\n";
# #pour chaque entrée définie dans le fichier ini
# #vérification de la validité de la sortie
# while (my $section = shift @output_sections) {
# 	#si entrée invalide, suivante
# 	next until ( $mixer->{IOs}->val($section,'status') eq 'active' );
# 	next until ( $mixer->{IOs}->val($section,'type') eq 'bus' ) or ( $mixer->{IOs}->val($section,'type') eq 'send' );
# 	die "must have a track name\n" until ( $mixer->{IOs}->val($section,'name') );
# 	#stocker la section valide
# 	push(@valid_output_sections, $section );
# }
# print "Found " . (scalar @valid_output_sections) . " valid audio output definitions\n";
# #construction des chains
# #foreach valid channel
# my $line = "-a:";
# foreach my $channel (@valid_input_sections) {
# 	#foreach valid bus
# 	foreach my $bus (@valid_output_sections) {
# 		#ignore send bus to himmixer
# 		if ($mixer->{IOs}->val($bus,'return')) { #prevent display of "Use of uninitialized value in string eq at"
# 			next if (($mixer->{IOs}->val($bus,'type') eq 'send') and ($mixer->{IOs}->val($bus,'return') eq $channel) );
# 		}
# 		#create channels_ai	
# 		$line .= $mixer->{IOs}->val($channel,'name') . "_to_" . $mixer->{IOs}->val($bus,'name') . ",";
# 	}
# 	#remove last ,
# 	chop($line);
# 	#finish line
# 	$line .= " -f:f32_le,2,48000 -i:loop," . $mixer->{IOs}->val($channel,'name');
# 	#add the line to the list
# 	push(@channels_ai,$line);
# 	$line = "-a:";
# }
# #foreach valid bus
# foreach my $bus (@valid_output_sections) {
# 	#foreach valid channel
# 	foreach my $channel (@valid_input_sections) {
# 		#ignore send bus to himlmixer
# 		if ($mixer->{IOs}->val($bus,'return')) { #prevent display of "Use of uninitialized value in string eq at"
# 			next if (($mixer->{IOs}->val($bus,'type') eq 'send') and ($mixer->{IOs}->val($bus,'return') eq $channel) );
# 		}
# 		#create channels_ao
# 		my $line = "-a:" . $mixer->{IOs}->val($channel,'name') . "_to_" . $mixer->{IOs}->val($bus,'name') . " -f:f32_le,2,48000 -o:jack,,to_bus_" . $mixer->{IOs}->val($bus,'name');
# 		#get default values
# 		my @def_dump = MidiCC::Get_defaults("st_panvol");
# 		#add pan/volume control
# 		$line .= " -pn:st_panvol" . $def_dump[1] if $def_dump[0];
# 		if ($create_midi_CC) {
# 			#ajouter les contrôleurs midi
# 			my $path = "/$eca_mixer/outputs/" . $mixer->{IOs}->val($bus,'name') . "/channel/" . $mixer->{IOs}->val($channel,'name') . "/panvol";
# 			my @CC_dump = MidiCC::Generate_km("st_panvol",$path);
# 			#status is in first parameter, km info is in second parameter
# 			$line .= $CC_dump[1] if $CC_dump[0];
# 		}
# 		#add the line to the list
# 		push(@channels_ao,$line);
# 	}
# 	#ajouter la règle de plumbing
# 	for my $i (1..2) {
# 		my $plumbin = "$eca_mixer:to_bus_" . $mixer->{IOs}->val($bus,'name') . "_.*[13579]\$" if ($i==1);
# 		$plumbin = "$eca_mixer:to_bus_" . $mixer->{IOs}->val($bus,'name') . "_.*[02468]\$" if ($i==2);
# 		my $plumbout = "$eca_mixer:bus_";
# 		$plumbout .= "send_" if ($mixer->{IOs}->val($bus,'type') eq 'send');
# 		$plumbout .= $mixer->{IOs}->val($bus,'name') . "_$i";
# 		$plumbing->Add("(connect \"$plumbin\" \"$plumbout\")") if $plumbin;
# 	}
# }
# if ($debug) {
# 	print "\nCHANNELS ROUTING CHAINS\nchannels_ai\n";
# 	print Dumper (@channels_ai);
# 	print "channels_ao\n";
# 	print Dumper (@channels_ao);
# }
# #----------------------------------------------------------------
# # -- BUS SENDS --
# $plumbing->Add(";buses");
# foreach my $bus (@valid_output_sections) {
# 	#outputbus_ai
# 	my $line = "-a:bus_";
# 	$line .= "send_" if ($mixer->{IOs}->val($bus,'type') eq 'send');
# 	$line .= $mixer->{IOs}->val($bus,'name');
# 	$line .= " -f:f32_le,2,48000 -i:jack,,bus_";
# 	$line .= "send_" if ($mixer->{IOs}->val($bus,'type') eq 'send');
# 	$line .= $mixer->{IOs}->val($bus,'name');
# 	#add volume control
# 	#get default values
# 	my @def_dump = MidiCC::Get_defaults("st_panvol");
# 	$line .= " -pn:st_panvol" . $def_dump[1] if $def_dump[0];
# 	if ($create_midi_CC) {
# 		#ajouter les contrôleurs midi
# 		my $path = "/$eca_mixer/outputs/" . $mixer->{IOs}->val($bus,'name') . "/panvol";
# 		my @CC_dump = MidiCC::Generate_km("st_panvol",$path);
# 		#status is in first parameter, km info is in second parameter
# 		$line .= $CC_dump[1] if $CC_dump[0];
# 	}	
# 	#add bus inserts
# 	if ( $mixer->{IOs}->val($bus,'insert') ) {
# 		#verify how many inserts are defined
# 		my @inserts = split(",", $mixer->{IOs}->val($bus,'insert') );
# 		foreach my $insert ( @inserts ) {
# 			# TODO : split on | for parralel effects ?
# 			#print "one effect here : $insert\n";
# 			#get default values
# 			my @def_dump = MidiCC::Get_defaults($insert);
# 			$line .= " -pn:$insert" . $def_dump[1] if $def_dump[0];
# 			if ($create_midi_CC) {
# 				#ajouter les contrôleurs midi
# 				my $path = "/$eca_mixer/outputs/" . $mixer->{IOs}->val($bus,'name') . "/$insert";
# 				my @CC_dump = MidiCC::Generate_km($insert,$path);
# 				#status is in first parameter, km info is in second parameter
# 				$line .= $CC_dump[1] if $CC_dump[0];
# 			}
# 		}
# 	}
# 	#add the line to the list
# 	push(@outputbus_ai,$line);
# 	#outputbus_ao
# 	$line = "-a:bus_";
# 	$line .= "send_" if ($mixer->{IOs}->val($bus,'type') eq 'send');
# 	$line .= $mixer->{IOs}->val($bus,'name');
# 	$line .= " -f:f32_le,2,48000 -o:jack,,";
# 	$line .= $mixer->{IOs}->val($bus,'name');
# 	$line .= "_out";
# 	#add the line to the list
# 	push(@outputbus_ao,$line);
# 	#ajouter la règle de plumbing
# 	for my $i (1..2) {
# 		my $plumbin = "$eca_mixer:" . $mixer->{IOs}->val($bus,'name') . "_out_$i";
# 		my $plumbout = $mixer->{IOs}->val($bus,"hardware_output_$i");
# 		$plumbing->Add("(connect \"$plumbin\" \"$plumbout\")") if $plumbout;
# 	}
# }
# if ($debug) {
# 	print "\nBUS OUTPUTS CHAINS\noutputbus_ai\n";
# 	print Dumper (@outputbus_ai);
# 	print "outputbus_ao\n";
# 	print Dumper (@outputbus_ao);
# }
# #----------------------------------------------------------------
# # --- Création du fichier ecs ecasound ---
# open FILE, ">$files_folder/$eca_mixer.ecs" or die $!;
# print FILE "#General\n";
# print FILE "$ecasound_header\n";
# print FILE "\n#INPUTS\n";
# print FILE "$_\n" for @inputs_ai;
# print FILE "\n";
# print FILE "$_\n" for @inputs_ao;
# print FILE "\n#CHANNELS ROUTING\n";
# print FILE "$_\n" for @channels_ai;
# print FILE "\n";
# print FILE "$_\n" for @channels_ao;
# print FILE "\n#BUS OUTPUTS\n";
# print FILE "$_\n" for @outputbus_ai;
# print FILE "\n";
# print FILE "$_\n" for @outputbus_ao;
# close FILE;
# print "\necs file successfully created\n";

sub verify {
	#check if chainsetup file is valid
	my $ecaecs = shift;
	unless ($ecaecs->{status} eq "chains") {
		warn "cannot verify an ecs file not containing chains\n";
		return;
	}
	#open it with ecasound and check return code
	
	$ecaecs->{status} = "verified";
}

1;