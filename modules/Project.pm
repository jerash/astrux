#!/usr/bin/perl

package Project;

use strict;
use warnings;
use Data::Dumper;

use Mixer;
use Player;

use Exporter;
our @ISA = 'Exporter';
our @EXPORT = qw($baseurl);

our $baseurl = "/home/seijitsu/";

sub new {
	my $class = shift;
	my $ini_file = shift;

	#init structure
	my $project = {
		'mixers' => {},
		'songs' => {},
		'rules' => {},
	};
	bless $project,$class;

	#if parameter exist, fill from ini file
	$project->init($ini_file) if defined $ini_file;

	return $project; 
}

sub init {
	#grap Project object from argument
	our $project = shift;
	my $ini_project = shift;

	#merge project info
	%$project = ( %{$ini_project->{project}} , %$project );

	#------------------Add mixers------------------------------
	my @mixers = grep (/^mixer_/,keys %{$ini_project});
	foreach my $mixer (@mixers) {
		my $mixername = substr $mixer,6 ;
		print "Project: Creating mixer $mixername\n";
		#create mixer ini input path
		$ini_project->{$mixer}{inifile} = $ini_project->{project}{base_path} . "/" . $ini_project->{project}{mixers_path} . "/" . $ini_project->{$mixer}{inifile};
		#create mixer ecs output path
		my $ecs_file = $ini_project->{project}{base_path} . "/" . $ini_project->{project}{output_path} . "/" . $mixername . ".ecs";
		#create mixer
		$project->{mixers}{$mixername} = Mixer->new($ini_project->{$mixer},$ecs_file);
	}

	#TODO verify if there is one "main" mixer

	print Dumper $project;
	#------------------Add songs------------------------------
	#----------------Add plumbing-----------------------------
	
}
sub AddSongs {
	my $project = shift;
# 	#my $player = Player->new();
	#TODO : deal with players ecs chains
	return;
}
sub Create_OscMidiBridge {	
	# 	#------------------------BRIDGE-----------------------------------
	# 	#create/reset the oscmidipath file
	# 	Bridge::Init_file();	
	#
	# 	Bridge::Close_file();
	return;
}
sub Create_Plumbing {
	# 	#------------------------PLUMBING-----------------------------------
	# 	#create/reset the plumbing file
	# 	my $plumbing = Plumbing->new($ini_project);	
	#
	# 	$plumbing->Close;
	return;
}

# #----------------------------------------------------------------
# print "\n---SUBMIXES---\n";
# #----------------------------------------------------------------
# #
# # === Création des fichiers ecs submixes ===
# #

# foreach my $submix_ini (@ini_submixes) {
# 	my $ini_submix = new Config::IniFiles -file => "$config_folder/$submix_ini";
# 	die "reading submix ini file failed\n" until $ini_submix;
# 	#grab submix name, truncate submix_ prefix, and .ini suffix
# 	my $submix_name = substr $submix_ini, 7, -4 ;

# 	my @submix_tracks; #liste des pistes i/o
# 	@input_sections = $ini_submix->Sections;
# 	print "\nFound " . (scalar @input_sections) . " submix track definitions in ini file\n";
# 	#pour chaque entrée définie dans le fichier ini, construction des lignes d'io
# 	while (my $section = shift @input_sections) {
# 		my $found_output = 0;
# 		my $line;
# 		#récupérer le numéro de la section
# 		my $number = substr $section, -2, 2;
# 		#check if input or output
# 		if ( $ini_submix->val($section,'type') eq 'input' ) {
# 			#si piste mono, ajouter mono_panvol (-pn:mono2stereo -epp:50)
# 			if ( $ini_submix->val($section,'channels') eq 1 ) {
# 				$line = "-a:$number -f:f32_le,1,48000 -i:jack,,";
# 				#récupérer le nom de la piste
# 				die "must have a track name\n" until ( $ini_submix->val($section,'name') );
# 				#TODO check for name uniqueness
# 				$line .= $ini_submix->val($section,'name');
# 				#get default values
# 				my @def_dump = MidiCC::Get_defaults("mono_panvol");
# 				$line .= " -pn:mono_panvol" . $def_dump[1] if $def_dump[0];
# 				if ($create_midi_CC) {
# 					#ajouter les contrôleurs midi
# 					my $path = "/$eca_mixer/submix/$submix_name/" . $ini_submix->val($section,'name') . "/panvol";
# 					my @CC_dump = MidiCC::Generate_km("mono_panvol",$path);
# 					#status is in first parameter, km info is in second parameter
# 					$line .= $CC_dump[1] if $CC_dump[0];
# 				}
# 			}
# 			#sinon, piste stéréo par défaut
# 			elsif ( $ini_submix->val($section,'channels') eq 2 ) {
# 				$line = "-a:$number -f:f32_le,2,48000 -i:jack,,";
# 				#récupérer le nom de la piste
# 				die "must have a track name\n" until ( $ini_submix->val($section,'name') );
# 				#TODO check for name uniqueness
# 				$line .= $ini_submix->val($section,'name');
# 				#get default values
# 				my @def_dump = MidiCC::Get_defaults("st_panvol");
# 				$line .= " -pn:st_panvol" . $def_dump[1] if $def_dump[0];
# 				if ($create_midi_CC) {
# 					#ajouter les contrôleurs midi
# 					my $path = "/$eca_mixer/submix/$submix_name/" . $ini_submix->val($section,'name') . "/panvol";
# 					my @CC_dump = MidiCC::Generate_km("st_panvol",$path);
# 					#status is in first parameter, km info is in second parameter
# 					$line .= $CC_dump[1] if $CC_dump[0];
# 				}	
# 			}
# 			#ajouter channel inserts (seulement pour les inputs, TODO for outputs)
# 			if (( $ini_submix->val($section,'insert') ) && ($ini_submix->val($section,'type') eq 'input') ) {
# 				#verify how many inserts are defined
# 				my @inserts = split(",", $ini_submix->val($section,'insert') );
# 				foreach my $insert ( @inserts ) {
# 					# TODO : split on | for parralel effects ?
# 					#print "one effect here : $insert\n";
# 					#get default values
# 					my @def_dump = MidiCC::Get_defaults($insert);
# 					$line .= " -pn:$insert" . $def_dump[1] if $def_dump[0];
# 					if ($create_midi_CC) {
# 						#ajouter les contrôleurs midi
# 						my $path = "/$eca_mixer/inputs/" . $ini_submix->val($section,'name') . "/$insert";
# 						my @CC_dump = MidiCC::Generate_km($insert,$path);
# 						#status is in first parameter, km info is in second parameter
# 						$line .= $CC_dump[1] if $CC_dump[0];
# 					}
# 				}
# 			}
# 		}
# 		elsif ( $ini_submix->val($section,'type') eq 'output' ) {
# 			die "submix output must be stereo" if ($ini_submix->val($section,'channels') ne 2);
# 			$line = "-a:all -f:f32_le,2,48000 -o:jack,,";
# 			#récupérer le nom de la piste
# 			die "must have a track name\n" until ( $ini_submix->val($section,'name') );
# 			#TODO check for uniqueness
# 			$line .= $ini_submix->val($section,'name') . "_out";
# 			$found_output = 1;
# 		}
# 		elsif ($found_output == 1) {
# 			die "only one outbut bus should exist\n";
# 		}
# 		else {
# 			die "unknown track type in submix file\n";
# 		}	
# 		push(@submix_tracks,$line);
# 	}

# 	print "Found " . (scalar @submix_tracks) . " valid submix track definitions in $submix_ini\n";
# 	if ($debug) {
# 		print "\nSUBMIX CHAINS\n";
# 		print Dumper (@submix_tracks);
# 	}
# 	#----------------------------------------------------------------
# 	# --- Création du fichier ecs ecasound ---
# 	#$ecasound_header = "-b:128 -r:50 -z:nodb -z:nointbuf -n:\"$submix_name\" -X -z:noxruns -z:mixmode,avg -G:jack,$submix_name,notransport -Md:alsaseq,16:0";
# 	Mixer::build_header($submix_name,'nosync');
# 	open FILE, ">$files_folder/$submix_name.ecs" or die $!;
# 	print FILE "#General\n";
# 	print FILE "$ecasound_header\n";
# 	print FILE "\n#CHAINS\n";
# 	print FILE "$_\n" for @submix_tracks;
# 	print FILE "\n";
# 	close FILE;
# 	print "\necs file successfully created\n";
# }

# #----------------------------------------------------------------
# print "\n---PLAYERS---\n";
# #----------------------------------------------------------------
# #
# # === Création des fichiers ecs pour chaque chanson ===
# #
# my $basedir = $ini_project->val('project','basefolder');
# #get the song folder names into an array
# opendir (DIR,$basedir) or die "Can't open project directory : $basedir\n";
# my @songfolderlist = grep { /^[0-9][0-9].*/ } readdir(DIR);
# closedir DIR;
# #verify if there is something to be done
# my $numberofsongs = @songfolderlist;
# die "No songs have been found, exiting\n" unless ($numberofsongs > 0);
# #display the number of songs we found
# print "\n" . $numberofsongs . " song folder found\n";

# my @cs_list; #liste des chain setup player à charger au démarrage du projet
# foreach my $folder(@songfolderlist) {
# 	my @audio_players; #liste des fichiers audio à lire
# 	#look for song.ini
# 	if (-e -r "$basedir/$folder/song.ini") {
# 		#song ini file
# 		my $ini_song = new Config::IniFiles -file => "$basedir/$folder/song.ini"; # -allowempty => 1;
# 		die "reading song ini file failed\n" unless $ini_song;
# 		#song name
# 		my $friendlysongname = $ini_song->val('global','friendly_name');
# 		print "  - $friendlysongname -\n";
# 		my @song_sections = $ini_song->Sections;
# 		while (my $section = shift @song_sections) {
# 			#on cherche les audio files
# 			next unless $section =~ /AUDIO/;
# 			#grab the track number
# 			my $number = substr $section, -2, 2;
# 			#verify if file to play is accessible
# 			my $filename = $ini_song->val($section,'filename');
# 			next unless -e -r "$basedir/$folder/$filename";
# 			#create ecasound input line
# 			my $line = "-a:$number -i:$basedir/$folder/$filename";
# 			#deal with mono/stereo, 
# 			my $f = Audio::SndFile->open("<","$basedir/$folder/$filename");
# 			if ( $f->channels == 1 ) {
# 				my @def_dump = MidiCC::Get_defaults("mono_panvol");
# 				#ajouter mono_panvol (-erc:1,2 -epp -eadb)
# 				$line .= " -pn:mono_panvol" . $def_dump[1] if $def_dump[0];
# 			}
# 			#don't deal with file format conversion; let ecasound do it well
# 			# TODO : midi CC for players tracks, generic ones ...
# 			#output line
# 			my $output = $ini_song->val($section,'output'); #sys_player ok
# 			if ( $output > $ini_project->val('audio_player','nb_tracks') ) {
# 				warn "\nWARNING : not enough player tracks defined at project level!\n Some audio files won't play, check configuration.\n\n";
# 				next;
# 			}
# 			$line .= " -o:jack,,out_$output";
# 			push (@audio_players,$line);
# 		}
# 		print "  Found " . (scalar @audio_players) . " valid audio files to play for song $friendlysongname\n";
# 		if ($debug) {
# 			print "\nPLAYER CHAINS\n";
# 			print Dumper (@audio_players);
# 		}
# 		#----------------------------------------------------------------
# 		# --- Création du fichier ecs ecasound for the song ---
# 		Mixer::build_header('player','sync');
# 		#TODO : option to keep ecasound opened after transport stop
# 		#TODO : check autostart option
# 		my $songname = $ini_song->val('global','name');
# 		open FILE, ">$basedir/$folder/$songname.ecs" or die $!;
# 		print FILE "#General\n";
# 		print FILE "$ecasound_header\n";
# 		print FILE "\n#CHAINS\n";
# 		print FILE "$_\n" for @audio_players;
# 		print FILE "\n";
# 		close FILE;
# 		print "  ecs file successfully created for song $friendlysongname\n";
# 		#insertion du chain setup dans la liste
# 		push (@cs_list,"$basedir/$folder/$songname.ecs");
# 	}
# 	else {
# 		# TODO : no song.ini file found, try to guess
# 		#warn "no song.ini file found, trying to guess\n";		
# 	}
# }
# undef @songfolderlist;
# #create the lsit of player chainsetups to load of project start
# my @validsonglist;
# open FILE, ">>$basedir/$files_folder/players_cs" or die $!;
# foreach(@cs_list){
# 	if( ( defined $_) and !($_ =~ /^$/ )){
# 		print FILE "$_\n";
#       	push(@validsonglist, $_);
#     }
# }
# close FILE;
# print scalar @cs_list . " song(s) with valid players \n";

1;