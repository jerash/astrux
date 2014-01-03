#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

my %htrux ;
my %insert;

#$htrux{"test"} = 4;

my $engine = "live";
#----DAIEN
my %values = ("1.pan"=>50,"2.vol"=>-3,"3.loow"=>12,"4.mid"=>6.5,"5.high"=>0);
foreach my $nam (sort keys %values) {
	$insert{"micstrip"}{$nam} = $values{$nam};
#	print "name : ", $nam, " value : ", $values{$nam}, "\n";
}

print Dumper \%insert;
#$htrux{$engine}{"Diane"}{"micstrip"}{keys %$_} = values %$_ foreach (%values);

#----RFA
#%values = ("pan",0,"vol",0,"low",0,"mid",0,"high",0.0);
#$htrux{$engine}{"Diane"}{"micstrip"}{keys %values} = values %values;

#$htrux{$engine}{"Raf"} = ( 
#	"micstrip" => {
#	}
 #);

#print Dumper \%htrux;