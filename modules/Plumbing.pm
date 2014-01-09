#!/usr/bin/perl

package Plumbing;

use strict;
use warnings;

use Config::IniFiles;

my $debug = 0;
#-----------------------PROJECT INI---------------------------------
#project file
# my $ini_project = new Config::IniFiles -file => "project.ini";
# die "reading project ini file failed\n" until $ini_project;
# #folder where to store generated files
# #do we generate plumbing file ?
# my $do_plumbing = $ini_project->val('jack.plumbing','enable');
#--------------------------------------------------------------------

sub new {
	my $class = shift;
	my $ini_project = shift;

	if ( $ini_project->{'jack.plumbing'}{'enable'} == 1 ) {
		my $files_folder = $ini_project->{'project'}{'filesfolder'};
		open my $file, ">$files_folder/jack.plumbing" or die $!;
		bless $file, $class;
		return $file;
  	} else {
  		warn "Plumbing not activated!!\n";
  		return undef;
  	}
}
  
sub Add {
	if (my $file = shift) {
		my $message = shift;
		print $file $message . "\n";
	} else {
		warn "Plumbing not activated!!\n";
	}
}
sub Close {
	close shift;
}


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

# #foreach valid bus
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

# #----------------------------------------------------------------
# # -- BUS SENDS --
# $plumbing->Add(";buses");
# foreach my $bus (@valid_output_sections) {
# 	#ajouter la règle de plumbing
# 	for my $i (1..2) {
# 		my $plumbin = "$eca_mixer:" . $mixer->{IOs}->val($bus,'name') . "_out_$i";
# 		my $plumbout = $mixer->{IOs}->val($bus,"hardware_output_$i");
# 		$plumbing->Add("(connect \"$plumbin\" \"$plumbout\")") if $plumbout;
# 	}
# }


1;