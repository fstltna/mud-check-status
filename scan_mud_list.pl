#!/usr/bin/perl

# This tool scans all the entries in the JV-LD database to see
# if they are functional or not

use strict;
use warnings;
use IO::Socket::PortState qw(check_ports);
use DBI;
use Email::Simple;
use Email::Simple::Creator;
use Email::Sender::Simple qw(sendmail);

# No changes below here
my $CurHost="";
my $CurPort=0;
my $CurId=0;
my $CurStatus="";
my $timeout=5;
my $VERSION="1.0";
my $DB_Owner="";
my $DB_Pswd="";
my $DB_Name="";
my $DB_Prefix="";
my $DB_Table="";
my $dbh;
my $CONF_FILE="/root/mud-check-status/config.ini";
my $EMAIL_SUBJ="";
my $EMAIL_FROM="";
my $CurNotify="";
my $email="";

# Read in configuration options
open(CONF, "<$CONF_FILE") || die("Unable to read config file '$CONF_FILE'");
while(<CONF>)
{
	chop;
	my ($FIELD_TYPE, $FIELD_VALUE) = split (/	/, $_);
	#print("Type is $FIELD_TYPE\n");
	if ($FIELD_TYPE eq "DB_User")
	{
		$DB_Owner = $FIELD_VALUE;
	}
	elsif ($FIELD_TYPE eq "DB_Pswd")
	{
		$DB_Pswd = $FIELD_VALUE;
	}
	elsif ($FIELD_TYPE eq "DB_DBName")
	{
		$DB_Name = $FIELD_VALUE;
	}
	elsif ($FIELD_TYPE eq "DB_DBtblpfx")
	{
		$DB_Prefix = $FIELD_VALUE;
	}
	elsif ($FIELD_TYPE eq "Email_Subj")
	{
		$EMAIL_SUBJ = $FIELD_VALUE;
	}
	elsif ($FIELD_TYPE eq "Email_From")
	{
		$EMAIL_FROM = $FIELD_VALUE;
	}
}
close(CONF);

if ($EMAIL_SUBJ eq "")
{
	print "You have not set a email subject in $CONF_FILE\n";
	exit 1;
}
if ($EMAIL_FROM eq "")
{
	print "You have not set a email sender in $CONF_FILE\n";
	exit 1;
}

# Marks the MUD state and check time
sub MarkMUD
{
	my($day, $month, $year)=(localtime)[3,4,5];
	$year += 1900;
	$month += 1;
	$month = substr("0".$month, -2);
	$day = substr("0".$day, -2);
	my $timeString="$year-$month-$day";
	# Field5 = date in "0000-00-00"
	# Field6 = status in "Active/Unreachable" format
	$dbh->do("UPDATE $DB_Table SET Field5 = ?, Field6 = ? WHERE id = ?",
		undef,
		$timeString,
		$CurStatus,
		$CurId);
	# Should we send owner a note?
	if (($CurStatus eq "Unreachable") && ($CurNotify ne ""))
	{
		my $CurBody = <<"END_MESSAGE_BODY";
Dear $CurNotify,
 
At our last scan of your MUD we could not connect to it. You may want to look into it or disable notifications if you don't want to get these messages in the future.

Next check will be in roughly 6 hours.
 
Regards,
The Admins at PocketMUD
END_MESSAGE_BODY
		$email = Email::Simple->create(
		header => [
		       From => $EMAIL_FROM,
		       To => $CurNotify,
		       Subject => $EMAIL_SUBJ,
		],
		body => $CurBody);
		sendmail($email);
	}
}

# Checks to see if the MUD is up
sub CheckMUD
{
	my %port_hash = (
		tcp => {
			$CurPort => {},
		}
	);

	my $host_hr = check_ports($CurHost, $timeout, \%port_hash);
	$CurStatus = $host_hr->{tcp}{$CurPort}{open} ? "Active" : "Unreachable";
	my $HostTable = sprintf("%-30s : %-5s : %s", $CurHost, $CurPort, $CurStatus);
	print "$HostTable\n";
	MarkMUD();
}

print("MUD Check Status ($VERSION)\n");
print("===============================================\n");

### The database handle
$dbh = DBI->connect ("DBI:mysql:database=$DB_Name:host=localhost",
                           $DB_Owner,
                           $DB_Pswd) 
                           or die "Can't connect to database: $DBI::errstr\n";

$DB_Table = $DB_Prefix . "jvld_links";

#print "DB_Table is $DB_Table\n";

### The statement handle
my $sth = $dbh->prepare("SELECT id, partner_url, field1, field2, field7 FROM $DB_Table");

$sth->execute or die $dbh->errstr;

my $rows_found = $sth->rows;

while (my $row = $sth->fetchrow_hashref)
{
	$CurId = $row->{'id'};
	$CurHost = $row->{'field1'};
	$CurPort = $row->{'field2'};
	$CurNotify = $row->{'field7'};
	# print "Working on '$CurId $CurHost'\n";
	CheckMUD();
}

exit(0);
