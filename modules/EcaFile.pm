#!/usr/bin/perl

package EcaFile;

use strict;
use warnings;

use Data::Dumper;

sub new {
	my $class = shift;
	my $ecahash = shift;
	my $ecsfile = shift;
	
	#create object
	my $ecafile = $mixer_io_ref;
	#add ecs file path to object
	$ecafile->{ecsfile} = $ecsfile;
	$ecafile->{status} = "notcreated";
	bless $ecafile,$class;
print "Ecafile:ECS=$ecsfile\nstruct=".$ecafile->{ecsfile} ;

	#create the file in the specified path
	#print "---Ecafile\n path = $path\n info = $info\n";
	$ecafile->create if (defined $ecsfile);
	#add file header
	$ecafile->build_header if (defined $mixer_io_ref);

	return $ecafile;
}

sub create {
	#create the file (overwrite)
	my $ecafile = shift;
	my $path = $ecafile->{ecsfile};
	print "---Ecafile:create\n path = $path\n";
	die "no path to create ecs file\n" unless (defined $path);
	open my $handle, ">$path" or die $!;
	#update mixer status
	$ecafile->{status} = "new";
}
sub open_add {
	#open a filehandle to the file (rw add)	
	my $ecafile = shift;
	my $ecsfile = $ecafile->{ecsfile};
	open my $handle, ">>$ecsfile" or die $!;
}
sub close {
	#close the filehandle to the file
	my $ecafile = shift;
	close $ecafile->{ecsfile};
}
sub build_header {
	my $ecafile = shift;
	#print Dumper $ecafile;
	my $name = $ecafile->{name};
	my $header = "#GENERAL\n";
	$header .= "-b:".$ecafile->{buffersize} if $ecafile->{buffersize};
	$header .= " -r:".$ecafile->{realtime} if $ecafile->{realtime};
	my @zoptions = split(",",$ecafile->{z});
	foreach (@zoptions) {
		$header .= " -z:".$_;
	}
	$header .= " -n:\"$name\"";
	$header .= " -z:mixmode,".$ecafile->{mixmode} if $ecafile->{mixmode};
	$header .= " -G:jack,$name,notransport" if ($ecafile->{sync} == 0);
	$header .= " -G:jack,$name,sendrecv" if ($ecafile->{sync});
	$header .= " -Md:".$ecafile->{midi} if $ecafile->{midi};
	#add header to file
	#print "--Ecafile:build_header\n header = $header\n";
	my $file;
	die "ecs file has not been created" if ($ecafile->{status} eq "notcreated");
	$file = $ecafile->open_add;
	#append to file
	#print $file , $header;
	#update status
	$ecafile->{status} = "header";
}

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