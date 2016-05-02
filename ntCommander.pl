#!/usr/bin/perl

##############################################################
# ntCommander
# List, Add, Change zone records via command line
# Author: sergio.cricca@vipsnet.net
# License: MIT
##############################################################
use warnings;
use strict;
use NicToolServerAPI;
use Getopt::Long;
use Data::Dumper qw(Dumper);
use Switch;

use vars qw( $opts $sid @zones @zonenames );
use vars qw( $ntconf $nt $ntuser $zones $records $record );

$| = 1;
no warnings "uninitialized";
GetOptions(
    "username=s"    => \( my $username ),                 
    "password|p=s"    => \( my $password ),                 
    "domain=s"    => \( my $domain ),                 
    "host=s"    => \( my $host ),                 
    "port=s"    => \( my $port = "8082" ),                 
    "record=s"   => \( my $recordType ),
    "filters=s"		=> \( my $recordFilters ),
    "action=s"	=> \( my $action),
    "new=s"		=> \( my $newRecordValues)	  
) or die "Error in command line arguments";

my @filters = split /;/, $recordFilters if ($recordFilters);
my @outputArray;

$ntconf = {     ntuser  => $username,
                ntpass  => $password,
                nthost  => $host,
                ntport  => $port,
        };

my $i="";
my $total_pages="";

# Set up the NicTool object
$nt = new NicToolServerAPI;
$NicToolServerAPI::server_host = $ntconf->{nthost};
$NicToolServerAPI::server_port = $ntconf->{ntport};
$NicToolServerAPI::data_protocol = "soap";
#$NicToolServerAPI::use_https_authentication = 0;

# Get a NicTool user object
$ntuser = $nt->send_request(
                action   => "login",
                username => $ntconf->{ntuser},
                password => $ntconf->{ntpass},
        );

if( $ntuser->{error_code} ) {
        print( "*** Unable to log in: " . $ntuser->{error_code} . " " . $ntuser->{error_msg} . "\n" );
        exit 1;
}

sub editRecord {
	
	my ($recordID, $zoneID, $recordValues) = @_;
	my @editValues = split /;/, $recordValues if ($recordValues);
	
	my %editRequest = (
	        nt_user_session   => $ntuser->{nt_user_session},
	        nt_group_id       => $ntuser->{nt_group_id},
			nt_zone_id		  => $zoneID
	);
	
	if ($recordID ne 'NULL') {
		$editRequest{nt_zone_record_id} = $recordID;
		$editRequest{action} = "edit_zone_record";
	}
	else
	{
		$editRequest{nt_zone_record_id} = '';
		$editRequest{action} = "new_zone_record";
	}
	
	foreach my $editVal (@editValues){
		my ($field, $value) = split /::/,$editVal;
		$editRequest{$field} = $value;
	}
		
	my $editOutput = $nt->send_request(%editRequest);
	push @outputArray,"added record: ".$editOutput->{nt_zone_record_id}."\n";
	
}

sub getRecords {		
	
	my $nt_zone_id =$_[0];
	
	my %recordsRequest = (
	        action            => "get_zone_records",
	        nt_user_session   => $ntuser->{nt_user_session},
	        nt_group_id       => $ntuser->{nt_group_id},
			nt_zone_id		  => $nt_zone_id,
			include_subgroups => 1,
	        limit             => 50
	);
	$recordsRequest{"Search"} = 1 if ($recordFilters);
	
	my $myCounter=0;
	foreach my $filter (@filters){
		my ($field, $value) = split /::/,$filter;
		$myCounter++;
		$recordsRequest{$myCounter.'_inclusive'} = 'And';
		$recordsRequest{$myCounter.'_field'} = $field;
		$recordsRequest{$myCounter.'_option'} = 'equals';
		$recordsRequest{$myCounter.'_value'} = $value;
	}
	
	
	$records = $nt->send_request(%recordsRequest);
	
	if( $records->{total} == 0 ) {
	        #warn( "*** No record defined.\n\n" );
	        pop @outputArray;
	}
	my $total_pages_records = $records->{total_pages};
	if ($total_pages_records){
		foreach my $recordsPage (1..$total_pages_records){
				$recordsRequest{'page'} = $recordsPage;
		        $records = $nt->send_request(%recordsRequest);
			foreach( @{$records->{records}} ) {
				switch (lc $action) {
					case "list"		{ 
										my $weight;
										if ( $_->{weight} ) { $weight=" weight: ".$_->{weight}; }
										push @outputArray, "\tRECORDID: ".$_->{nt_zone_record_id}." = ".$_->{name}." (".$_->{type}.") ".$_->{address}." [ttl: ".$_->{ttl}.$weight."]\n"; }
					case "delete" 	{ deleteRecord($_->{nt_zone_record_id}, $nt_zone_id); }
					case "change"	{ editRecord($_->{nt_zone_record_id}, $nt_zone_id, $newRecordValues); }
				}
			}
		}
	}	
} 
#-------------------------------------------------------------------------------

my %zoneRequest = (action => "get_group_zones",
        nt_user_session => $ntuser->{nt_user_session},
        nt_group_id => $ntuser->{nt_group_id},
        include_subgroups => 1,
        limit => 50);

if (defined $domain){
	$zoneRequest{'Search'} = 1;
	$zoneRequest{'1_field'} = 'zone';
	$zoneRequest{'1_option'} = 'equals';
	$zoneRequest{'1_value'} = $domain;
}

$zones = $nt->send_request(%zoneRequest);

if( $zones->{total} == 0 ) {
        warn( "*** No zones defined.\n\n" );
}



$total_pages = $zones->{total_pages};

foreach my $page (1..$total_pages){
		$zoneRequest{'page'} = $page;
        $zones = $nt->send_request(%zoneRequest);
        
        foreach( @{$zones->{zones}} ) {
	        	push @outputArray, "### DNS Zone: ".$_->{zone}."\n";
	        	switch (lc $action) { 
	        		case "add" 		{ editRecord('NULL',$_->{nt_zone_id}, $newRecordValues); }
					else			{ getRecords($_->{nt_zone_id}); }
				}
		}
}

foreach (@outputArray) {
  print "$_";
}

#-------------------------------------------------------------------------------

$ntuser = $nt->send_request( action => "logout", );
