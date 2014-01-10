#!/usr/bin/perl

package Project;

use strict;
use warnings;
use Data::Dumper;

use Mixer;
use Song;

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
	my $project = shift;
	my $ini_project = shift;

	#merge project ini info
	%$project = ( %{$ini_project} , %$project );

	#------------------Add mixers-----------------------------
	$project->AddMixers;	

	#------------------Add songs------------------------------
	#TODO
	$project->AddSongs;	

	#----------------Add plumbing-----------------------------
	#TODO
}

sub AddMixers {
	my $project = shift;

	#build path to mixers files
	my $mixers_path = $project->{project}{base_path} . "/" . $project->{project}{mixers_path};
	
	#iterate through each mixer file
	my @files = <$mixers_path/*.ini>;
	foreach my $mixerfile (@files) {

		#create mixer
	 	print "Project: Creating mixer from $mixerfile\n";
	 	my $mixer = Mixer->new($mixerfile);
		$project->{mixers}{$mixer->{ecasound}{name}} = $mixer;
	}

	#verify if there is one "main" mixer
	if (!exists $project->{mixers}{"main"} ) {
		die "!!!! main mixer must exist !!!!!\n";
	}
}

sub AddSongs {
	my $project = shift;
# 	#my $player = Player->new();
	#TODO : deal with players ecs chains

	#build path to songs folder
	my $songs_path = $project->{project}{base_path} . "/" . $project->{project}{songs_path};
	
	#get song list
	my @songs_folders = <$songs_path/*>;

	#iterate through each song fodlder
	foreach my $folder (@songs_folders){

		#ignore files, use directories only
		next if (! -d $folder);
		print " Songs folder : $folder\n";

		#crete a song object
		my $song = Song->new($folder);

		#update the project with song info
		$project->{songs}{$song->{song_globals}{name}} = $song;
	}
}

sub CreateEcsFiles {
	my $project = shift;

	#for each mixer, create the ecasound mixer file
	foreach my $mixername (keys %{$project->{mixers}}) {
		#shorcut name
		my $mixer = $project->{mixers}{$mixername};
		#create path to ecs file
		my $ecsfilepath = $project->{project}{base_path}."/".$project->{project}{output_path}."/".$mixer->{ecasound}{name} . ".ecs";
		#add path to ecasound info
		$mixer->{ecasound}{ecsfile} = $ecsfilepath;
		#bless structure to access data with module functions
		bless $mixer->{ecasound} , EcaFile::;
		#create the file
		$mixer->{ecasound}->create;
		#add ecasound header to file
		$mixer->{ecasound}->build_header;
		#get chains from structure
		$mixer->get_ecasoundchains;
		#add chains to file
		$mixer->{ecasound}->add_chains;
		#TODO verify is the generated file can be opened by ecasound
		#$mixer->{ecasound}->verify;
	}

	#TODO : for each song, create the ecasound player file		
	foreach my $songname (keys %{$project->{songs}}) {
		#shorcut name
		my $song = $project->{songs}{$songname};
		#create path to ecs file
		my $ecsfilepath = $project->{project}{base_path}."/songs/$songname/chainsetup.ecs";
		#add path to song info
		$song->{ecasound}{ecsfile} = $ecsfilepath;
		#bless structure to access data with module functions
		bless $song->{ecasound} , EcaFile::;
		#create the file
		$song->{ecasound}->create;
		#copy header from player mixer
		if (defined $project->{mixers}{players}{ecasound}{header}) {
			$song->{ecasound}{header} = $project->{mixers}{players}{ecasound}{header};
		}
		else {
			die "Error : can't find a player mixer header\n";
		}
		#add ecasound header to file
		$song->build_song_header;
		#add chains to file
		$song->add_songfile_chain;
		#TODO verify is the generated file can be opened by ecasound
		#$song->{ecasound}->verify;
	}

}

sub SaveTofile {
	my $project = shift;

}

sub CreateOscMidiBridge {	
	# 	#------------------------BRIDGE-----------------------------------
	# 	#create/reset the oscmidipath file
	# 	Bridge::Init_file();	
	#
	# 	Bridge::Close_file();
	return;
}
sub CreatePlumbing {
	# 	#------------------------PLUMBING-----------------------------------
	# 	#create/reset the plumbing file
	# 	my $plumbing = Plumbing->new($ini_project);	
	#
	# 	$plumbing->Close;
	return;
}


1;