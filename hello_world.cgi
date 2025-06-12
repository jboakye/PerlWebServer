#!/usr/bin/perl
# hello.pl - My first CGI program
#jbdebug
use Data::Dumper;
my $run_id = $ARGV[0];

use DBD::SQLite::Constants ':dbd_sqlite_string_mode';
my $unicode_opt = DBD_SQLITE_STRING_MODE_UNICODE_STRICT;
my $db_file = "/dev/shm/web_server_db";
my $dbh = DBI->connect( "dbi:SQLite:dbname=$db_file;sqlite_string_mode=$unicode_opt", '', '' );

my $sth = $dbh->prepare("SELECT query_string FROM query_string where run_id = ?");
$sth->execute($run_id);
my $query_string = $sth->fetch()->[0];

my $sth = $dbh->prepare("SELECT content FROM content where run_id = ?");
$sth->execute($run_id);
my $content = $sth->fetch()->[0];



print "Content-Type: text/html\n\n";
# Note there is a newline between 
# this header and Data

# Simple HTML code follows

print "<html> <head>\n";
print "<title>Hello, world!</title>";
print "</head>\n";
print "<body>\n";
print Dumper('---- query string  ----', $query_string);
print Dumper('---- content  ----', $content);
print Dumper('--- in actual cgi ---- run id ', $run_id);

print "<h1>Hello, world!</h1>\n";
print "</body> </html>\n";