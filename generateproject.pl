#!/usr/bin/perl
use strict;
use warnings;

use lib '/home/seijitsu/astrux/modules';
require ("MidiCC.pm");
require ("Bridge.pm");
require ("Plumbing.pm");

#----------------------------------------------------------------
# This script will create a main mixer ecs file for ecasound based on the information contained in ini files
# It will unconditionnaly overwrite any previoulsy existing ecs file with the same name.
# it is to be launched in the project folder root.
#----------------------------------------------------------------
my $debug = 0;

use Data::Dumper;
use Config::IniFiles;
use Audio::SndFile;

#-----------------------PROJECT INI---------------------------------
#project file
my $ini_project = new Config::IniFiles -file => "project.ini";
die "reading project ini file failed\n" until $ini_project;

#folder where to find the ini files
my $config_folder = $ini_project->val('project','configfolder');
#folder where to store generated files
my $files_folder = $ini_project->val('project','filesfolder');

#------------------------FILES-----------------------------------
#create/reset the oscmidipath file
Bridge::Init_file();
#plumbing file;
my $plumbing = Plumbing->new();

#create/reset the players_cs file
open FILE, ">$files_folder/players_cs" or die $!;
close FILE;

#-------------------------I/O INI------------------------------------
#open input file
my $ini_inputs = new Config::IniFiles -file => "$config_folder/inputs.ini";
die "reading inputs ini file failed\n" until $ini_inputs;

#open output file
my $ini_outputs = new Config::IniFiles -file => "$config_folder/outputs.ini";
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
my $ecasound_header;
&build_ecasound_header($eca_mixer,'nosync');

sub build_ecasound_header {
	my $temp = shift;
	my $synchro = shift;
	$ecasound_header = "-b:".$ini_project->val('ecasound','buffersize') if $ini_project->val('ecasound','buffersize');
	$ecasound_header .= " -r:".$ini_project->val('ecasound','realtime') if $ini_project->val('ecasound','realtime');
	my @zoptions = split(",",$ini_project->val('ecasound','z'));
	foreach (@zoptions) {
		$ecasound_header .= " -z:".$_;
	}
	$ecasound_header .= " -n:\"$temp\"";
	$ecasound_header .= " -z:mixmode,".$ini_project->val('ecasound','mixmode') if $ini_project->val('ecasound','mixmode');
	$ecasound_header .= " -G:jack,$temp,notransport" if ($synchro eq "nosync");
	$ecasound_header .= " -G:jack,$temp,sendrecv" if ($synchro eq "sync");
	$ecasound_header .= " -Md:".$ini_project->val('ecasound','midi') if $ini_project->val('ecasound','midi');
}

#----------------------------------------------------------------
#
# === variables contenant les lignes à insérer dans le fichier mixer principal ecs ===
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
print "\n---MAIN MIXER---\n";
#----------------------------------------------------------------
#
# === I/O Channels, Buses, Sends ===

#----------------------------------------------------------------
# -- CHANNELS audio inputs --
my @input_sections = $ini_inputs->Sections;
print "\nFound " . (scalar @input_sections) . " input definitions in ini file\n";
#initialisation du fichier plumbing
&add_plumbing(";\n;audio input channels (to $eca_mixer inputs)");
#pour chaque entrée définie dans le fichier ini, construction de la ligne d'input
while (my $section = shift @input_sections) {
	#si entrée invalide, suivante
	next unless ( $ini_inputs->val($section,'status') eq 'active' );
	next unless ( $ini_inputs->val($section,'type') eq 'audio' ) 
		or ( $ini_inputs->val($section,'type') eq 'return' ) 
		or ( $ini_inputs->val($section,'type') eq 'submix' )
		or ( $ini_inputs->val($section,'type') eq 'player' );
	#récupérer le numéro de la section
	my $number = substr $section, -2, 2;
	my $line = "-a:$number ";
	#si piste mono
	if ( $ini_inputs->val($section,'channels') eq 1 ) {
		$line .= "-f:f32_le,1,48000 -i:jack,,";
		#récupérer le nom de la piste
		die "must have a track name\n" until ( $ini_inputs->val($section,'name') );
		$line .= $ini_inputs->val($section,'name');
		#get default values
		my @def_dump = MidiCC::Get_defaults("mono_panvol");
		#ajouter mono_panvol (-erc:1,2 -epp -eadb)
		$line .= " -pn:mono_panvol" . $def_dump[1] if $def_dump[0];
		#ajouter les contrôleurs midi
		if ($create_midi_CC) {
			my $path = "/$eca_mixer/inputs/" . $ini_inputs->val($section,'name') . "/panvol";
			my @CC_dump = MidiCC::Generate_km("mono_panvol",$path);
			#status is in first parameter, km info is in second parameter
			$line .= $CC_dump[1] if $CC_dump[0];
		}
		#ajouter la règle de plumbing
		my $plumbin = $ini_inputs->val($section,'hardware_input_1');
		my $plumbout = "$eca_mixer:" . $ini_inputs->val($section,'name') . "_1";
		&add_plumbing("(connect \"$plumbin\" \"$plumbout\")") if $plumbin;
	}
	#sinon, piste stéréo
	elsif ( $ini_inputs->val($section,'channels') eq 2 ) {
		$line .= "-f:f32_le,2,48000 -i:jack,,";
		#récupérer le nom de la piste
		die "must have a track name\n" until ( $ini_inputs->val($section,'name') );
		$line .= $ini_inputs->val($section,'name');
		#get default values
		my @def_dump = MidiCC::Get_defaults("st_panvol");
		$line .= " -pn:st_panvol" . $def_dump[1] if $def_dump[0];
		if ($create_midi_CC) {
			#ajouter les contrôleurs midi
			my $path = "/$eca_mixer/inputs/" . $ini_inputs->val($section,'name') . "/panvol";
			my @CC_dump = MidiCC::Generate_km("st_panvol",$path);
			#status is in first parameter, km info is in second parameter
			$line .= $CC_dump[1] if $CC_dump[0];
		}
		#ajouter la règle de plumbing
		#pour une piste player
		if ( $ini_inputs->val($section,'type') eq 'player' ) {
			for my $i (1..2) {
				#grab player number
				my $nb = substr ($ini_inputs->val($section,'name'), -1, 1);
				#deal with stereo pair
				my $plumbin = "player:out_$nb" . "_.*[13579]\$" if ($i==1);
				$plumbin = "player:out_$nb" . "_.*[02468]\$" if ($i==2);
				my $plumbout = "$eca_mixer:";
				$plumbout .= $ini_inputs->val($section,'name') . "_$i";
				&add_plumbing("(connect \"$plumbin\" \"$plumbout\")") if $plumbin;
			}
		}
		#pour une piste submix
		elsif ( $ini_inputs->val($section,'type') eq 'submix' ) {
			my $plumbin = "submix_" . $ini_inputs->val($section,'name') . ":" . $ini_inputs->val($section,'name') . "_out_(.*)";
			my $plumbout = "$eca_mixer:" . $ini_inputs->val($section,'name') . "_\\1";
			&add_plumbing("(connect \"$plumbin\" \"$plumbout\")") if $plumbin;
		}
		else { #pour une piste input,return
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
	}
	#ajouter channel inserts
	if ( $ini_inputs->val($section,'insert') ) {
		#verify how many inserts are defined
		my @inserts = split(",", $ini_inputs->val($section,'insert') );
		foreach my $insert ( @inserts ) {
			# TODO : split on | for parralel effects ?
			#print "one effect here : $insert\n";
			#get default values
			my @def_dump = MidiCC::Get_defaults($insert);
			$line .= " -pn:$insert" . $def_dump[1] if $def_dump[0];
			if ($create_midi_CC) {
				#ajouter les contrôleurs midi
				my $path = "/$eca_mixer/inputs/" . $ini_inputs->val($section,'name') . "/$insert";
				my @CC_dump = MidiCC::Generate_km($insert,$path);
				#status is in first parameter, km info is in second parameter
				$line .= $CC_dump[1] if $CC_dump[0];
			}
		}
	}
	#section valide
	 #ajoute à la liste des sections valides
	push(@valid_input_sections,$section);
	 #ajoute la ligne à la liste des ai
	push(@inputs_ai,$line);
	 #crée la sorite loop
	$line = "-a:$number -f:f32_le,2,48000 -o:loop," . $ini_inputs->val($section,'name');
	push(@inputs_ao,$line);
}
print "Found " . (scalar @valid_input_sections) . " valid audio input definitions\n";
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
#pour chaque entrée définie dans le fichier ini
#vérification de la validité de la sortie
while (my $section = shift @output_sections) {
	#si entrée invalide, suivante
	next until ( $ini_outputs->val($section,'status') eq 'active' );
	next until ( $ini_outputs->val($section,'type') eq 'bus' ) or ( $ini_outputs->val($section,'type') eq 'send' );
	die "must have a track name\n" until ( $ini_outputs->val($section,'name') );
	#stocker la section valide
	push(@valid_output_sections, $section );
}
print "Found " . (scalar @valid_output_sections) . " valid audio output definitions\n";
#construction des chains
#foreach valid channel
my $line = "-a:";
foreach my $channel (@valid_input_sections) {
	#foreach valid bus
	foreach my $bus (@valid_output_sections) {
		#ignore send bus to himself
		if ($ini_outputs->val($bus,'return')) { #prevent display of "Use of uninitialized value in string eq at"
			next if (($ini_outputs->val($bus,'type') eq 'send') and ($ini_outputs->val($bus,'return') eq $channel) );
		}
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
		if ($ini_outputs->val($bus,'return')) { #prevent display of "Use of uninitialized value in string eq at"
			next if (($ini_outputs->val($bus,'type') eq 'send') and ($ini_outputs->val($bus,'return') eq $channel) );
		}
		#create channels_ao
		my $line = "-a:" . $ini_inputs->val($channel,'name') . "_to_" . $ini_outputs->val($bus,'name') . " -f:f32_le,2,48000 -o:jack,,to_bus_" . $ini_outputs->val($bus,'name');
		#get default values
		my @def_dump = MidiCC::Get_defaults("st_panvol");
		#add pan/volume control
		$line .= " -pn:st_panvol" . $def_dump[1] if $def_dump[0];
		if ($create_midi_CC) {
			#ajouter les contrôleurs midi
			my $path = "/$eca_mixer/outputs/" . $ini_outputs->val($bus,'name') . "/channel/" . $ini_inputs->val($channel,'name') . "/panvol";
			my @CC_dump = MidiCC::Generate_km("st_panvol",$path);
			#status is in first parameter, km info is in second parameter
			$line .= $CC_dump[1] if $CC_dump[0];
		}
		#add the line to the list
		push(@channels_ao,$line);
	}
	#ajouter la règle de plumbing
	for my $i (1..2) {
		my $plumbin = "$eca_mixer:to_bus_" . $ini_outputs->val($bus,'name') . "_.*[13579]\$" if ($i==1);
		$plumbin = "$eca_mixer:to_bus_" . $ini_outputs->val($bus,'name') . "_.*[02468]\$" if ($i==2);
		my $plumbout = "$eca_mixer:bus_";
		$plumbout .= "send_" if ($ini_outputs->val($bus,'type') eq 'send');
		$plumbout .= $ini_outputs->val($bus,'name') . "_$i";
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
	my @def_dump = MidiCC::Get_defaults("st_panvol");
	$line .= " -pn:st_panvol" . $def_dump[1] if $def_dump[0];
	if ($create_midi_CC) {
		#ajouter les contrôleurs midi
		my $path = "/$eca_mixer/outputs/" . $ini_outputs->val($bus,'name') . "/panvol";
		my @CC_dump = MidiCC::Generate_km("st_panvol",$path);
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
			my @def_dump = MidiCC::Get_defaults($insert);
			$line .= " -pn:$insert" . $def_dump[1] if $def_dump[0];
			if ($create_midi_CC) {
				#ajouter les contrôleurs midi
				my $path = "/$eca_mixer/outputs/" . $ini_outputs->val($bus,'name') . "/$insert";
				my @CC_dump = MidiCC::Generate_km($insert,$path);
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
	#ajouter la règle de plumbing
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
# --- Création du fichier ecs ecasound ---
open FILE, ">$files_folder/$eca_mixer.ecs" or die $!;
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
print "\necs file successfully created\n";

#----------------------------------------------------------------
print "\n---SUBMIXES---\n";
#----------------------------------------------------------------
#
# === Création des fichiers ecs submixes ===
#

foreach my $submix_ini (@ini_submixes) {
	my $ini_submix = new Config::IniFiles -file => "$config_folder/$submix_ini";
	die "reading submix ini file failed\n" until $ini_submix;
	#grab submix name, truncate submix_ prefix, and .ini suffix
	my $submix_name = substr $submix_ini, 7, -4 ;

	my @submix_tracks; #liste des pistes i/o
	@input_sections = $ini_submix->Sections;
	print "\nFound " . (scalar @input_sections) . " submix track definitions in ini file\n";
	#pour chaque entrée définie dans le fichier ini, construction des lignes d'io
	while (my $section = shift @input_sections) {
		my $found_output = 0;
		my $line;
		#récupérer le numéro de la section
		my $number = substr $section, -2, 2;
		#check if input or output
		if ( $ini_submix->val($section,'type') eq 'input' ) {
			#si piste mono, ajouter mono_panvol (-pn:mono2stereo -epp:50)
			if ( $ini_submix->val($section,'channels') eq 1 ) {
				$line = "-a:$number -f:f32_le,1,48000 -i:jack,,";
				#récupérer le nom de la piste
				die "must have a track name\n" until ( $ini_submix->val($section,'name') );
				#TODO check for name uniqueness
				$line .= $ini_submix->val($section,'name');
				#get default values
				my @def_dump = MidiCC::Get_defaults("mono_panvol");
				$line .= " -pn:mono_panvol" . $def_dump[1] if $def_dump[0];
				if ($create_midi_CC) {
					#ajouter les contrôleurs midi
					my $path = "/$eca_mixer/submix/$submix_name/" . $ini_submix->val($section,'name') . "/panvol";
					my @CC_dump = MidiCC::Generate_km("mono_panvol",$path);
					#status is in first parameter, km info is in second parameter
					$line .= $CC_dump[1] if $CC_dump[0];
				}
			}
			#sinon, piste stéréo par défaut
			elsif ( $ini_submix->val($section,'channels') eq 2 ) {
				$line = "-a:$number -f:f32_le,2,48000 -i:jack,,";
				#récupérer le nom de la piste
				die "must have a track name\n" until ( $ini_submix->val($section,'name') );
				#TODO check for name uniqueness
				$line .= $ini_submix->val($section,'name');
				#get default values
				my @def_dump = MidiCC::Get_defaults("st_panvol");
				$line .= " -pn:st_panvol" . $def_dump[1] if $def_dump[0];
				if ($create_midi_CC) {
					#ajouter les contrôleurs midi
					my $path = "/$eca_mixer/submix/$submix_name/" . $ini_submix->val($section,'name') . "/panvol";
					my @CC_dump = MidiCC::Generate_km("st_panvol",$path);
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
					my @def_dump = MidiCC::Get_defaults($insert);
					$line .= " -pn:$insert" . $def_dump[1] if $def_dump[0];
					if ($create_midi_CC) {
						#ajouter les contrôleurs midi
						my $path = "/$eca_mixer/inputs/" . $ini_submix->val($section,'name') . "/$insert";
						my @CC_dump = MidiCC::Generate_km($insert,$path);
						#status is in first parameter, km info is in second parameter
						$line .= $CC_dump[1] if $CC_dump[0];
					}
				}
			}
		}
		elsif ( $ini_submix->val($section,'type') eq 'output' ) {
			die "submix output must be stereo" if ($ini_submix->val($section,'channels') ne 2);
			$line = "-a:all -f:f32_le,2,48000 -o:jack,,";
			#récupérer le nom de la piste
			die "must have a track name\n" until ( $ini_submix->val($section,'name') );
			#TODO check for uniqueness
			$line .= $ini_submix->val($section,'name') . "_out";
			$found_output = 1;
		}
		elsif ($found_output == 1) {
			die "only one outbut bus should exist\n";
		}
		else {
			die "unknown track type in submix file\n";
		}	
		push(@submix_tracks,$line);
	}

	print "Found " . (scalar @submix_tracks) . " valid submix track definitions in $submix_ini\n";
	if ($debug) {
		print "\nSUBMIX CHAINS\n";
		print Dumper (@submix_tracks);
	}
	#----------------------------------------------------------------
	# --- Création du fichier ecs ecasound ---
	#$ecasound_header = "-b:128 -r:50 -z:nodb -z:nointbuf -n:\"$submix_name\" -X -z:noxruns -z:mixmode,avg -G:jack,$submix_name,notransport -Md:alsaseq,16:0";
	&build_ecasound_header($submix_name,'nosync');
	open FILE, ">$files_folder/$submix_name.ecs" or die $!;
	print FILE "#General\n";
	print FILE "$ecasound_header\n";
	print FILE "\n#CHAINS\n";
	print FILE "$_\n" for @submix_tracks;
	print FILE "\n";
	close FILE;
	print "\necs file successfully created\n";
}

#----------------------------------------------------------------
print "\n---PLAYERS---\n";
#----------------------------------------------------------------
#
# === Création des fichiers ecs pour chaque chanson ===
#
my $basedir = $ini_project->val('project','basefolder');
#get the song folder names into an array
opendir (DIR,$basedir) or die "Can't open project directory : $basedir\n";
my @songfolderlist = grep { /^[0-9][0-9].*/ } readdir(DIR);
closedir DIR;
#verify if there is something to be done
my $numberofsongs = @songfolderlist;
die "No songs have been found, exiting\n" unless ($numberofsongs > 0);
#display the number of songs we found
print "\n" . $numberofsongs . " song folder found\n";

my @cs_list; #liste des chain setup player à charger au démarrage du projet
foreach my $folder(@songfolderlist) {
	my @audio_players; #liste des fichiers audio à lire
	#look for song.ini
	if (-e -r "$basedir/$folder/song.ini") {
		#song ini file
		my $ini_song = new Config::IniFiles -file => "$basedir/$folder/song.ini"; # -allowempty => 1;
		die "reading song ini file failed\n" unless $ini_song;
		#song name
		my $friendlysongname = $ini_song->val('global','friendly_name');
		print "  - $friendlysongname -\n";
		my @song_sections = $ini_song->Sections;
		while (my $section = shift @song_sections) {
			#on cherche les audio files
			next unless $section =~ /AUDIO/;
			#grab the track number
			my $number = substr $section, -2, 2;
			#verify if file to play is accessible
			my $filename = $ini_song->val($section,'filename');
			next unless -e -r "$basedir/$folder/$filename";
			#create ecasound input line
			my $line = "-a:$number -i:$basedir/$folder/$filename";
			#deal with mono/stereo, 
			my $f = Audio::SndFile->open("<","$basedir/$folder/$filename");
			if ( $f->channels == 1 ) {
				my @def_dump = MidiCC::Get_defaults("mono_panvol");
				#ajouter mono_panvol (-erc:1,2 -epp -eadb)
				$line .= " -pn:mono_panvol" . $def_dump[1] if $def_dump[0];
			}
			#don't deal with file format conversion; let ecasound do it well
			# TODO : midi CC for players tracks, generic ones ...
			#output line
			my $output = $ini_song->val($section,'output'); #sys_player ok
			if ( $output > $ini_project->val('audio_player','nb_tracks') ) {
				warn "\nWARNING : not enough player tracks defined at project level!\n Some audio files won't play, check configuration.\n\n";
				next;
			}
			$line .= " -o:jack,,out_$output";
			push (@audio_players,$line);
		}
		print "  Found " . (scalar @audio_players) . " valid audio files to play for song $friendlysongname\n";
		if ($debug) {
			print "\nPLAYER CHAINS\n";
			print Dumper (@audio_players);
		}
		#----------------------------------------------------------------
		# --- Création du fichier ecs ecasound for the song ---
		&build_ecasound_header('player','sync');
		#TODO : option to keep ecasound opened after transport stop
		#TODO : check autostart option
		my $songname = $ini_song->val('global','name');
		open FILE, ">$basedir/$folder/$songname.ecs" or die $!;
		print FILE "#General\n";
		print FILE "$ecasound_header\n";
		print FILE "\n#CHAINS\n";
		print FILE "$_\n" for @audio_players;
		print FILE "\n";
		close FILE;
		print "  ecs file successfully created for song $friendlysongname\n";
		#insertion du chain setup dans la liste
		push (@cs_list,"$basedir/$folder/$songname.ecs");
	}
	else {
		# TODO : no song.ini file found, try to guess
		#warn "no song.ini file found, trying to guess\n";		
	}
}
undef @songfolderlist;
#create the lsit of player chainsetups to load of project start
my @validsonglist;
open FILE, ">>$basedir/$files_folder/players_cs" or die $!;
foreach(@cs_list){
	if( ( defined $_) and !($_ =~ /^$/ )){
		print FILE "$_\n";
      	push(@validsonglist, $_);
    }
}
close FILE;
print scalar @cs_list . " song(s) with valid players \n";

print "\n";
#----------------------------------------------------------------
#----------------------------------------------------------------
#
# === mise à jour du fichier jack.plumbing ===

sub add_plumbing () {
	#Plumbing::Add(shift);
	$plumbing->Add(shift);
}

#----------------------------------------------------------------
#
# === Création du fichier pour le pont midi/OSC ===
#
# using a hash to store the generated midis
# http://stackoverflow.com/questions/13588129/write-to-a-csv-file-from-a-hash-perl


# Fermeture des fichiers
Bridge::Close_file();
#Plumbing::Close();
$plumbing->Close;