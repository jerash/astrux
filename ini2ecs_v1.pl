#!/usr/bin/perl
use strict;
use warnings;

require ("modules/MidiCC.pm");

#----------------------------------------------------------------
# This script will create a main mixer ecs file for ecasound based on the information contained in ini files
# It will unconditionnaly overwrite any previoulsy existing ecs file with the same name.
#----------------------------------------------------------------

use Data::Dumper;
use Config::IniFiles;

my $ini_inputs = new Config::IniFiles -file => "fakein.ini"; # -allowempty => 1;
die "reading inputs ini file failed\n" until $ini_inputs;

my $ini_outputs = new Config::IniFiles -file => "fakeout.ini"; # -allowempty => 1;
die "reading outputs ini file failed\n" until $ini_outputs;

my $debug = 0;

#----------------------------------------------------------------
#
# === variables contenant les lignes à insérer dans le fichier ecs ===
#
my @ecasound_header = ("-b:128 -r:50 -z:intbuf -z:nodb -z:nointbuf -n:\"mixer\" -X -z:noxruns -z:mixmode,avg -G:jack,mixer,notransport -Md:alsaseq,16:0");
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
# === Génération des lignes à insérer ===

#----------------------------------------------------------------
# -- CHANNELS audio inputs --
my @input_sections = $ini_inputs->Sections;
print "\nFound " . (scalar @input_sections) . " input definitions in ini file\n";
#pour chaque entrée définie dans le fichier ini
#construction de la ligne d'input
while (my $section = shift @input_sections) {
	#si entrée invalide, suivante
	next until ( $ini_inputs->val($section,'status') eq 'active' );
	next until ( $ini_inputs->val($section,'type') eq 'audio' ) or ( $ini_inputs->val($section,'type') eq 'return' );
	#récupérer le numéro de la section
	my $number = substr $section, -2, 2;
	my $line = "-a:$number -f:f32_le,1,48000 -i:jack,,";
	#récupérer le nom de la piste
	next until ( $ini_inputs->val($section,'name') );
	$line .= $ini_inputs->val($section,'name');
	#si piste mono, ajouter mono_panvol (-pn:mono2stereo -epp:50)
	if ( $ini_inputs->val($section,'channels') eq 1 ) {
		$line .= " -pn:mono_panvol";
		#TODO : get default values
		my @def_dump = MidiCC::get_defaults("mono_panvol");
		$line .= $def_dump[1] if $def_dump[0];
		#ajouter les contrôleurs midi
		my @CC_dump = MidiCC::generate_km("mono_panvol");
		#status is in first parameter, km info is in second parameter
		$line .= $CC_dump[1] if $CC_dump[0];
	}
	#sinon, piste stéréo par défaut
	elsif ( $ini_inputs->val($section,'channels') eq 2 ) {
		$line .= " -pn:st_panvol";
		#TODO : get default values
		my @def_dump = MidiCC::get_defaults("st_panvol");
		$line .= $def_dump[1] if $def_dump[0];
		#ajouter les contrôleurs midi
		my @CC_dump = MidiCC::generate_km("st_panvol");
		#status is in first parameter, km info is in second parameter
		$line .= $CC_dump[1] if $CC_dump[0];	
	}
	#ajouter channel strip 
		#TODO
	#section valide
	 #ajoute à la liste des sections valides
	push(@valid_input_sections,$section);
	 #ajoute la ligne à la liste des ai
	push(@inputs_ai,$line);
	 #crée la sorite loop
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
my @output_sections = $ini_outputs->Sections;
print "\nFound " . (scalar @output_sections) . " output definitions in ini file\n";
#pour chaque entrée définie dans le fichier ini
#vérification de la validité de la sortie
while (my $section = shift @output_sections) {
	#si entrée invalide, suivante
	next until ( $ini_outputs->val($section,'status') eq 'active' );
	next until ( $ini_outputs->val($section,'type') eq 'bus' ) or ( $ini_outputs->val($section,'type') eq 'send' );
	next until ( $ini_outputs->val($section,'name') );
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
	#ignore send bus to himlself
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
		push(@channels_ao,$line);
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
foreach my $bus (@valid_output_sections) {
	#outputbus_ai
	my $line = "-a:bus_";
	$line .= "send_" if ($ini_outputs->val($bus,'type') eq 'send');
	$line .= $ini_outputs->val($bus,'name');
	$line .= " -f:f32_le,2,48000 -i:jack,,bus_";
	$line .= "send_" if ($ini_outputs->val($bus,'type') eq 'send');
	$line .= $ini_outputs->val($bus,'name');
	push(@outputbus_ai,$line);
	#outputbus_ao
	$line = "-a:bus_";
	$line .= "send_" if ($ini_outputs->val($bus,'type') eq 'send');
	$line .= $ini_outputs->val($bus,'name');
	$line .= " -f:f32_le,2,48000 -o:jack,,";
	$line .= $ini_outputs->val($bus,'name');
	$line .= "_out";
	push(@outputbus_ao,$line);
}
if ($debug) {
	print "\nBUS OUTPUTS CHAINS\noutputbus_ai\n";
	print Dumper (@outputbus_ai);
	print "outputbus_ao\n";
	print Dumper (@outputbus_ao);
}
#----------------------------------------------------------------
#
# === Création du fichier ecs ecasound ===
# -- entête --

open FILE, ">mixer.ecs" or die $!;

print FILE "#General\n";
print FILE "$_\n" for @ecasound_header;
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
#
# === Création du fichier jack.plumbing ===


#----------------------------------------------------------------
#
# === Création du fichier pour le pont midi/OSC ===
#
# using a hash to store the generated midis
# http://stackoverflow.com/questions/13588129/write-to-a-csv-file-from-a-hash-perl