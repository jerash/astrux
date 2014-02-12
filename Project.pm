#!/usr/bin/perl

package Project;

use strict;
use warnings;

use Mixer;
use Song;
use Plumbing;
use Bridge;

###########################################################
#
#		 PROJECT OBJECT functions
#
###########################################################

sub new {
	my $class = shift;
	my $ini_file = shift;

	#init structure
	my $project = {
		'mixers' => {},
		'songs' => {},
	};
	bless $project,$class;

	#if parameter exist, fill from ini file
	$project->init($ini_file) if defined $ini_file;

	return $project; 
}

sub init {
	#grap Project object from argument
	my $project = shift;
	my $ini_project = shift;

	#merge project ini info
	%$project = ( %{$ini_project} , %$project );

	#------------------Add mixers-----------------------------
	$project->AddMixers;

	# sanitize effects values, need SAMPLERATE
	$project->Sanitize;

	#------------------Add songs------------------------------
	$project->AddSongs;	

	#----------------Add plumbing-----------------------------
	# MOVED to generates files, after we know the nonmixer auxes

	#----------------Add bridge-----------------------------
	$project->AddOscMidiBridge;
}

###########################################################
#
#		 PROJECT ADD functions
#
###########################################################

sub AddMixers {
	my $project = shift;

	my $foundmain = 0;

	#build path to mixers files
	my $mixers_path = $project->{project}{base_path} . "/" . $project->{project}{mixers_path};
	my $output_path = $project->{project}{base_path} . "/" . $project->{project}{output_path};
	
	#iterate through each mixer file
	my @files = <$mixers_path/*.ini>;
	foreach my $mixerfile (@files) {
	 	print "Project: Creating mixer from $mixerfile\n";

		#create mixer
	 	my $mixer = Mixer->new($mixerfile,$output_path);

	 	#insert into project
		$project->{mixers}{$mixer->{engine}{name}} = $mixer;

		#ecasound mixer need project info
		if ($project->{mixers}{$mixer->{engine}{name}}->is_ecasound) {
			#add the ecaconfig path to mixer
			my $path = $project->{project}{base_path}."/".$project->{project}{eca_cfg_path};
			$project->{mixers}{$mixer->{engine}{name}}{engine}{eca_cfg_path} = $path;
		}

		#check if we have a main mixer
		if ($project->{mixers}{$mixer->{engine}{name}}->is_main) {
			die "Error ...hum we already have a main mixer, can't have two !\n" if $foundmain eq 1;
			$foundmain = 1;
		}
	}

	#verify if there is one "main" mixer
	die "!!!! main mixer must exist !!!!!\n" unless $foundmain;
}

sub AddSongs {
	my $project = shift;

	#build path to songs folder
	my $songs_path = $project->{project}{base_path} . "/" . $project->{project}{songs_path};
	
	#get song list
	my @songs_folders = <$songs_path/*>;

	#iterate through each song fodlder
	foreach my $folder (@songs_folders){

		#ignore files, use directories only
		next if (! -d $folder);
		print "Project: Entering song folder : $folder\n";

		#crete a song object
		my $song = Song->new($folder);

		#update the project with song info
		$project->{songs}{$song->{name}} = $song;
	}
}

sub AddOscMidiBridge {	
	my $project = shift;
	
	$project->{osc2midi}{status} = "notcreated";
	bless $project->{osc2midi}, Bridge::;

	my @bridgelines = Bridge->create_lines($project);
	$project->{osc2midi}{lines} = \@bridgelines;
}

sub AddPlumbing {
	my $project = shift;

	my $plumbingfilepath = $project->{project}{base_path}."/".$project->{project}{output_path}."/jack.plumbing";
	$project->{connections}{file} = $plumbingfilepath;
	bless $project->{connections} , Plumbing::;

	my @plumbing_rules = Plumbing->create_rules($project);
	$project->{connections}{rules} = \@plumbing_rules;
}

###########################################################
#
#		 PROJECT functions
#
###########################################################
sub Sanitize {
	my $project = shift;

	print "Project: Sanitize\n";
	foreach my $mixername (keys %{$project->{mixers}}) {
		#shortcut name
		my $mixer = $project->{mixers}{$mixername};
		#sanitize effect
		$mixer->Sanitize_EffectsParams($project->{AUDIO}{samplerate});
	}	
}

###########################################################
#
#		 PROJECT FILE functions
#
###########################################################

sub GenerateFiles {
	my $project = shift;

	print "Project: generating files\n";
	#----------------MIXERS FILES------------------------
	#for each mixer, create the mixer file/folder
	foreach my $mixername (keys %{$project->{mixers}}) {
		my $mixer = $project->{mixers}{$mixername}->Create_File;
	}

	#----------------SONGS FILES------------------------
	#for each song, create the ecasound player file		
	foreach my $songname (keys %{$project->{songs}}) {
		#shorcut name
		my $song = $project->{songs}{$songname};

		#copy ecasound parameters from players mixer
		my %engine = %{$project->{mixers}{players}{engine}};
		$song->{ecasound} = \%engine;
		bless $song->{ecasound} , EcaEngine::;
		#update name
		# $song->{ecasound}{name} = $songname;
		$song->{ecasound}{name} = "players";
		#update ecsfile path
		my $ecsfilepath = $project->{project}{base_path}."/songs/$songname/chainsetup.ecs";
		$song->{ecasound}{ecsfile} = $ecsfilepath;

		#add io_chains
		$song->build_songfile_chain;
		#create the file
		$song->{ecasound}->CreateEcsFile;
		#remove io_chains
		delete $song->{ecasound}{io_chains} if defined $song->{ecasound}{io_chains};
	}

	#----------------PLUMBING FILE------------------------
	#add the pumbing rules to the project 
	#TODO we do it now after nonmixer files are generetad, so we know the auxes assignations
	$project->AddPlumbing;
	#now generate the file
	if ($project->{connections}{"jack.plumbing"} == 1) {
		#we're asked to generate the plumbing file
		my $plumbingfilepath = $project->{project}{base_path}."/".$project->{project}{output_path}."/jack.plumbing";
		$project->{connections}{file} = $plumbingfilepath;
		print " |_Project: creating plumbing file $plumbingfilepath\n";
		$project->{connections}->create;
		$project->{connections}->save;
	}
	else {
		print " |_Project: jack.plumbing isn't defined as active. Not creating file.\n";
	}

	#----------------OSC2MIDI BRIDGE FILE------------------------
	#TODO define bridge option
	if ($project->{osc2midi}{enable} == 1) {
		#we're asked to generate the bridge file
		my $filepath = $project->{project}{base_path} . "/" . $project->{project}{output_path} . "/oscmidistate.csv";
		$project->{osc2midi}{file} = $filepath;
		print " |_Project: creating osc2midi file $filepath\n";
		$project->{osc2midi}->create;
		$project->{osc2midi}->save;
	}
	else {
		print " |_Project: midi2osc bridge isn't defined as active. Not creating file.";
	}
}

sub SaveTofile {
	my $project = shift;
	my $outfile = shift;

	print "Project: saving project\n";
	#replace any nonalphanumeric character
	$outfile =~ s/[^\w]/_/g;
	$outfile = $project->{project}{base_path}."/".$outfile;

	#we create a dumper file (human readable)
	use Data::Dumper;
	$Data::Dumper::Purity = 1;
	open my $handle, ">$outfile.dmp" or die $!;
	print $handle Dumper $project;
	close $handle;

	# remove all filehandles from structure (storable limitation)
	#TODO also remove AE containing sub (CODE)
	my %hash;
	if (defined $project->{TCP}{socket}) {
		$hash{TCP}{socket} = delete $project->{TCP}{socket};
		$hash{TCP}{events} = delete $project->{TCP}{events};
	}
	if (defined $project->{OSC}{socket}) {
		$hash{OSC}{socket} = delete $project->{OSC}{socket};
		$hash{OSC}{object} = delete $project->{OSC}{object};
		$hash{OSC}{events} = delete $project->{OSC}{events};
	}
	foreach my $mixer (keys $project->{mixers}) {
		$hash{mixers}{$mixer} = delete $project->{mixers}{$mixer}{engine}{socket}; 
	}

	#Storable : create a project file, not working with opened sockets
	$outfile .= ".cfg";
	use Storable;
	$Storable::Deparse = 1; #warn if CODE encountered, but dont die
	store $project, $outfile;

	print " |_Project: saved to $outfile\n";

	# store values back
	if (defined $hash{TCP}{socket}) {
		$project->{TCP}{socket} = delete $hash{TCP}{socket};
		$project->{TCP}{events} = delete $hash{TCP}{events};
	}
	if (defined $hash{OSC}{socket}) {
		$project->{OSC}{socket} = delete $hash{OSC}{socket};
		$project->{OSC}{object} = delete $hash{OSC}{object};
		$project->{OSC}{events} = delete $hash{OSC}{events};
	}
	foreach my $mixer (keys $hash{mixers}) {
		$project->{mixers}{$mixer}{engine}{socket} = delete $hash{mixers}{$mixer}; 
	}
	undef %hash;

}

sub LoadFromFile {
	my $project = shift;
	my $infile = shift;

	use Storable;
	$project = retrieve($infile);
}

###########################################################
#
#		 PROJECT LIVE functions
#
###########################################################

sub StartEngines {
	my $project = shift;

	foreach my $mixername (keys %{$project->{mixers}}) {
		print " - mixer $mixername\n";
		$project->{mixers}{$mixername}->Start;
	}
}

sub execute_command {
	my $project = shift;
	my $command = shift;

	$command =~ s/\s*$//s; #remove trailing whitspaces
	my $reply = '';

	if ($command =~ /^save$/) { 
		$project->SaveTofile("$project->{project}{name}"); 
	}
	elsif ($command =~ /^status$/) { 
		foreach my $mixer (keys %{$project->{mixers}}) {
			$reply = $project->{mixers}{$mixer}{engine}->Status . "\n";
		}
	}
	elsif ($command =~ /^song /) { 
		my $songname = substr $command,5;
		return unless exists $project->{songs}{$songname};
		$reply = "Starting song $songname";
		#loading players
		$reply .= $project->{mixers}{players}{engine}->SelectAndConnectChainsetup($songname);
		#loading midifile
		#TODO oups...jpmidi cannot load a new song & need a2jmidid to connect to some midi out
		#autostart ?
		$reply .= $project->{mixers}{players}{engine}->SendCmdGetReply("start") 
			if $project->{songs}{$songname}{song_globals}{autostart};
	}
	elsif ($command =~ /^play|start$/) { 
		$reply = "Starting play";
		$reply .= $project->{mixers}{players}{engine}->SendCmdGetReply("start");
	}
	elsif ($command =~ /^stop$/) { 
		$reply = "Stopping";
		$reply .= $project->{mixers}{players}{engine}->SendCmdGetReply("stop");
	}
	elsif ($command =~ /^zero$/) { 
		$reply = "back to the beginning";
		$reply .= $project->{mixers}{players}{engine}->SendCmdGetReply("setpos 0");
	}
	elsif ($command =~ /^send/) { 
		my $mixer = grep (/main/,$command); #TODO replace the false grep
		$reply = "to ecasound $command"; 
	}
	elsif ($command =~ /^eca/) {
		my ($mixer, $cmd) =
		$command =~ /eca\s(\S+)\s(.+)$/;
		#TODO check that $cmd is valid
		$reply .= $project->{mixers}{$mixer}{engine}->SendCmdGetReply($cmd) if $project->{mixers}{$mixer};
		# $reply = "to ecasound $command\n"; 
	}
	#default { $reply = "Other"; }
	return $reply;
	}

1;
