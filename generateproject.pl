#!/usr/bin/perl
use strict;
use warnings;

require ("modules/MidiCC.pm");

#----------------------------------------------------------------
# This script will create a main mixer ecs file for ecasound based on the information contained in ini files
# It will unconditionnaly overwrite any previoulsy existing ecs file with the same name.
#----------------------------------------------------------------
my $debug = 0;

use Data::Dumper;
use Config::IniFiles;

#------------------------OPTIONS-----------------------------------
# TODO move this options to grab project.ini options

#-----------------------PROJECT INI---------------------------------
#project file
my $ini_project = new Config::IniFiles -file => "project.ini"; # -allowempty => 1;
die "reading project ini file failed\n" until $ini_project;

#folder where to find the ini files
my $config_folder = $ini_project->val('project','configfolder');

#-------------------------I/O INI------------------------------------
#open input file
my $ini_inputs = new Config::IniFiles -file => "$config_folder/inputs.ini"; # -allowempty => 1;
die "reading inputs ini file failed\n" until $ini_inputs;

#open output file
my $ini_outputs = new Config::IniFiles -file => "$config_folder/outputs.ini"; # -allowempty => 1;
die "reading outputs ini file failed\n" until $ini_outputs;

#open submixes files
my @ini_submixes;
my $directory = "config";
opendir(DIR, $directory);
foreach my $subfile (readdir(DIR)) {
   	push (@ini_submixes, $subfile ) if ($subfile =~ /^submix_.*/ );
}
closedir(DIR);

#-------------------------Ecasound------------------------------------
die "Oops no audio ? what do you want to do ?\n" if ($ini_project->val('ecasound','enable') eq 0);
#check for audio options
my $create_midi_CC = $ini_project->val('ecasound','generatekm'); #enable/disable midiCC control with -km switch
my $eca_mixer = $ini_project->val('ecasound','name'); #name for the main input/output mixer
#build ecasound header
#my @ecasound_header = ("-b:128 -r:50 -z:nodb -z:nointbuf -n:\"$eca_mixer\" -X -z:noxruns -z:mixmode,avg -G:jack,$eca_mixer,notransport -Md:alsaseq,16:0");
my $ecasound_header;
$ecasound_header .= "-b:".$ini_project->val('ecasound','buffersize') if $ini_project->val('ecasound','buffersize');
$ecasound_header .= " -r:".$ini_project->val('ecasound','realtime') if $ini_project->val('ecasound','realtime');
my @zoptions = split(",",$ini_project->val('ecasound','z'));
foreach (@zoptions) {
	$ecasound_header .= " -z:".$_;
}
$ecasound_header .= " -n:\"$eca_mixer\"";
$ecasound_header .= " -z:mixmode,".$ini_project->val('ecasound','mixmode') if $ini_project->val('ecasound','mixmode');
$ecasound_header .= " -G:jack,$eca_mixer,notransport";
$ecasound_header .= " -Md:".$ini_project->val('ecasound','midi') if $ini_project->val('ecasound','midi');

#create/reset the midipath file
open FILE, ">midistate.csv" or die $!;
print FILE "path,value,min,max,CC,channel\n";
close FILE;

#-------------------------Plumbing------------------------------------
my $do_plumbing = $ini_project->val('jack.plumbing','enable');
#create/reset the jack.plumbing file
open FILE, ">jack.plumbing" or die $!;
close FILE;

#----------------------------------------------------------------
#
# === variables contenant les lignes � ins�rer dans le fichier mixer principal ecs ===
#
my @valid_input_sections; #liste des input sections valides (connectables)
my @valid_output_sections; #liste des output sections valides (connectables)
my @inputs_ai; #liste des ai ecasound
my @inputs_ao; #liste des ao ecasound
my @channels_ai; #liste des ai ecasound
my @channels_ao; #liste des ao ecasound
my @outputbus_ai;
my @outputbus_ao;
 
#----------------------------------------------------------------
#
# === G�n�ration des lignes � ins�rer ===

#----------------------------------------------------------------
# -- CHANNELS audio inputs --
my @input_sections = $ini_inputs->Sections;
print "\nFound " . (scalar @input_sections) . " input definitions in ini file\n";
#initialisation du fichier plumbing
&add_plumbing(";\n;audio input channels (to $eca_mixer inputs)");
#pour chaque entr�e d�finie dans le fichier ini, construction de la ligne d'input
while (my $section = shift @input_sections) {
	#si entr�e invalide, suivante
	next until ( $ini_inputs->val($section,'status') eq 'active' );
	next until ( $ini_inputs->val($section,'type') eq 'audio' ) or ( $ini_inputs->val($section,'type') eq 'return' ) or ( $ini_inputs->val($section,'type') eq 'submix' );
	#r�cup�rer le num�ro de la section
	my $number = substr $section, -2, 2;
	my $line = "-a:$number ";
	#si piste mono
	if ( $ini_inputs->val($section,'channels') eq 1 ) {
		$line .= "-f:f32_le,1,48000 -i:jack,,";
		#r�cup�rer le nom de la piste
		die "must have a track name\n" until ( $ini_inputs->val($section,'name') );
		$line .= $ini_inputs->val($section,'name');
		#get default values
		my @def_dump = MidiCC::get_defaults("mono_panvol");
		#ajouter mono_panvol (-erc:1,2 -epp -eadb)
		$line .= " -pn:mono_panvol" . $def_dump[1] if $def_dump[0];
		#ajouter les contr�leurs midi
		if ($create_midi_CC) {
			my $path = "/$eca_mixer/inputs/" . $ini_inputs->val($section,'name') . "/panvol";
			my @CC_dump = MidiCC::generate_km("mono_panvol",$path);
			#status is in first parameter, km info is in second parameter
			$line .= $CC_dump[1] if $CC_dump[0];
		}
		#ajouter la r�gle de plumbing
		my $plumbin = $ini_inputs->val($section,'hardware_input_1');
		my $plumbout = "$eca_mixer:" . $ini_inputs->val($section,'name') . "_1";
		&add_plumbing("(connect \"$plumbin\" \"$plumbout\")") if $plumbin;
	}
	#sinon, piste st�r�o par d�faut
	elsif ( $ini_inputs->val($section,'channels') eq 2 ) {
		$line .= "-f:f32_le,2,48000 -i:jack,,";
		#r�cup�rer le nom de la piste
		die "must have a track name\n" until ( $ini_inputs->val($section,'name') );
		$line .= $ini_inputs->val($section,'name');
		#get default values
		my @def_dump = MidiCC::get_defaults("st_panvol");
		$line .= " -pn:st_panvol" . $def_dump[1] if $def_dump[0];
		if ($create_midi_CC) {
			#ajouter les contr�leurs midi
			my $path = "/$eca_mixer/inputs/" . $ini_inputs->val($section,'name') . "/panvol";
			my @CC_dump = MidiCC::generate_km("st_panvol",$path);
			#status is in first parameter, km info is in second parameter
			$line .= $CC_dump[1] if $CC_dump[0];
		}
		#ajouter la r�gle de plumbing
		for my $i (1..2) {
			if (( $ini_inputs->val($section,'type') eq 'audio' ) or ( $ini_inputs->val($section,'type') eq 'return' )) {
				my $plumbin = $ini_inputs->val($section,"hardware_input_$i");
				my $plumbout = "$eca_mixer:" . $ini_inputs->val($section,'name') . "_$i";
				&add_plumbing("(connect \"$plumbin\" \"$plumbout\")") if $plumbin;
			}
			elsif ( $ini_inputs->val($section,'type') eq 'submix' ) {
				&add_plumbing(";submix");
				my $plumbin = "submix_" . $ini_inputs->val($section,'name') . ":out_(.*)";
				my $plumbout = "$eca_mixer:submix_" . $ini_inputs->val($section,'name') . "_\\1";
				&add_plumbing("(connect \"$plumbin\" \"$plumbout\")");
				last;
			}
		}
	}
	#ajouter channel inserts
	if ( $ini_inputs->val($section,'insert') ) {
		#verify how many inserts are defined
		my @inserts = split(",", $ini_inputs->val($section,'insert') );
		foreach my $insert ( @inserts ) {
			# TODO : split on | for parralel effects ?
			#print "one effect here : $insert\n";
			#get default values
			my @def_dump = MidiCC::get_defaults($insert);
			$line .= " -pn:$insert" . $def_dump[1] if $def_dump[0];
			if ($create_midi_CC) {
				#ajouter les contr�leurs midi
				my $path = "/$eca_mixer/inputs/" . $ini_inputs->val($section,'name') . "/$insert";
				my @CC_dump = MidiCC::generate_km($insert,$path);
				#status is in first parameter, km info is in second parameter
				$line .= $CC_dump[1] if $CC_dump[0];
			}
		}
	}
	#section valide
	 #ajoute � la liste des sections valides
	push(@valid_input_sections,$section);
	 #ajoute la ligne � la liste des ai
	push(@inputs_ai,$line);
	 #cr�e la sorite loop
	$line = "-a:$number -f:f32_le,2,48000 -o:loop," . $ini_inputs->val($section,'name');
	push(@inputs_ao,$line);
}
print "\nFound " . (scalar @valid_input_sections) . " valid audio input definitions\n";
if ($debug) {
	print "\nINPUT CHAINS\ninputs_ai\n";
	print Dumper (@inputs_ai);
	print "inputs_ao\n";
	print Dumper (@inputs_ao);
}
#----------------------------------------------------------------
# -- CHANNELS routing to bus sends --
&add_plumbing(";channels routes");
my @output_sections = $ini_outputs->Sections;
print "\nFound " . (scalar @output_sections) . " output definitions in ini file\n";
#pour chaque entr�e d�finie dans le fichier ini
#v�rification de la validit� de la sortie
while (my $section = shift @output_sections) {
	#si entr�e invalide, suivante
	next until ( $ini_outputs->val($section,'status') eq 'active' );
	next until ( $ini_outputs->val($section,'type') eq 'bus' ) or ( $ini_outputs->val($section,'type') eq 'send' );
	die "must have a track name\n" until ( $ini_outputs->val($section,'name') );
	#stocker la section valide
	push(@valid_output_sections, $section );
}
print "\nFound " . (scalar @valid_output_sections) . " valid audio output definitions\n";
#construction des chains
#foreach valid channel
my $line = "-a:";
foreach my $channel (@valid_input_sections) {
	#foreach valid bus
	foreach my $bus (@valid_output_sections) {
	#ignore send bus to himself
		next if (($ini_outputs->val($bus,'type') eq 'send') and  ($ini_outputs->val($bus,'return') eq $channel) );
	#create channels_ai	
	$line .= $ini_inputs->val($channel,'name') . "_to_" . $ini_outputs->val($bus,'name') . ",";
	}
	#remove last ,
	chop($line);
	#finish line
	$line .= " -f:f32_le,2,48000 -i:loop," . $ini_inputs->val($channel,'name');
	#add the line to the list
	push(@channels_ai,$line);
	$line = "-a:";
}
#foreach valid bus
foreach my $bus (@valid_output_sections) {
	#foreach valid channel
	foreach my $channel (@valid_input_sections) {
		#ignore send bus to himlself
		next if (($ini_outputs->val($bus,'type') eq 'send') and  ($ini_outputs->val($bus,'return') eq $channel) );
		#create channels_ao
		my $line = "-a:" . $ini_inputs->val($channel,'name') . "_to_" . $ini_outputs->val($bus,'name') . " -f:f32_le,2,48000 -o:jack,,to_bus_" . $ini_outputs->val($bus,'name');
		#get default values
		my @def_dump = MidiCC::get_defaults("st_panvol");
		#add pan/volume control
		$line .= " -pn:st_panvol" . $def_dump[1] if $def_dump[0];
		if ($create_midi_CC) {
			#ajouter les contr�leurs midi
			my $path = "/$eca_mixer/outputs/" . $ini_outputs->val($bus,'name') . "/from/" . $ini_inputs->val($channel,'name') . "/panvol";
			my @CC_dump = MidiCC::generate_km("st_panvol",$path);
			#status is in first parameter, km info is in second parameter
			$line .= $CC_dump[1] if $CC_dump[0];
		}
		#add the line to the list
		push(@channels_ao,$line);
	}
	#ajouter la r�gle de plumbing
	for my $i (1..2) {
		my $plumbin = "$eca_mixer:to_bus_" . $ini_outputs->val($bus,'name') . "_.*[13579]\$" if ($i==1);
		$plumbin = "$eca_mixer:to_bus_" . $ini_outputs->val($bus,'name') . "_.*[02468]\$" if ($i==2);
		my $plumbout = "$eca_mixer:bus_" . $ini_outputs->val($bus,'name') . "_$i";
		&add_plumbing("(connect \"$plumbin\" \"$plumbout\")") if $plumbin;
	}
}
if ($debug) {
	print "\nCHANNELS ROUTING CHAINS\nchannels_ai\n";
	print Dumper (@channels_ai);
	print "channels_ao\n";
	print Dumper (@channels_ao);
}
#----------------------------------------------------------------
# -- BUS SENDS --
&add_plumbing(";buses");
foreach my $bus (@valid_output_sections) {
	#outputbus_ai
	my $line = "-a:bus_";
	$line .= "send_" if ($ini_outputs->val($bus,'type') eq 'send');
	$line .= $ini_outputs->val($bus,'name');
	$line .= " -f:f32_le,2,48000 -i:jack,,bus_";
	$line .= "send_" if ($ini_outputs->val($bus,'type') eq 'send');
	$line .= $ini_outputs->val($bus,'name');
	#add volume control
	#get default values
	my @def_dump = MidiCC::get_defaults("st_panvol");
	$line .= " -pn:st_panvol" . $def_dump[1] if $def_dump[0];
	if ($create_midi_CC) {
		#ajouter les contr�leurs midi
		my $path = "/$eca_mixer/outputs/" . $ini_outputs->val($bus,'name') . "/panvol";
		my @CC_dump = MidiCC::generate_km("st_panvol",$path);
		#status is in first parameter, km info is in second parameter
		$line .= $CC_dump[1] if $CC_dump[0];
	}	
	#add bus inserts
	if ( $ini_outputs->val($bus,'insert') ) {
		#verify how many inserts are defined
		my @inserts = split(",", $ini_outputs->val($bus,'insert') );
		foreach my $insert ( @inserts ) {
			# TODO : split on | for parralel effects ?
			#print "one effect here : $insert\n";
			#get default values
			my @def_dump = MidiCC::get_defaults($insert);
			$line .= " -pn:$insert" . $def_dump[1] if $def_dump[0];
			if ($create_midi_CC) {
				#ajouter les contr�leurs midi
				my $path = "/$eca_mixer/inputs/" . $ini_outputs->val($bus,'name') . "/$insert";
				my @CC_dump = MidiCC::generate_km($insert,$path);
				#status is in first parameter, km info is in second parameter
				$line .= $CC_dump[1] if $CC_dump[0];
			}
		}
	}
	#add the line to the list
	push(@outputbus_ai,$line);
	#outputbus_ao
	$line = "-a:bus_";
	$line .= "send_" if ($ini_outputs->val($bus,'type') eq 'send');
	$line .= $ini_outputs->val($bus,'name');
	$line .= " -f:f32_le,2,48000 -o:jack,,";
	$line .= $ini_outputs->val($bus,'name');
	$line .= "_out";
	#add the line to the list
	push(@outputbus_ao,$line);
	#ajouter la r�gle de plumbing
	for my $i (1..2) {
		my $plumbin = "$eca_mixer:" . $ini_outputs->val($bus,'name') . "_out_$i";
		my $plumbout = $ini_outputs->val($bus,"hardware_output_$i");
		&add_plumbing("(connect \"$plumbin\" \"$plumbout\")") if $plumbout;
	}
}
if ($debug) {
	print "\nBUS OUTPUTS CHAINS\noutputbus_ai\n";
	print Dumper (@outputbus_ai);
	print "outputbus_ao\n";
	print Dumper (@outputbus_ao);
}
#----------------------------------------------------------------
# --- Cr�ation du fichier ecs ecasound ---
open FILE, ">$eca_mixer.ecs" or die $!;
print FILE "#General\n";
print FILE "$ecasound_header\n";
print FILE "\n#INPUTS\n";
print FILE "$_\n" for @inputs_ai;
print FILE "\n";
print FILE "$_\n" for @inputs_ao;
print FILE "\n#CHANNELS ROUTING\n";
print FILE "$_\n" for @channels_ai;
print FILE "\n";
print FILE "$_\n" for @channels_ao;
print FILE "\n#BUS OUTPUTS\n";
print FILE "$_\n" for @outputbus_ai;
print FILE "\n";
print FILE "$_\n" for @outputbus_ao;
close FILE;
print "ecs file successfully created\n";

#----------------------------------------------------------------
#----------------------------------------------------------------
#
# === Cr�ation des fichiers ecs submixes ===
#

foreach my $submix_ini (@ini_submixes) {
	my $ini_submix = new Config::IniFiles -file => "$config_folder/$submix_ini";
	die "reading submix ini file failed\n" until $ini_submix;
	#grab submix name
	#my $submix_name = $1 if $submix_ini =~  /^(.*).ini/ ;
	my $submix_name = substr $submix_ini, 0, -4 ;
	#print "---$submix_name---";

	my @submix_tracks; #liste des pistes i/o
	@input_sections = $ini_submix->Sections;
	print "\nFound " . (scalar @input_sections) . " submix track definitions in ini file\n";
	#pour chaque entr�e d�finie dans le fichier ini
	#construction de la ligne d'input
	while (my $section = shift @input_sections) {
		my $found_output = 0;
		my $line;
		#r�cup�rer le num�ro de la section
		my $number = substr $section, -2, 2;
		#check if input or output
		if ( $ini_submix->val($section,'type') eq 'input' ) {
			#si piste mono, ajouter mono_panvol (-pn:mono2stereo -epp:50)
			if ( $ini_submix->val($section,'channels') eq 1 ) {
				$line = "-a:$number -f:f32_le,1,48000 -i:jack,,";
				#r�cup�rer le nom de la piste
				die "must have a track name\n" until ( $ini_submix->val($section,'name') );
				#TODO check for name uniqueness
				$line .= $ini_submix->val($section,'name');
				#get default values
				my @def_dump = MidiCC::get_defaults("mono_panvol");
				$line .= " -pn:mono_panvol" . $def_dump[1] if $def_dump[0];
				if ($create_midi_CC) {
					#ajouter les contr�leurs midi
					my $path = "/$eca_mixer/inputs/" . $ini_submix->val($section,'name') . "/panvol";
					my @CC_dump = MidiCC::generate_km("mono_panvol",$path);
					#status is in first parameter, km info is in second parameter
					$line .= $CC_dump[1] if $CC_dump[0];
				}
			}
			#sinon, piste st�r�o par d�faut
			elsif ( $ini_submix->val($section,'channels') eq 2 ) {
				$line = "-a:$number -f:f32_le,2,48000 -i:jack,,";
				#r�cup�rer le nom de la piste
				die "must have a track name\n" until ( $ini_submix->val($section,'name') );
				#TODO check for name uniqueness
				$line .= $ini_submix->val($section,'name');
				#get default values
				my @def_dump = MidiCC::get_defaults("st_panvol");
				$line .= " -pn:st_panvol" . $def_dump[1] if $def_dump[0];
				if ($create_midi_CC) {
					#ajouter les contr�leurs midi
					my $path = "/$eca_mixer/inputs/" . $ini_submix->val($section,'name') . "/panvol";
					my @CC_dump = MidiCC::generate_km("st_panvol",$path);
					#status is in first parameter, km info is in second parameter
					$line .= $CC_dump[1] if $CC_dump[0];
				}	
			}
			#ajouter channel inserts (seulement pour les inputs, TODO for outputs)
			if (( $ini_submix->val($section,'insert') ) && ($ini_submix->val($section,'type') eq 'input') ) {
				#verify how many inserts are defined
				my @inserts = split(",", $ini_submix->val($section,'insert') );
				foreach my $insert ( @inserts ) {
					# TODO : split on | for parralel effects ?
					#print "one effect here : $insert\n";
					#get default values
					my @def_dump = MidiCC::get_defaults($insert);
					$line .= " -pn:$insert" . $def_dump[1] if $def_dump[0];
					if ($create_midi_CC) {
						#ajouter les contr�leurs midi
						my $path = "/$eca_mixer/inputs/" . $ini_submix->val($section,'name') . "/$insert";
						my @CC_dump = MidiCC::generate_km($insert,$path);
						#status is in first parameter, km info is in second parameter
						$line .= $CC_dump[1] if $CC_dump[0];
					}
				}
			}
		}
		elsif ( $ini_submix->val($section,'type') eq 'output' ) {
			die "submix output must be stereo" if ($ini_submix->val($section,'channels') ne 2);
			$line = "-a:all -f:f32_le,2,48000 -o:jack,,";
			#r�cup�rer le nom de la piste
			die "must have a track name\n" until ( $ini_submix->val($section,'name') );
			#TODO check for uniqueness
			$line .= $ini_submix->val($section,'name') . "_out";
			$found_output = 1;
		}
		elsif ($found_output == 1) {
			die "only one outbut bus should exist\n";
		}
		else {
			die "unknown track type\n";
		}	
		push(@submix_tracks,$line);
	}

	print "\nFound " . (scalar @submix_tracks) . " valid submix track definitions in $submix_ini\n";
	if ($debug) {
		print "\nSUBMIX CHAINS\n";
		print Dumper (@submix_tracks);
	}
	#----------------------------------------------------------------
	# --- Cr�ation du fichier ecs ecasound ---
	$ecasound_header = "-b:128 -r:50 -z:nodb -z:nointbuf -n:\"$submix_name\" -X -z:noxruns -z:mixmode,avg -G:jack,$submix_name,notransport -Md:alsaseq,16:0";

	open FILE, ">$submix_name.ecs" or die $!;
	print FILE "#General\n";
	print FILE "$ecasound_header\n";
	print FILE "\n#CHAINS\n";
	print FILE "$_\n" for @submix_tracks;
	print FILE "\n";
	close FILE;
	print "ecs file successfully created\n";
}

#----------------------------------------------------------------
#----------------------------------------------------------------
#
# === mise � jour du fichier jack.plumbing ===

sub add_plumbing () {
	if ($do_plumbing){ 
		my $param = shift;
		open FILE, ">>jack.plumbing" or die $!;
		print FILE $param;
		print FILE "\n";
		close FILE;
	}	
}
# voir comment/quand d�finir le branchement de pistes syst�me (players,messages)

#----------------------------------------------------------------
#
# === Cr�ation du fichier pour le pont midi/OSC ===
#
# using a hash to store the generated midis
# http://stackoverflow.com/questions/13588129/write-to-a-csv-file-from-a-hash-perl